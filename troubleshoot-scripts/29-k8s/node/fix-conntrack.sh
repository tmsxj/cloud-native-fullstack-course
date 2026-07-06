#!/bin/bash
# ============================================================================
# 模块29-K8S故障排查 (节点修复)
# 脚本名称: fix-conntrack.sh
# 功能: 自动修复 conntrack 表满问题
# 用法: ./fix-conntrack.sh [--force]
# 说明: 增大 nf_conntrack_max、缩短超时、必要时清理表
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_info() { echo -e "[INFO] $1"; }
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

FORCE_MODE=false
[ "$1" = "--force" ] && FORCE_MODE=true

echo "============================================================"
echo "          conntrack 自动修复"
echo "          执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# 0. 检查 conntrack 模块
if ! lsmod 2>/dev/null | grep -q '^nf_conntrack\b'; then
    print_info "加载 nf_conntrack 模块..."
    sudo modprobe nf_conntrack 2>/dev/null || true
fi

# 1. 获取当前值
CONNTRACK_MAX=""
for p in /proc/sys/net/netfilter/nf_conntrack_max /proc/sys/net/nf_conntrack_max; do
    [ -r "$p" ] && { CONNTRACK_MAX=$(cat "$p"); CONNTRACK_MAX_FILE="$p"; break; }
done

CONNTRACK_COUNT=""
for p in /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/nf_conntrack_count; do
    [ -r "$p" ] && { CONNTRACK_COUNT=$(cat "$p"); break; }
done

[ -z "$CONNTRACK_COUNT" ] && command -v conntrack &>/dev/null && CONNTRACK_COUNT=$(conntrack -C 2>/dev/null)

print_info "当前状态: ${CONNTRACK_COUNT:-?}/${CONNTRACK_MAX:-?}"
echo ""

# 2. 计算推荐值（取 当前值×2 和 65536 和 262144 中的最大值）
RECOMMENDED_MAX=262144
[ -n "$CONNTRACK_COUNT" ] && [ "$CONNTRACK_COUNT" -gt 0 ] && RECOMMENDED_MAX=$(( CONNTRACK_COUNT * 2 ))
[ "$RECOMMENDED_MAX" -lt 262144 ] && RECOMMENDED_MAX=262144

if [ -n "$CONNTRACK_MAX" ] && [ "$CONNTRACK_MAX" -lt "$RECOMMENDED_MAX" ]; then
    print_info "增大 nf_conntrack_max: ${CONNTRACK_MAX} → ${RECOMMENDED_MAX}"
    for p in /proc/sys/net/netfilter/nf_conntrack_max /proc/sys/net/nf_conntrack_max; do
        [ -w "$p" ] && echo "$RECOMMENDED_MAX" | sudo tee "$p" > /dev/null 2>&1
    done
    print_ok "nf_conntrack_max 已更新"
else
    print_ok "nf_conntrack_max 已足够 (${CONNTRACK_MAX})"
fi

# 3. 增大 hashsize（需模块参数方式）
HASHSIZE=""
for p in /sys/module/nf_conntrack/parameters/hashsize /proc/sys/net/netfilter/nf_conntrack_buckets; do
    [ -r "$p" ] && { HASHSIZE=$(cat "$p" 2>/dev/null); break; }
done
if [ -n "$HASHSIZE" ] && [ "$HASHSIZE" -lt 32768 ]; then
    NEW_HASH=$((RECOMMENDED_MAX / 8))
    print_info "hashsize: ${HASHSIZE} → 建议 ${NEW_HASH} (需重新加载模块或重启生效)"
fi

echo ""

# 4. 缩短超时时间
print_info "调整 conntrack 超时参数..."
declare -A TIMEOUTS=(
    ["net.netfilter.nf_conntrack_tcp_timeout_established"]="600"
    ["net.netfilter.nf_conntrack_tcp_timeout_time_wait"]="30"
    ["net.netfilter.nf_conntrack_tcp_timeout_close_wait"]="60"
    ["net.netfilter.nf_conntrack_udp_timeout"]="30"
    ["net.netfilter.nf_conntrack_udp_timeout_stream"]="60"
)

for key in "${!TIMEOUTS[@]}"; do
    CURRENT=$(sysctl -n "$key" 2>/dev/null)
    TARGET=${TIMEOUTS[$key]}
    if [ -n "$CURRENT" ] && [ "$CURRENT" -gt "$TARGET" ]; then
        print_info "  ${key}: ${CURRENT}s → ${TARGET}s"
        sudo sysctl -w "${key}=${TARGET}" >/dev/null 2>&1
    fi
done

echo ""

# 5. 持久化 sysctl
print_info "持久化配置..."
SYSCTL_FILE="/etc/sysctl.d/99-k8s-conntrack.conf"
sudo bash -c "cat > $SYSCTL_FILE << 'EOF'
# K8s 节点 conntrack 优化
net.netfilter.nf_conntrack_max = ${RECOMMENDED_MAX}
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 60
EOF"
sudo sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1
print_ok "配置已持久化到 ${SYSCTL_FILE}"

echo ""

# 6. --force 模式: 清理 conntrack 表
if $FORCE_MODE; then
    print_info "--force: 清理 conntrack 表..."
    if command -v conntrack &>/dev/null; then
        DROPPED=$(sudo conntrack -D 2>/dev/null | wc -l)
        print_warn "已清理 ${DROPPED} 条 conntrack 条目（会影响现有连接）"
    else
        # 用 /proc 方式只能全量清
        for p in /proc/sys/net/netfilter/nf_conntrack_max /proc/sys/net/nf_conntrack_max; do
            if [ -w "$p" ]; then
                OLD=$(cat "$p")
                echo 1 | sudo tee "$p" > /dev/null 2>&1
                sleep 0.5
                echo "$OLD" | sudo tee "$p" > /dev/null 2>&1
                break
            fi
        done
        print_warn "已通过重置方式清理 conntrack 表"
    fi
elif [ -n "$CONNTRACK_PCT" ] && [ "$CONNTRACK_PCT" -ge 90 ]; then
    print_warn "使用率 > 90%，建议用 --force 清理 conntrack 表"
fi

echo ""
echo "============================================================"
print_ok "conntrack 修复完成"
echo "============================================================"
