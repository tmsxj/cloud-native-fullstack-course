#!/bin/bash
# ============================================================================
# 模块29-K8S故障排查 (节点级)
# 脚本名称: check-inotify.sh
# 功能: inotify 文件监控资源诊断
# 用法: ./check-inotify.sh
# 说明: containerd/kubelet 重度依赖 inotify，耗尽了容器无法启动/日志丢失
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
echo "          inotify 文件监控资源诊断报告"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 1. 系统级 inotify 限制 ========================
print_info ">>> [1/5] 检查系统 inotify 限制 ..."

MAX_USER_INSTANCES=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null)
MAX_USER_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null)
MAX_QUEUED_EVENTS=$(cat /proc/sys/fs/inotify/max_queued_events 2>/dev/null)

echo "    max_user_instances:  ${MAX_USER_INSTANCES:-N/A}  (每用户最多 inotify 实例数)"
echo "    max_user_watches:    ${MAX_USER_WATCHES:-N/A}    (每用户最多监控文件数)"
echo "    max_queued_events:   ${MAX_QUEUED_EVENTS:-N/A}   (队列最大事件数)"

# 阈值判断
if [ -n "$MAX_USER_INSTANCES" ] && [ "$MAX_USER_INSTANCES" -lt 512 ]; then
    print_warn "max_user_instances < 512，K8s 节点建议 >= 1024"
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
fi

if [ -n "$MAX_USER_WATCHES" ] && [ "$MAX_USER_WATCHES" -lt 65536 ]; then
    print_warn "max_user_watches < 65536，K8s 节点建议 >= 1048576"
    echo "    sysctl -w fs.inotify.max_user_watches=1048576"
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
fi

echo ""

# ======================== 2. 各用户 inotify 使用量 ========================
print_info ">>> [2/5] 检查各用户 inotify 实际使用量 ..."

# 从 /proc 统计各用户 inotify watches 使用量
echo "    用户        实例数    监控数      归属服务"
echo "    ─────────────────────────────────────────────"

# 收集每个 fd 的 inotify 信息
declare -A USER_INSTANCES
declare -A USER_WATCHES
declare -A USER_PROCESSES

