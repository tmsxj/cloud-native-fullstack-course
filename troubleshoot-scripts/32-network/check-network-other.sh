#!/bin/bash
# ============================================================================
# 模块32-网络协议诊断 (合并版)
# 脚本名称: check-network-other.sh
# 功能: DNS解析 + TLS证书 + 网络延迟
# 用法: ./check-network-other.sh [domain]
# 合并自: check-dns.sh + check-tls.sh + check-network-latency.sh
# ============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

DOMAIN=${1:-"www.baidu.com"}
print_info "目标域名: ${DOMAIN}"

DNS_SERVERS=("114.114.114.114:114DNS" "223.5.5.5:阿里DNS" "8.8.8.8:Google DNS" "1.1.1.1:Cloudflare")

echo "============================================================"
echo "    网络诊断 — DNS | TLS | 延迟"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

ISSUE_COUNT=0

# ======================== DNS ========================
print_info ">>> [DNS/1] 解析测试 (dig) ..."
if command -v dig &>/dev/null; then
    DIG_R=$(dig +stats "$DOMAIN" 2>&1)
    QUERY_TIME=$(echo "$DIG_R" | grep "Query time" | awk '{print $4}'); QUERY_TIME=${QUERY_TIME:-0}
    ANSWER_IP=$(echo "$DIG_R" | grep -A1 "ANSWER SECTION" | tail -1 | awk '{print $NF}')
    echo "    域名: ${DOMAIN}  耗时: ${QUERY_TIME}ms  解析: ${ANSWER_IP}"

    [ "$QUERY_TIME" -gt 500 ] && { print_fail "DNS解析>500ms (${QUERY_TIME}ms)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
    { [ "$QUERY_TIME" -gt 100 ] && print_warn "DNS解析偏慢 (${QUERY_TIME}ms)"; } || print_ok "DNS解析正常"
else
    print_warn "dig不可用: yum install bind-utils"
fi
echo ""

# DNS对比
print_info ">>> [DNS/2] 多DNS对比 ..."
printf "    %-20s %-12s %s\n" "DNS服务器" "耗时" "结果"
for de in "${DNS_SERVERS[@]}"; do
    IP=$(echo "$de" | cut -d: -f1); NAME=$(echo "$de" | cut -d: -f2)
    DR=$(dig @"$IP" +stats +time=2 +tries=1 "$DOMAIN" 2>&1)
    DT=$(echo "$DR" | grep "Query time" | awk '{print $4}'); DT=${DT:-"timeout"}
    DIP=$(echo "$DR" | grep -A1 "ANSWER SECTION" | tail -1 | awk '{print $NF}')
    printf "    %-20s %-12s %s\n" "$NAME" "${DT}ms" "${DIP:-N/A}"
done
echo ""

# resolv.conf
print_info ">>> [DNS/3] /etc/resolv.conf ..."
if [ -f /etc/resolv.conf ]; then
    NS_COUNT=$(grep -c "^nameserver" /etc/resolv.conf)
    [ "$NS_COUNT" -eq 0 ] && print_fail "未配置DNS" || [ "$NS_COUNT" -eq 1 ] && print_warn "仅1个DNS" || print_ok "${NS_COUNT}个DNS"
    grep "^nameserver\|^search\|^options" /etc/resolv.conf | while read l; do echo "    $l"; done
fi
echo ""


# ======================== TLS ========================
print_info ">>> [TLS/1] 证书检查 ..."
# 从域名提取主机名并检查443端口
TLS_HOST=$(echo "$DOMAIN" | sed 's|^https\?://||' | cut -d/ -f1)
echo "    检查: ${TLS_HOST}:443"

if command -v openssl &>/dev/null; then
    CERT=$(echo | openssl s_client -servername "$TLS_HOST" -connect "${TLS_HOST}:443" 2>/dev/null 2>&1)
    if echo "$CERT" | grep -q "BEGIN CERTIFICATE"; then
        # 过期时间
        EXPIRY=$(echo "$CERT" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        ISSUER=$(echo "$CERT" | openssl x509 -noout -issuer 2>/dev/null | sed 's/.*CN=//' | cut -d/ -f1)
        SAN=$(echo "$CERT" | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | head -5 | sed 's/^[[:space:]]*//')

        echo "    颁发者: ${ISSUER}"
        echo "    到期日: ${EXPIRY}"
        echo "    SAN: $(echo $SAN | tr '\n' ' ')"

        # 剩余天数
        EXPIRY_TS=$(date -d "$EXPIRY" +%s 2>/dev/null)
        NOW_TS=$(date +%s)
        if [ -n "$EXPIRY_TS" ] && [ "$EXPIRY_TS" -gt "$NOW_TS" ]; then
            DAYS_LEFT=$(( (EXPIRY_TS - NOW_TS) / 86400 ))
            [ "$DAYS_LEFT" -lt 30 ] && { print_fail "证书即将过期! 剩余${DAYS_LEFT}天"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
            { [ "$DAYS_LEFT" -lt 90 ] && print_warn "证书剩余${DAYS_LEFT}天"; } || print_ok "证书有效，剩余${DAYS_LEFT}天"
        fi

        # TLS版本
        TLS_VER=$(echo "$CERT" | openssl s_client -connect "${TLS_HOST}:443" -tls1_2 2>/dev/null | grep -o "TLSv1\.[0-9]")
        [ -n "$TLS_VER" ] && print_ok "TLS版本: ${TLS_VER}" || print_info "TLS版本未知"
    else
        print_warn "无法获取TLS证书"
    fi
else
    print_warn "openssl不可用"
fi
echo ""


# ======================== 网络延迟 ========================
print_info ">>> [LAT] 网络延迟 ..."

# 到网关
GW=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -n "$GW" ]; then
    echo "    默认网关: ${GW}"
    PING_R=$(ping -c 3 -W 2 "$GW" 2>&1)
    RTT=$(echo "$PING_R" | grep -oP 'avg=\K[0-9.]+')
    [ -n "$RTT" ] && echo "    网关延迟(avg): ${RTT}ms" && \
        [ "$(echo "$RTT > 10" | bc 2>/dev/null)" = "1" ] && print_warn "网关延迟偏高 (${RTT}ms)" || print_ok "网关延迟正常 (${RTT}ms)"
fi

# 到目标
echo "    到目标: ${DOMAIN}"
PING_R2=$(ping -c 3 -W 3 "$TLS_HOST" 2>&1)
RTT2=$(echo "$PING_R2" | grep -oP 'avg=\K[0-9.]+')
[ -n "$RTT2" ] && echo "    目标延迟(avg): ${RTT2}ms" && \
    [ "$(echo "$RTT2 > 200" | bc 2>/dev/null)" = "1" ] && { print_fail "网络延迟过高 (${RTT2}ms)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
    { [ "$(echo "$RTT2 > 50" | bc 2>/dev/null)" = "1" ] && print_warn "延迟偏高 (${RTT2}ms)"; } || print_ok "延迟正常 (${RTT2}ms)"

# traceroute
if command -v traceroute &>/dev/null; then
    echo "    traceroute(前10跳):"
    traceroute -m 10 -w 1 "$TLS_HOST" 2>/dev/null | while read l; do echo "    $l"; done
fi
# ======================== 网卡错误/丢包 ========================
print_info ">>> [NET/4] 网卡错误与丢包 ..."
NIC_ISSUE=0
for iface in $(ip -o link show 2>/dev/null | grep -v "lo:" | awk -F': ' '{print $2}' | grep -v '^veth\|^cali\|^docker\|^cni\|^flannel\|^tun\|^kube-ipvs\|^nodelocal'); do
    STATS=$(ip -s link show "$iface" 2>/dev/null)
    RX_ERR=$(echo "$STATS" | grep -A1 "RX:" | tail -1 | awk '{print $3}')
    TX_ERR=$(echo "$STATS" | grep -A1 "TX:" | tail -1 | awk '{print $3}')
    RX_DROP=$(echo "$STATS" | grep -A1 "RX:" | tail -1 | awk '{print $4}')
    TX_DROP=$(echo "$STATS" | grep -A1 "TX:" | tail -1 | awk '{print $4}')
    TOTAL_ERR=$((RX_ERR + TX_ERR))
    TOTAL_DROP=$((RX_DROP + TX_DROP))
    if [ "$TOTAL_ERR" -gt 0 ] || [ "$TOTAL_DROP" -gt 100 ]; then
        print_warn "$iface: RXerr=$RX_ERR TXerr=$TX_ERR RXdrop=$RX_DROP TXdrop=$TX_DROP"
        NIC_ISSUE=$((NIC_ISSUE+1)); ISSUE_COUNT=$((ISSUE_COUNT+1))
    else
        echo "    ${GREEN}[+]${NC} $iface: 无异常"
    fi
done
[ "$NIC_ISSUE" -eq 0 ] && print_ok "所有网卡无错误/丢包"
echo ""

echo "============================================================"
echo "                     网络诊断结论"
echo "============================================================"
[ "$ISSUE_COUNT" -eq 0 ] && echo -e "  ${GREEN}[正常]${NC} DNS/TLS/延迟状态健康"
echo "============================================================"
