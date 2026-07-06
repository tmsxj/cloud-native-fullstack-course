#!/bin/bash
# ============================================================================
# 模块29-K8S故障排查 (节点级)
# 脚本名称: check-conntrack.sh
# 功能: conntrack 连接跟踪表诊断
# 用法: ./check-conntrack.sh
# 说明: K8s节点Service多时conntrack表容易满，表现为随机丢包、新建连接失败
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
# 0=正常  1=警告  2=严重
EXIT_CODE=0

echo "============================================================"
echo "          conntrack 连接跟踪表诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 0. conntrack 模块检测 ========================
print_info ">>> [0/5] 检查 conntrack 模块是否加载 ..."

CONNTRACK_LOADED=false
if lsmod 2>/dev/null | grep -qE '^nf_conntrack\b'; then
    CONNTRACK_LOADED=true
    print_ok "nf_conntrack 模块已加载"
elif modprobe -n nf_conntrack 2>/dev/null; then
    print_warn "nf_conntrack 模块未加载，但可用。K8s节点建议加载。"
    echo "    modprobe nf_conntrack"
else
    print_warn "nf_conntrack 模块不可用，跳过 conntrack 检查"
    echo "    原因: 内核可能未编译 conntrack 支持"
    exit 0
fi

echo ""

# ======================== 1. conntrack 表容量 ========================
print_info ">>> [1/5] 检查 conntrack 表容量 ..."

# 探测 conntrack_max 路径（不同发行版路径不同）
CONNTRACK_MAX=""
for p in /proc/sys/net/netfilter/nf_conntrack_max /proc/sys/net/nf_conntrack_max; do
    if [ -r "$p" ]; then
        CONNTRACK_MAX=$(cat "$p" 2>/dev/null)
        CONNTRACK_MAX_FILE="$p"
        break
    fi
done

# 探测 conntrack_count 路径
CONNTRACK_COUNT=""
for p in /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/nf_conntrack_count; do
    if [ -r "$p" ]; then
        CONNTRACK_COUNT=$(cat "$p" 2>/dev/null)
        break
    fi
done

# 兜底: 用 conntrack 命令获取
if [ -z "$CONNTRACK_COUNT" ] || [ -z "$CONNTRACK_MAX" ]; then
    if command -v conntrack &>/dev/null; then
        CONNTRACK_COUNT=$(conntrack -C 2>/dev/null)
        CONNTRACK_MAX=$(conntrack -S 2>/dev/null | grep -oP 'max\s*=\s*\K\d+' | head -1)
    fi
fi

