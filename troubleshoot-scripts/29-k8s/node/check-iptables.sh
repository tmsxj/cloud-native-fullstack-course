#!/bin/bash
# ============================================================================
# 模块29-K8S故障排查 (节点级)
# 脚本名称: check-iptables.sh
# 功能: iptables/nftables 规则数爆炸诊断
# 用法: ./check-iptables.sh
# 说明: K8s kube-proxy iptables 模式时，Service 多了规则数万条，严重影响性能
# ============================================================================

# ======================== 颜色输出函数定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

# ======================== 退出码定义 ========================
EXIT_CODE=0

echo "============================================================"
echo "          iptables/nftables 规则数诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 0. 检测防火墙后端 ========================
print_info ">>> [0/5] 检测防火墙后端类型 ..."

FIREWALL_TYPE=""
if command -v nft &>/dev/null && nft list ruleset &>/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q 'table'; then
    FIREWALL_TYPE="nftables"
    print_info "检测到 nftables (现代防火墙)"
elif command -v iptables-save &>/dev/null; then
    FIREWALL_TYPE="iptables"
    print_info "检测到 iptables (传统防火墙)"
else
    print_warn "无法确定防火墙类型"
fi

echo ""

# ======================== 1. iptables 各表规则统计 ========================
print_info ">>> [1/5] 统计各表规则数量 ..."

TOTAL_RULES=0
declare -A TABLE_COUNTS

if [ "$FIREWALL_TYPE" = "iptables" ]; then
    TABLES="filter nat mangle raw security"
    for table in $TABLES; do
        COUNT=$(sudo iptables-save -t "$table" 2>/dev/null | grep -vE '^[#*:]' | grep -vE '^$' | grep -v 'COMMIT' | wc -l)
        TABLE_COUNTS[$table]=$COUNT
        TOTAL_RULES=$((TOTAL_RULES + COUNT))
        printf "    %-12s %5d 条\n" "${table}:" "${COUNT}"
    done
