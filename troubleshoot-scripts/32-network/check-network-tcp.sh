#!/bin/bash
# ============================================================================
# 模块32-网络协议诊断 (合并版)
# 脚本名称: check-network-tcp.sh
# 功能: TCP连接状态 + TIME_WAIT深度分析
# 用法: ./check-network-tcp.sh [port]
# 合并自: check-tcp-conn.sh + check-time-wait.sh
# ============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

TARGET_PORT=""
[ -n "$1" ] && { TARGET_PORT=$1; print_info "过滤端口: ${TARGET_PORT}"; }

echo "============================================================"
echo "    TCP连接深度诊断 — 状态分布 | TIME_WAIT | 端口资源"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

ISSUE_COUNT=0

# ======================== TCP状态总览 ========================
print_info ">>> [1/5] TCP状态总览 ..."
printf "    %-15s %-10s %s\n" "状态" "数量" "说明"

declare -A STATE_DESC=(
    ["ESTAB"]="已建立" ["TIME-WAIT"]="等待关闭" ["CLOSE-WAIT"]="等待关闭"
    ["LISTEN"]="监听中" ["SYN-SENT"]="同步已发送" ["SYN-RECV"]="同步接收"
    ["FIN-WAIT-1"]="终止等待1" ["FIN-WAIT-2"]="终止等待2" ["LAST-ACK"]="最后确认" ["CLOSING"]="关闭中"
)

TOTAL_CONN=0
for state in ESTAB TIME-WAIT CLOSE-WAIT LISTEN SYN-SENT SYN-RECV FIN-WAIT-1 FIN-WAIT-2 LAST-ACK CLOSING; do
    [ -n "$TARGET_PORT" ] && COUNT=$(ss -tan "sport = :${TARGET_PORT}" "state ${state}" 2>/dev/null | grep -v "^State" | wc -l) || \
        COUNT=$(ss -tan "state ${state}" 2>/dev/null | grep -v "^State" | wc -l)
    [ "$COUNT" -gt 0 ] && printf "    %-15s %-10s %s\n" "$state" "$COUNT" "${STATE_DESC[$state]}"
    TOTAL_CONN=$((TOTAL_CONN + COUNT))
done
printf "    %-15s %-10s %s\n" "总计" "$TOTAL_CONN" ""
echo ""


# ======================== TIME_WAIT 深度分析 ========================
print_info ">>> [2/5] TIME_WAIT详细分析 ..."
[ -n "$TARGET_PORT" ] && TW=$(ss -tan "sport = :${TARGET_PORT}" state time-wait 2>/dev/null | grep -v "^State" | wc -l) || \
    TW=$(ss -tan state time-wait 2>/dev/null | grep -v "^State" | wc -l)
echo "    TIME_WAIT总数: ${TW}"

