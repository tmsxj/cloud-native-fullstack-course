#!/bin/bash
# ============================================================================
# 模块29-K8S故障排查 (节点级)
# 脚本名称: check-pid.sh
# 功能: PID 资源耗尽诊断
# 用法: ./check-pid.sh
# 说明: 高密度Pod部署时 PID 可能耗尽，表现为 fork() 失败、"Resource temporarily unavailable"
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
echo "          PID 资源耗尽诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. PID 限制与使用率 ========================
print_info ">>> [1/5] 检查 PID 限制与使用率 ..."

PID_MAX=$(cat /proc/sys/kernel/pid_max 2>/dev/null)
# 统计当前分配的 PID 数（用 /proc 下的数字目录近似）
PID_CURRENT=$(ls -1d /proc/[0-9]* 2>/dev/null | wc -l)

echo "    pid_max (上限):       ${PID_MAX:-N/A}"
echo "    当前进程/线程数:      ${PID_CURRENT}"

if [ -n "$PID_MAX" ] && [ "$PID_MAX" -gt 0 ]; then
    PID_PCT=$(( PID_CURRENT * 100 / PID_MAX ))
    echo "    PID 使用率:           ${PID_PCT}%"

    if [ "$PID_PCT" -ge 85 ]; then
        print_fail "PID 使用率 > 85%，即将耗尽！fork() 将失败"
        EXIT_CODE=2
    elif [ "$PID_PCT" -ge 60 ]; then
        print_warn "PID 使用率 > 60%，存在耗尽风险"
        [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
    elif [ "$PID_PCT" -ge 30 ]; then
        print_ok "PID 使用率正常"
    else
        print_ok "PID 使用率健康"
    fi
fi

echo ""

# ======================== 2. 按进程统计线程数 Top 10 ========================
print_info ">>> [2/5] 统计进程线程数 Top 10 ..."

echo "    PID        线程数    进程名"
echo "    ─────────────────────────────────────"

# 用 ps 获取线程数
ps -eo pid,nlwp,comm --no-headers 2>/dev/null | sort -k2 -rn | head -10 | while read -r pid threads comm; do
    printf "    %-10s %-8s   %s\n" "$pid" "$threads" "$comm"
done

echo ""

# ======================== 3. 线程数汇总 ========================
print_info ">>> [3/5] 线程总数统计 ..."

TOTAL_THREADS=$(ps -eo nlwp --no-headers 2>/dev/null | awk '{sum+=$1} END {print sum}')
THREADS_MAX=$(cat /proc/sys/kernel/threads-max 2>/dev/null)

echo "    当前线程总数:         ${TOTAL_THREADS:-N/A}"
echo "    threads-max (上限):   ${THREADS_MAX:-N/A}"

if [ -n "$THREADS_MAX" ] && [ -n "$TOTAL_THREADS" ] && [ "$THREADS_MAX" -gt 0 ]; then
    THREAD_PCT=$(( TOTAL_THREADS * 100 / THREADS_MAX ))
    echo "    线程使用率:           ${THREAD_PCT}%"

    if [ "$THREAD_PCT" -ge 80 ]; then
        print_warn "线程使用率 > 80%"
        [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
    fi
fi

echo ""

# ======================== 4. K8s Pod 对 PID 的消耗 ========================
print_info ">>> [4/5] K8s Pod PID 消耗分析 ..."

ON_K8S_NODE=false
if pgrep -x kubelet &>/dev/null; then
    ON_K8S_NODE=true
fi

if $ON_K8S_NODE && command -v crictl &>/dev/null; then
    # 通过 crictl 获取容器数和 Pod 数
    CONTAINER_COUNT=$(sudo crictl ps -q 2>/dev/null | wc -l)
    POD_COUNT=$(sudo crictl pods -q 2>/dev/null | wc -l)

    echo "    运行中容器数:         ${CONTAINER_COUNT}"
    echo "    运行中 Pod 数:        ${POD_COUNT}"

    # 读所有容器内的进程数
    TOTAL_CONTAINER_PROC=0
    while read -r container_id; do
        [ -z "$container_id" ] && continue
        CONTAINER_PID=$(sudo crictl inspect "$container_id" 2>/dev/null | grep -oP '"pid":\s*\K\d+' | head -1)
        if [ -n "$CONTAINER_PID" ] && [ "$CONTAINER_PID" -gt 0 ]; then
            CHILD_COUNT=$(pgrep -P "$CONTAINER_PID" 2>/dev/null | wc -l)
            TOTAL_CONTAINER_PROC=$((TOTAL_CONTAINER_PROC + CHILD_COUNT + 1))
        fi
    done < <(sudo crictl ps -q 2>/dev/null)

    echo "    容器内进程估算:       ${TOTAL_CONTAINER_PROC}"

    if [ -n "$PID_MAX" ] && [ "$PID_MAX" -gt 0 ]; then
        CONTAINER_PID_PCT=$(( TOTAL_CONTAINER_PROC * 100 / PID_MAX ))
        echo "    容器进程占 PID 比:    ${CONTAINER_PID_PCT}%"
    fi

    # Pod PID 限制检查
    if [ -f /var/lib/kubelet/config.yaml ]; then
        POD_PID_LIMIT=$(sudo grep 'podPidsLimit' /var/lib/kubelet/config.yaml 2>/dev/null | awk '{print $2}')
        if [ -n "$POD_PID_LIMIT" ] && [ "$POD_PID_LIMIT" -gt 0 ]; then
            echo ""
            echo "    Pod PID 限制 (podPidsLimit): ${POD_PID_LIMIT}"
            echo "    全节点理论最大:      $(( POD_COUNT * POD_PID_LIMIT )) (Pod数 × 每Pod限制)"
        else
            print_warn "    podPidsLimit 未设置，单个 Pod 可能耗尽所有 PID"
            echo "    建议: kubelet --pod-max-pids=4096"
        fi
    fi
elif $ON_K8S_NODE; then
    print_info "crictl 不可用，跳过 K8s 容器 PID 分析"
    if command -v docker &>/dev/null; then
        CONTAINER_COUNT=$(sudo docker ps -q 2>/dev/null | wc -l)
        echo "    运行中容器数 (docker): ${CONTAINER_COUNT}"
    fi
else
    print_info "当前节点非 K8s 节点"
fi

echo ""

# ======================== 5. PID 耗尽预警 ========================
print_info ">>> [5/5] PID 耗尽风险评估 ..."

# 检查内核日志中是否有 fork 失败记录
FORK_FAILS=$(dmesg 2>/dev/null | grep -ci 'fork.*fail\|Cannot allocate memory.*fork\|cgroup.*pids')
if [ "$FORK_FAILS" -gt 0 ]; then
    print_fail "内核日志发现 ${FORK_FAILS} 条 fork 失败记录！"
    EXIT_CODE=2
fi

# 检查 cgroup pids 控制器
if [ -d /sys/fs/cgroup/pids ]; then
    print_ok "cgroup pids 控制器已启用"
else
    print_info "cgroup v1 pids 控制器未挂载（v2 自动包含）"
fi

# 推荐值
if [ -n "$PID_MAX" ] && [ "$PID_MAX" -lt 65536 ]; then
    echo ""
    echo "    ⚠  pid_max 仅 ${PID_MAX}，建议至少 65536"
    echo "    高密度 K8s 节点建议: 262144 或更高"
    echo ""
    echo "    立即生效: sysctl -w kernel.pid_max=262144"
    echo "    永久生效: echo 'kernel.pid_max=262144' >> /etc/sysctl.d/99-k8s-pid.conf"
fi

# 综合建议
if $ON_K8S_NODE; then
    echo ""
    echo "    K8s 节点 PID 优化清单:"
    echo "    1. 设置 kernel.pid_max >= 262144"
    echo "    2. 设置 kubelet --pod-max-pids >= 4096"
    echo "    3. 排查线程泄漏的 Pod"
    echo "    4. 使用 LimitRange 限制 namespace 级 PID"
fi

echo ""
echo "============================================================"
if [ "$EXIT_CODE" -eq 2 ]; then
    print_fail "PID 诊断完成: PID 资源紧张，需要立即处理"
elif [ "$EXIT_CODE" -eq 1 ]; then
    print_warn "PID 诊断完成: PID 使用率偏高，建议关注"
else
    print_ok "PID 诊断完成: PID 资源充足"
fi
echo "============================================================"

exit $EXIT_CODE