elif [ "$FIREWALL_TYPE" = "nftables" ]; then
    # nftables 按 family 统计
    for family in ip ip6 inet; do
        COUNT=$(sudo nft list ruleset "$family" 2>/dev/null | grep -vE '^\s*(table|chain|$|\{|})' | grep -vE '^\s*$' | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            TABLE_COUNTS[$family]=$COUNT
            TOTAL_RULES=$((TOTAL_RULES + COUNT))
            printf "    %-12s %5d 条\n" "${family}:" "${COUNT}"
        fi
    done
fi

echo "    总计规则数:          ${TOTAL_RULES}"

# 阈值判断
if [ "$TOTAL_RULES" -gt 10000 ]; then
    print_fail "iptables 规则总数 > 10000，kube-proxy 性能严重下降！"
    print_info "建议: 迁移到 IPVS 模式或 nftables 后端"
    EXIT_CODE=2
elif [ "$TOTAL_RULES" -gt 5000 ]; then
    print_warn "iptables 规则总数 > 5000，存在性能风险"
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
elif [ "$TOTAL_RULES" -gt 1000 ]; then
    print_ok "iptables 规则数正常"
else
    print_ok "iptables 规则数很少"
fi

echo ""

# ======================== 2. K8s 相关链分析 ========================
print_info ">>> [2/5] 检查 K8s Service 相关规则 ..."

# KUBE-SERVICES / KUBE-SVC-* 链计数
if [ "$FIREWALL_TYPE" = "iptables" ]; then
    KUBE_SVC_COUNT=$(sudo iptables-save 2>/dev/null | grep -oP '^:KUBE-SVC-[A-Z0-9]+' | wc -l)
    KUBE_SEP_COUNT=$(sudo iptables-save 2>/dev/null | grep -oP '^:KUBE-SEP-[A-Z0-9]+' | wc -l)
    KUBE_NODEPORT_COUNT=$(sudo iptables-save 2>/dev/null | grep -c 'KUBE-NODEPORTS')
    KUBE_FW_COUNT=$(sudo iptables-save 2>/dev/null | grep -oP '^:KUBE-FW-[A-Z0-9]+' | wc -l)

    echo "    KUBE-SVC-* 链:       ${KUBE_SVC_COUNT} (每个 ClusterIP Service 一个)"
    echo "    KUBE-SEP-* 链:       ${KUBE_SEP_COUNT} (每个 Endpoint 一个)"
    echo "    KUBE-FW-* 链:        ${KUBE_FW_COUNT} (每个 LoadBalancer Service 一个)"
    echo "    KUBE-NODEPORTS 引用: ${KUBE_NODEPORT_COUNT}"

    # kube-proxy 模式检测
    if pgrep -x kube-proxy &>/dev/null; then
        KUBE_PROXY_MODE=$(ss -tlnp 2>/dev/null | grep kube-proxy | head -1)
        echo ""
        echo "    kube-proxy 当前运行模式:"
        if sudo iptables-save -t nat 2>/dev/null | grep -q 'KUBE-SERVICES'; then
            print_info "    → iptables 模式"
            if [ "$KUBE_SVC_COUNT" -gt 500 ]; then
                print_warn "    Service 数量 > 500，建议迁移到 IPVS 模式"
                echo "    迁移命令: kubectl edit cm kube-proxy -n kube-system"
                echo "    修改 mode: \"ipvs\""
            fi
        fi
    fi
elif [ "$FIREWALL_TYPE" = "nftables" ]; then
    KUBE_SVC_COUNT=$(sudo nft list ruleset 2>/dev/null | grep -c 'kube-svc')
    echo "    k8s 相关规则数:      ${KUBE_SVC_COUNT}"
fi

echo ""

# ======================== 3. kube-proxy 状态 ========================
print_info ">>> [3/5] 检查 kube-proxy 状态 ..."

if pgrep -x kube-proxy &>/dev/null; then
    KUBE_PROXY_PID=$(pgrep -x kube-proxy)
    print_ok "kube-proxy 正在运行 (PID: ${KUBE_PROXY_PID})"

    # kube-proxy CPU 使用率
    KUBE_PROXY_CPU=$(ps -p "$KUBE_PROXY_PID" -o %cpu= 2>/dev/null | tr -d ' ')
    echo "    CPU 使用率:          ${KUBE_PROXY_CPU}%"

    if [ -n "$KUBE_PROXY_CPU" ]; then
        KUBE_PROXY_CPU_INT=$(echo "$KUBE_PROXY_CPU" | cut -d. -f1)
        if [ "$KUBE_PROXY_CPU_INT" -gt 50 ]; then
            print_fail "kube-proxy CPU > 50%，规则数爆炸导致开销过大"
        elif [ "$KUBE_PROXY_CPU_INT" -gt 20 ]; then
            print_warn "kube-proxy CPU > 20%，需关注"
        fi
    fi

    # 检查是否在频繁重启
    KUBE_PROXY_RESTART=$(systemctl status kube-proxy 2>/dev/null | grep -c 'Main PID changed')
    if [ "$KUBE_PROXY_RESTART" -gt 3 ]; then
        print_fail "kube-proxy 频繁重启 (${KUBE_PROXY_RESTART} 次)"
    fi
else
    print_warn "kube-proxy 未运行（可能使用其他代理模式）"
fi

echo ""

# ======================== 4. IPVS 备用检测 ========================
print_info ">>> [4/5] 检查 IPVS 状态 ..."

if command -v ipvsadm &>/dev/null; then
    IPVS_COUNT=$(sudo ipvsadm -Ln 2>/dev/null | grep -cE '^(TCP|UDP)')
    echo "    IPVS 虚拟服务数:     ${IPVS_COUNT}"
    if [ "$IPVS_COUNT" -gt 0 ]; then
        print_ok "IPVS 模式已启用，不受 iptables 规则数限制"
    fi
elif lsmod 2>/dev/null | grep -q ip_vs; then
    print_ok "IPVS 内核模块已加载"
    if ! command -v ipvsadm &>/dev/null; then
        print_info "建议安装 ipvsadm: apt install ipvsadm"
    fi
else
    print_info "IPVS 未启用"
fi

echo ""

# ======================== 5. 性能影响总结 ========================
print_info ">>> [5/5] 性能影响评估 ..."

# 检测 kube-proxy 是否导致延迟
KUBELET_OK=true
if command -v kubectl &>/dev/null; then
    # 检查是否有 Service 相关的错误事件
    if dmesg 2>/dev/null | tail -100 | grep -qi 'nf_conntrack.*table full'; then
        print_fail "检测到 conntrack 表满事件！iptables + conntrack 双重压力"
        EXIT_CODE=2
    fi
fi

# K8s 版本信息
if [ -f /etc/kubernetes/kubelet.conf ] && command -v kubectl &>/dev/null; then
    K8S_VER=$(sudo kubectl --kubeconfig=/etc/kubernetes/kubelet.conf version --short 2>/dev/null | grep Server | awk '{print $3}')
    if [ -n "$K8S_VER" ]; then
        echo "    K8s 版本:            ${K8S_VER}"

        # K8s 1.19+ 支持 nftables, 1.23+ 默认
        K8S_MAJOR=$(echo "$K8S_VER" | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2)
        if [ -n "$K8S_MAJOR" ] && [ "$K8S_MAJOR" -lt 19 ]; then
            print_warn "K8s < 1.19，IPVS 模式可能不够稳定"
        fi
    fi
fi

# 给出迁移建议
if [ "$TOTAL_RULES" -gt 5000 ] && [ "$FIREWALL_TYPE" = "iptables" ]; then
    echo ""
    echo "    ╔═══════════════════════════════════════════════╗"
    echo "    ║  强烈建议迁移到 IPVS 模式:                     ║"
    echo "    ║  kubectl edit cm kube-proxy -n kube-system   ║"
    echo "    ║  修改: mode: \"ipvs\"                          ║"
    echo "    ║  然后: kubectl delete pod -n kube-system    ║"
    echo "    ║        -l k8s-app=kube-proxy                ║"
    echo "    ╚═══════════════════════════════════════════════╝"
fi

echo ""
echo "============================================================"
if [ "$EXIT_CODE" -eq 2 ]; then
    print_fail "iptables 诊断完成: iptables 规则过多，严重影响性能"
elif [ "$EXIT_CODE" -eq 1 ]; then
    print_warn "iptables 诊断完成: 规则数偏高，建议关注"
else
    print_ok "iptables 诊断完成: 规则数正常"
fi
echo "============================================================"

exit $EXIT_CODE