[ "$TW" -gt 5000 ] && { print_fail "TIME_WAIT过多 (${TW})，面临端口耗尽"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
{ [ "$TW" -gt 1000 ] && { print_warn "TIME_WAIT偏多 (${TW})"; }; } || \
[ "$TW" -gt 0 ] && print_ok "TIME_WAIT正常 (${TW})"

# TW按目标IP分布
if [ "$TW" -gt 0 ]; then
    echo "    TIME_WAIT TOP10 目标IP:"
    ss -tan state time-wait 2>/dev/null | grep -v "^State" | awk '{print $5}' | rev | cut -d: -f2- | rev | sort | uniq -c | sort -rn | head -10 | \
        while read cnt ip; do printf "    %-20s %s个\n" "$ip" "$cnt"; done
fi
echo ""

# TIME_WAIT内核参数
print_info ">>> [3/5] TCP TIME_WAIT内核参数 ..."
TW_REUSE=$(cat /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null)
MAX_TW=$(cat /proc/sys/net/ipv4/tcp_max_tw_buckets 2>/dev/null)
FIN_TIMEOUT=$(cat /proc/sys/net/ipv4/tcp_fin_timeout 2>/dev/null)

echo "    tcp_tw_reuse = ${TW_REUSE}  (1=允许复用)"
echo "    tcp_max_tw_buckets = ${MAX_TW}"
echo "    tcp_fin_timeout = ${FIN_TIMEOUT}秒"

[ "$TW_REUSE" -eq 1 ] && print_ok "tcp_tw_reuse已启用" || print_warn "tcp_tw_reuse未启用，建议设为1"
[ "$FIN_TIMEOUT" -gt 30 ] && print_warn "tcp_fin_timeout偏长 (${FIN_TIMEOUT}s)" || print_ok "tcp_fin_timeout合理"

# tw桶使用率
TW_PCT=$((TW * 100 / MAX_TW))
[ "$TW_PCT" -gt 80 ] && print_warn "TW桶使用率${TW_PCT}%" || print_ok "TW桶使用率${TW_PCT}%"

# tcp_tw_recycle (4.12+已移除)
TW_RECYCLE=$(cat /proc/sys/net/ipv4/tcp_tw_recycle 2>/dev/null)
[ -n "$TW_RECYCLE" ] && { echo "    tcp_tw_recycle = ${TW_RECYCLE}"; [ "$TW_RECYCLE" -eq 1 ] && print_warn "NAT环境不建议启用tcp_tw_recycle"; } || echo "    tcp_tw_recycle = (已移除)"
echo ""


# ======================== CLOSE_WAIT / ESTAB ========================
print_info ">>> [4/5] CLOSE_WAIT与活跃连接 ..."
[ -n "$TARGET_PORT" ] && CW=$(ss -tan "sport = :${TARGET_PORT}" state close-wait 2>/dev/null | grep -v "^State" | wc -l) || \
    CW=$(ss -tan state close-wait 2>/dev/null | grep -v "^State" | wc -l)
echo "    CLOSE_WAIT: ${CW}"
[ "$CW" -gt 100 ] && { print_fail "CLOSE_WAIT严重 (${CW})，应用连接泄漏!"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
{ [ "$CW" -gt 50 ] && print_warn "CLOSE_WAIT偏多 (${CW})"; } || print_ok "CLOSE_WAIT正常"

[ -n "$TARGET_PORT" ] && ESTAB=$(ss -tan "sport = :${TARGET_PORT}" state established 2>/dev/null | grep -v "^State" | wc -l) || \
    ESTAB=$(ss -tan state established 2>/dev/null | grep -v "^State" | wc -l)
echo "    ESTABLISHED: ${ESTAB}"
[ "$ESTAB" -gt 0 ] && print_ok "活跃连接: ${ESTAB}"

# CLOSE_WAIT详情
[ "$CW" -gt 0 ] && { echo "    CLOSE_WAIT详情(最多5条):"; ss -tan state close-wait 2>/dev/null | grep -v "^State" | head -5 | while read l; do echo "    $l"; done; }
echo ""


# ======================== 端口范围 ========================
print_info ">>> [5/5] 端口范围与conntrack ..."
PORT_RANGE=$(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null)
PORT_MIN=$(echo "$PORT_RANGE" | awk '{print $1}'); PORT_MAX=$(echo "$PORT_RANGE" | awk '{print $2}')
PORT_TOTAL=$((PORT_MAX - PORT_MIN))
USED=$(ss -tan 2>/dev/null | grep -v "^State" | wc -l)
PORT_PCT=$((USED * 100 / PORT_TOTAL))
echo "    端口范围: ${PORT_MIN}-${PORT_MAX} (共${PORT_TOTAL}个)  |  已用: ${USED} (${PORT_PCT}%)"
[ "$PORT_PCT" -gt 80 ] && { print_fail "端口使用率过高 (${PORT_PCT}%)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
{ [ "$PORT_PCT" -gt 50 ] && print_warn "端口使用率偏高 (${PORT_PCT}%)"; } || print_ok "端口使用率正常"

# conntrack
[ -f /proc/net/nf_conntrack ] && {
    CT_COUNT=$(wc -l < /proc/net/nf_conntrack 2>/dev/null)
    CT_MAX=$(cat /proc/sys/net/nf_conntrack_max 2>/dev/null)
    [ "$CT_MAX" -gt 0 ] && CT_PCT=$((CT_COUNT * 100 / CT_MAX)) || CT_PCT=0
    echo "    conntrack: ${CT_COUNT}/${CT_MAX} (${CT_PCT}%)"
    [ "$CT_PCT" -gt 80 ] && print_warn "conntrack使用率${CT_PCT}%"
} || print_info "conntrack未加载"
echo ""


# 优化建议汇总
echo "============================================================"
echo "                    TCP优化建议"
echo "============================================================"
[ "$TW" -gt 1000 ] && {
    echo "  推荐:"
    echo "  1. sysctl -w net.ipv4.tcp_tw_reuse=1"
    echo "  2. sysctl -w net.ipv4.tcp_fin_timeout=30"
    echo "  3. 应用层使用长连接/连接池"
}
[ "$CW" -gt 50 ] && echo "  严重: CLOSE_WAIT过多，检查应用连接关闭逻辑!"
[ "$ISSUE_COUNT" -eq 0 ] && echo -e "  ${GREEN}[正常]${NC} TCP连接状态健康"
echo "============================================================"