while read -r pid; do
    [ -z "$pid" ] && continue
    FD_DIR="/proc/$pid/fd"
    [ ! -d "$FD_DIR" ] && continue

    USER=$(stat -c %U "$FD_DIR" 2>/dev/null)
    [ -z "$USER" ] && continue

    INST_COUNT=0
    WATCH_COUNT=0

    for fd in "$FD_DIR"/*; do
        LINK=$(readlink "$fd" 2>/dev/null)
        if echo "$LINK" | grep -q 'inotify'; then
            INST_COUNT=$((INST_COUNT + 1))
            # 从 fdinfo 获取 watches 数量
            FD_NUM=$(basename "$fd")
            FDINFO="/proc/$pid/fdinfo/$FD_NUM"
            if [ -r "$FDINFO" ]; then
                W=$(grep -c 'inotify' "$FDINFO" 2>/dev/null)
                WATCH_COUNT=$((WATCH_COUNT + W))
            fi
        fi
    done

    if [ "$INST_COUNT" -gt 0 ] || [ "$WATCH_COUNT" -gt 0 ]; then
        USER_INSTANCES[$USER]=$(( ${USER_INSTANCES[$USER]:-0} + INST_COUNT ))
        USER_WATCHES[$USER]=$(( ${USER_WATCHES[$USER]:-0} + WATCH_COUNT ))
        PROC_NAME=$(cat /proc/$pid/comm 2>/dev/null)
        USER_PROCESSES[$USER]="${USER_PROCESSES[$USER]:-}${PROC_NAME},"
    fi
done < <(ls /proc/ 2>/dev/null | grep -E '^[0-9]+$')

for user in "${!USER_INSTANCES[@]}"; do
    inst=${USER_INSTANCES[$user]}
    watch=${USER_WATCHES[$user]}
    procs=$(echo "${USER_PROCESSES[$user]}" | sed 's/,$//')
    printf "    %-10s %5d      %-8d   %s\n" "$user" "$inst" "$watch" "$procs"
done

echo ""

# ======================== 3. inotify 使用率检查 ========================
print_info ">>> [3/5] 检查 inotify 资源使用率 ..."

# 重点检查 root 用户（containerd/kubelet 通常用 root 运行）
ROOT_WATCHES=${USER_WATCHES["root"]:-0}
ROOT_INSTANCES=${USER_INSTANCES["root"]:-0}

if [ -n "$MAX_USER_WATCHES" ] && [ "$MAX_USER_WATCHES" -gt 0 ]; then
    WATCH_PCT=$(( ROOT_WATCHES * 100 / MAX_USER_WATCHES ))
    echo "    root watches 使用率: ${WATCH_PCT}% (${ROOT_WATCHES}/${MAX_USER_WATCHES})"

    if [ "$WATCH_PCT" -ge 90 ]; then
        print_fail "root inotify watches 使用率 > 90%，即将耗尽！"
        print_info "containerd/kubelet 将无法监控新文件，容器日志可能丢失"
        EXIT_CODE=2
    elif [ "$WATCH_PCT" -ge 70 ]; then
        print_warn "root inotify watches 使用率 > 70%，存在耗尽风险"
        [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
    elif [ "$WATCH_PCT" -ge 50 ]; then
        print_ok "root inotify watches 使用率偏高但可接受"
    else
        print_ok "root inotify watches 使用率正常"
    fi
fi

if [ -n "$MAX_USER_INSTANCES" ] && [ "$MAX_USER_INSTANCES" -gt 0 ]; then
    INST_PCT=$(( ROOT_INSTANCES * 100 / MAX_USER_INSTANCES ))
    echo "    root instances 使用率: ${INST_PCT}% (${ROOT_INSTANCES}/${MAX_USER_INSTANCES})"

    if [ "$INST_PCT" -ge 80 ]; then
        print_warn "root inotify instances 使用率 > 80%"
        [ $EXIT_CODE -lt 2 ] && EXIT_CODE=1
    fi
fi

echo ""

# ======================== 4. 关键服务 inotify 详情 ========================
print_info ">>> [4/5] 检查关键服务 inotify 占用 ..."

check_service_inotify() {
    local svc_name=$1
    local pid
    pid=$(pgrep -x "$svc_name" 2>/dev/null | head -1)
    if [ -z "$pid" ]; then
        print_info "${svc_name}: 未运行"
        return
    fi

    local inst=0 watch=0
    for fd in /proc/$pid/fd/*; do
        local lnk=$(readlink "$fd" 2>/dev/null)
        if echo "$lnk" | grep -q 'inotify'; then
            inst=$((inst + 1))
            local fdn=$(basename "$fd")
            local w=$(grep -c 'inotify' "/proc/$pid/fdinfo/$fdn" 2>/dev/null)
            watch=$((watch + w))
        fi
    done

    printf "    %-20s PID:%-7s instances:%-3s watches:%-8s\n" "$svc_name" "$pid" "$inst" "$watch"

    # 告警: containerd watches > 20000
    if [ "$svc_name" = "containerd" ] && [ "$watch" -gt 20000 ]; then
        print_warn "    → containerd watches 过多 (${watch})，日志监控可能消耗大量 inotify"
    fi
}

check_service_inotify "containerd"
check_service_inotify "dockerd"
check_service_inotify "kubelet"
check_service_inotify "cri-o"

echo ""

# ======================== 5. 修复建议 ========================
print_info ">>> [5/5] 修复建议 ..."

NEED_FIX=false
RECOMMENDED_WATCHES=1048576
RECOMMENDED_INSTANCES=1024

if [ -n "$MAX_USER_WATCHES" ] && [ "$MAX_USER_WATCHES" -lt "$RECOMMENDED_WATCHES" ]; then
    NEED_FIX=true
    echo "    ⚠  max_user_watches 建议从 ${MAX_USER_WATCHES} 调整为 ${RECOMMENDED_WATCHES}"
fi

if [ -n "$MAX_USER_INSTANCES" ] && [ "$MAX_USER_INSTANCES" -lt "$RECOMMENDED_INSTANCES" ]; then
    NEED_FIX=true
    echo "    ⚠  max_user_instances 建议从 ${MAX_USER_INSTANCES} 调整为 ${RECOMMENDED_INSTANCES}"
fi

if $NEED_FIX; then
    echo ""
    echo "    立即生效:"
    echo "    sysctl -w fs.inotify.max_user_watches=${RECOMMENDED_WATCHES}"
    echo "    sysctl -w fs.inotify.max_user_instances=${RECOMMENDED_INSTANCES}"
    echo ""
    echo "    永久生效:"
    echo "    echo 'fs.inotify.max_user_watches=${RECOMMENDED_WATCHES}' >> /etc/sysctl.d/99-k8s-inotify.conf"
    echo "    echo 'fs.inotify.max_user_instances=${RECOMMENDED_INSTANCES}' >> /etc/sysctl.d/99-k8s-inotify.conf"
    echo "    sysctl -p /etc/sysctl.d/99-k8s-inotify.conf"
fi

# K8s 特有建议
if pgrep -x containerd &>/dev/null; then
    echo ""
    echo "    containerd 优化建议:"
    echo "    减少不必要的容器日志监控（调整 logging driver 配置）"
fi

echo ""
echo "============================================================"
if [ "$EXIT_CODE" -eq 2 ]; then
    print_fail "inotify 诊断完成: inotify 资源即将耗尽，需要立即扩容"
elif [ "$EXIT_CODE" -eq 1 ]; then
    print_warn "inotify 诊断完成: inotify 配置偏低，建议扩容"
else
    print_ok "inotify 诊断完成: 一切正常"
fi
echo "============================================================"

exit $EXIT_CODE
