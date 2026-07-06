#!/bin/bash
# =============================================
# Traffic Generator for Mall Demo
# 模拟用户行为，生成API流量用于可观测性演示
# =============================================

# 配置
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
DURATION="${DURATION:-60}"          # 持续时间(秒)
QPS="${QPS:-5}"                     # 目标QPS
FAIL_RATE="${FAIL_RATE:-10}"        # 支付失败概率(%)
USER_COUNT=10
PRODUCT_IDS=(1001 1002 1003 1004 1005)

# 统计
TOTAL_REQUESTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0
START_TIME=$(date +%s)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "$(date '+%H:%M:%S') ${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "$(date '+%H:%M:%S') ${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "$(date '+%H:%M:%S') ${RED}[ERROR]${NC} $1"; }

print_stats() {
    local elapsed=$(( $(date +%s) - START_TIME ))
    if [[ $elapsed -gt 0 ]]; then
        local actual_qps=$(( TOTAL_REQUESTS / elapsed ))
        local success_rate=0
        if [[ $TOTAL_REQUESTS -gt 0 ]]; then
            success_rate=$(( (SUCCESS_COUNT * 100) / TOTAL_REQUESTS ))
        fi
        echo -e "\r  Requests: $TOTAL_REQUESTS | Success: $SUCCESS_COUNT | Failed: $FAIL_COUNT | QPS: $actual_qps | Success Rate: ${success_rate}%   "
    fi
}

# 1. 用户注册
register_user() {
    local user_id=$1
    local username="user_$(date +%s%N | tail -c 6)_$user_id"
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$GATEWAY_URL/api/v1/users/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$username\",\"email\":\"${username}@mall.com\",\"phone\":\"1380000${user_id}\"}" 2>/dev/null)

    local http_code=$(echo "$response" | tail -1)
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))

    if [[ "$http_code" =~ ^2 ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo "$username"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo ""
    fi
}

# 2. 查询用户
get_user() {
    local user_id=$1
    curl -s -o /dev/null -w "%{http_code}" -X GET "$GATEWAY_URL/api/v1/users/$user_id" 2>/dev/null
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
}

# 3. 创建订单
create_order() {
    local user_id=$1
    local product_id=$2
    local quantity=$((RANDOM % 5 + 1))

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$GATEWAY_URL/api/v1/orders/" \
        -H "Content-Type: application/json" \
        -d "{\"userId\":$user_id,\"productId\":$product_id,\"quantity\":$quantity}" 2>/dev/null)

    local http_code=$(echo "$response" | tail -1)
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))

    if [[ "$http_code" =~ ^2 ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        # 提取order id
        local body=$(echo "$response" | head -n -1)
        echo "$body" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo ""
    fi
}

# 4. 支付订单
pay_order() {
    local order_id=$1
    local force_fail=0

    # 随机触发支付失败
    if [[ $((RANDOM % 100)) -lt $FAIL_RATE ]]; then
        force_fail=1
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$GATEWAY_URL/api/v1/orders/$order_id/pay" \
        -H "Content-Type: application/json" 2>/dev/null)

    local http_code=$(echo "$response" | tail -1)
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))

    if [[ "$http_code" =~ ^2 ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# 5. 查询订单
get_order() {
    local order_id=$1
    curl -s -o /dev/null -w "%{http_code}" -X GET "$GATEWAY_URL/api/v1/orders/$order_id" 2>/dev/null
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
}

# 6. 查询库存
get_inventory() {
    local product_id=$1
    curl -s -o /dev/null -w "%{http_code}" -X GET "$GATEWAY_URL/api/v1/inventory/product/$product_id" 2>/dev/null
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
}

# 主流量循环
main() {
    echo "============================================"
    echo "  Mall Demo Traffic Generator"
    echo "============================================"
    echo "  Gateway:    $GATEWAY_URL"
    echo "  Duration:   ${DURATION}s"
    echo "  Target QPS: $QPS"
    echo "  Fail Rate:  ${FAIL_RATE}%"
    echo "============================================"
    echo ""

    # 检查网关连通性
    log_info "Checking gateway connectivity..."
    local health
    health=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/health" 2>/dev/null)
    if [[ "$health" != "200" ]]; then
        log_error "Gateway not reachable at $GATEWAY_URL (HTTP $health)"
        log_error "Please ensure the gateway is running and accessible."
        log_error "Tips:"
        echo "  - For local: kubectl port-forward svc/api-gateway -n <namespace> 8080:8080"
        echo "  - For ingress: use the Ingress IP/hostname"
        exit 1
    fi
    log_info "Gateway is healthy!"

    # 预注册一些用户
    log_info "Pre-registering $USER_COUNT users..."
    for i in $(seq 1 $USER_COUNT); do
        register_user $i > /dev/null
        sleep 0.1
    done
    log_info "Users registered."

    echo ""
    log_info "Starting traffic generation..."

    END_TIME=$(( $(date +%s) + DURATION ))
    INTERVAL=$(echo "scale=3; 1/$QPS" | bc)

    while [[ $(date +%s) -lt $END_TIME ]]; do
        # 随机选择操作
        local op=$((RANDOM % 100))

        if [[ $op -lt 30 ]]; then
            # 30% - 创建订单并支付
            local uid=$((RANDOM % USER_COUNT + 1))
            local pid=${PRODUCT_IDS[$((RANDOM % ${#PRODUCT_IDS[@]}))]}
            local order_id
            order_id=$(create_order $uid $pid)
            if [[ -n "$order_id" ]]; then
                sleep $(echo "$INTERVAL * 0.5" | bc)
                pay_order "$order_id"
            fi
        elif [[ $op -lt 50 ]]; then
            # 20% - 查询订单
            local oid=$((RANDOM % 100 + 1))
            local code
            code=$(get_order $oid)
            if [[ "$code" =~ ^2 ]]; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        elif [[ $op -lt 65 ]]; then
            # 15% - 查询用户
            local uid=$((RANDOM % USER_COUNT + 1))
            local code
            code=$(get_user $uid)
            if [[ "$code" =~ ^2 ]]; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        elif [[ $op -lt 80 ]]; then
            # 15% - 查询库存
            local pid=${PRODUCT_IDS[$((RANDOM % ${#PRODUCT_IDS[@]}))]}
            local code
            code=$(get_inventory $pid)
            if [[ "$code" =~ ^2 ]]; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        elif [[ $op -lt 90 ]]; then
            # 10% - 注册新用户
            register_user $((RANDOM % 1000 + 100)) > /dev/null
        else
            # 10% - 创建订单(不支付)
            local uid=$((RANDOM % USER_COUNT + 1))
            local pid=${PRODUCT_IDS[$((RANDOM % ${#PRODUCT_IDS[@]}))]}
            create_order $uid $pid > /dev/null
        fi

        # 控制QPS
        sleep $INTERVAL

        # 打印统计
        print_stats
    done

    echo ""
    echo ""
    echo "============================================"
    echo "  Traffic Generation Complete!"
    echo "============================================"
    print_stats
    echo ""
    local elapsed=$(( $(date +%s) - START_TIME ))
    echo "  Duration:      ${elapsed}s"
    echo "  Total Requests: $TOTAL_REQUESTS"
    echo "  Success:       $SUCCESS_COUNT"
    echo "  Failed:        $FAIL_COUNT"
    if [[ $TOTAL_REQUESTS -gt 0 ]]; then
        echo "  Success Rate:  $(( (SUCCESS_COUNT * 100) / TOTAL_REQUESTS ))%"
        echo "  Avg QPS:       $(( TOTAL_REQUESTS / elapsed ))"
    fi
    echo "============================================"
}

main "$@"