if [ -n "$CONNTRACK_MAX" ] && [ -n "$CONNTRACK_COUNT" ]; then
    CONNTRACK_PCT=$(( CONNTRACK_COUNT * 100 / CONNTRACK_MAX ))
    echo "    conntrack 上限 (max):  ${CONNTRACK_MAX}"
    echo "    当前连接数 (count):   ${CONNTRACK_COUNT}"
    echo "    使用率:               ${CONNTRACK_PCT}%"

    if [ "$CONNTRACK_PCT" -ge 90 ]; then
        print_fail "conntrack 表使用率严重超标 (${CONNTRACK_PCT}%)，新连接将被丢弃！"
        EXIT_CODE=2
    elif [ "$CONNTRACK_PCT" -ge 70 ]; then
        print_warn "conntrack 表使用率偏高 (${CONNTRACK_PCT}%)，建议扩容或清理"
        [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
    elif [ "$CONNTRACK_PCT" -ge 50 ]; then
        print_ok "conntrack 表使用率正常 (${CONNTRACK_PCT}%)"
    else
        print_ok "conntrack 表使用率健康 (${CONNTRACK_PCT}%)"
    fi
else
    print_warn "无法获取 conntrack 统计数据，跳过容量检查"
fi

echo ""

# ======================== 2. conntrack 统计计数器 ========================
print_info ">>> [2/5] 检查 conntrack 丢包/错误统计 ..."

CONNTRACK_STAT="/proc/net/stat/nf_conntrack"
if [ -r "$CONNTRACK_STAT" ]; then
    # 解析 /proc/net/stat/nf_conntrack (第一行=表头, 第二行=数据)
    # 列: entries searched found new invalid ignore delete delete_list insert insert_failed drop early_drop error expect_new ...
    HEADER=$(head -1 "$CONNTRACK_STAT")
    DATA=$(tail -1 "$CONNTRACK_STAT")

    # 用表头确定列位置
    col_idx() {
        local name=$1
        local idx=1
        for col in $HEADER; do
            if [ "$col" = "$name" ]; then echo "$idx"; return 0; fi
            idx=$((idx + 1))
        done
        echo "0"
    }

    DROP_IDX=$(col_idx "drop")
    EARLY_DROP_IDX=$(col_idx "early_drop")
    INS_FAIL_IDX=$(col_idx "insert_failed")
    ERR_IDX=$(col_idx "error")
    FOUND_IDX=$(col_idx "found")

    get_col() {
        local idx=$1
        [ "$idx" = "0" ] && { echo "N/A"; return; }
        echo "$DATA" | awk -v i="$idx" '{print $i}'
    }

    DROP_VAL=$(get_col "$DROP_IDX")
    EARLY_DROP_VAL=$(get_col "$EARLY_DROP_IDX")
    INS_FAIL_VAL=$(get_col "$INS_FAIL_IDX")
    ERR_VAL=$(get_col "$ERR_IDX")
    FOUND_VAL=$(get_col "$FOUND_IDX")

    echo "    drop (表满丢弃):        ${DROP_VAL}"
    echo "    early_drop (早期丢弃):   ${EARLY_DROP_VAL}"
    echo "    insert_failed (插入失败): ${INS_FAIL_VAL}"
    echo "    error (错误数):          ${ERR_VAL}"

    # 累计丢弃 > 10000 告警
    TOTAL_DROP=0
    [ "$DROP_VAL" != "N/A" ] && TOTAL_DROP=$((TOTAL_DROP + DROP_VAL))
    [ "$EARLY_DROP_VAL" != "N/A" ] && TOTAL_DROP=$((TOTAL_DROP + EARLY_DROP_VAL))

    if [ "$TOTAL_DROP" -gt 10000 ]; then
        print_fail "conntrack 累计丢弃 ${TOTAL_DROP} 个连接，表容量严重不足！"
        print_info "建议: 增大 nf_conntrack_max 并缩短超时时间"
        [ $EXIT_CODE -lt 2 ] && EXIT_CODE=2
    elif [ "$TOTAL_DROP" -gt 1000 ]; then
        print_warn "conntrack 累计丢弃 ${TOTAL_DROP} 个连接，存在容量压力"
        [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
    else
        print_ok "conntrack 丢弃率正常"
    fi
else
    print_warn "/proc/net/stat/nf_conntrack 不可读，跳过计数器检查"
fi

echo ""

# ======================== 3. 连接状态分布 ========================
print_info ">>> [3/5] 检查连接状态分布 (Top 5) ..."

if command -v conntrack &>/dev/null; then
    conntrack -L -o extended 2>/dev/null | awk '{print $4}' | sort | uniq -c | sort -rn | head -5 | while read -r cnt state; do
        printf "    %-20s %s\n" "${state}" "${cnt}"
    done
    echo ""
    print_info "TIME_WAIT 过多可能导致表膨胀，建议调整:"
    echo "    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=30"
else
    print_info "conntrack 命令不可用，跳过状态分布检查"
fi

echo ""

# ======================== 4. conntrack 超时参数 ========================
print_info ">>> [4/5] 检查 conntrack 超时参数 ..."

# 获取 hashsize
HASHSIZE=""
for p in /proc/sys/net/netfilter/nf_conntrack_buckets /sys/module/nf_conntrack/parameters/hashsize; do
    if [ -r "$p" ]; then
        HASHSIZE=$(cat "$p" 2>/dev/null)
        break
    fi
done

echo "    hashsize (桶数量):  ${HASHSIZE:-N/A}"

# 检查常用超时 sysctl
show_timeout() {
    local key=$1 desc=$2
    local val=$(sysctl -n "$key" 2>/dev/null)
    if [ -n "$val" ]; then
        printf "    %-55s %s秒\n" "${desc}" "${val}"
    fi
}

show_timeout "net.netfilter.nf_conntrack_tcp_timeout_established" "TCP 已建立连接超时"
show_timeout "net.netfilter.nf_conntrack_tcp_timeout_time_wait"   "TCP TIME_WAIT 超时"
show_timeout "net.netfilter.nf_conntrack_tcp_timeout_close_wait"  "TCP CLOSE_WAIT 超时"
show_timeout "net.netfilter.nf_conntrack_udp_timeout"             "UDP 超时"
show_timeout "net.netfilter.nf_conntrack_udp_timeout_stream"      "UDP 流超时"
show_timeout "net.netfilter.nf_conntrack_generic_timeout"         "通用超时"

TC_EST=$(sysctl -n net.netfilter.nf_conntrack_tcp_timeout_established 2>/dev/null)
if [ -n "$TC_EST" ] && [ "$TC_EST" -gt 86400 ]; then
    print_warn "TCP established 超时超过24小时(${TC_EST}s)，高并发场景建议缩短"
    echo "    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=600"
fi

echo ""

# ======================== 5. K8s 场景关联分析 ========================
print_info ">>> [5/5] K8s 关联分析 ..."

# 检查是否在 K8s 节点上
ON_K8S_NODE=false
if pgrep -x kubelet &>/dev/null; then
    ON_K8S_NODE=true
fi
if command -v kubectl &>/dev/null && [ -f /etc/kubernetes/kubelet.conf ]; then
    ON_K8S_NODE=true
fi

if $ON_K8S_NODE; then
    # Service/Endpoint 数量
    SVC_COUNT=0
    if command -v kubectl &>/dev/null; then
        SVC_COUNT=$(sudo kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get svc --all-namespaces --no-headers 2>/dev/null | wc -l)
    fi

    echo "    当前节点是 K8s 节点"
    echo "    集群 Service 总数:  ${SVC_COUNT:-N/A}"

    # 估算: 每个 Service 约产生 N 条 conntrack 条目
    if [ -n "$SVC_COUNT" ] && [ "$SVC_COUNT" -gt 0 ]; then
        EST_ENTRIES=$((SVC_COUNT * 8))  # 粗略估算: 每个Service 8个后端
        if [ -n "$CONNTRACK_MAX" ] && [ "$CONNTRACK_MAX" -gt 0 ]; then
            EST_PCT=$((EST_ENTRIES * 100 / CONNTRACK_MAX))
            if [ "$EST_PCT" -gt 60 ]; then
                print_warn "估算 conntrack 条目约占表容量 ${EST_PCT}%，建议扩容"
                echo "    推荐: nf_conntrack_max >= $((SVC_COUNT * 32))"
            fi
        fi
    fi
else
    print_info "当前节点非 K8s 节点，跳过 K8s 关联分析"
fi

echo ""
echo "============================================================"
if [ "$EXIT_CODE" -eq 2 ]; then
    print_fail "conntrack 诊断完成: 存在严重问题，需要立即处理"
elif [ "$EXIT_CODE" -eq 1 ]; then
    print_warn "conntrack 诊断完成: 存在潜在风险，建议关注"
else
    print_ok "conntrack 诊断完成: 一切正常"
fi
echo "============================================================"

exit $EXIT_CODE
