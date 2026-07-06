#!/bin/bash
# ============================================================================
# 模块29-K8S故障排查 (节点修复)
# 脚本名称: fix-inotify.sh
# 功能: 自动修复 inotify 资源不足
# 用法: ./fix-inotify.sh
# 说明: 增大 max_user_watches 和 max_user_instances
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_info() { echo -e "[INFO] $1"; }
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "============================================================"
echo "          inotify 自动修复"
echo "          执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

CHANGED=false

# 1. max_user_watches
CURRENT_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null)
TARGET_WATCHES=1048576
# 检测节点类型: 如果是 K8s 节点推荐更大值
if pgrep -x kubelet &>/dev/null || pgrep -x containerd &>/dev/null; then
    TARGET_WATCHES=2097152
fi

if [ -n "$CURRENT_WATCHES" ] && [ "$CURRENT_WATCHES" -lt "$TARGET_WATCHES" ]; then
    print_info "max_user_watches: ${CURRENT_WATCHES} → ${TARGET_WATCHES}"
    sudo sysctl -w fs.inotify.max_user_watches="$TARGET_WATCHES" >/dev/null 2>&1
    print_ok "max_user_watches 已更新"
    CHANGED=true
else
    print_ok "max_user_watches 已足够 (${CURRENT_WATCHES})"
fi

# 2. max_user_instances
CURRENT_INSTANCES=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null)
TARGET_INSTANCES=1024

if [ -n "$CURRENT_INSTANCES" ] && [ "$CURRENT_INSTANCES" -lt "$TARGET_INSTANCES" ]; then
    print_info "max_user_instances: ${CURRENT_INSTANCES} → ${TARGET_INSTANCES}"
    sudo sysctl -w fs.inotify.max_user_instances="$TARGET_INSTANCES" >/dev/null 2>&1
    print_ok "max_user_instances 已更新"
    CHANGED=true
else
    print_ok "max_user_instances 已足够 (${CURRENT_INSTANCES})"
fi

# 3. max_queued_events
CURRENT_QUEUED=$(cat /proc/sys/fs/inotify/max_queued_events 2>/dev/null)
TARGET_QUEUED=65536

if [ -n "$CURRENT_QUEUED" ] && [ "$CURRENT_QUEUED" -lt "$TARGET_QUEUED" ]; then
    print_info "max_queued_events: ${CURRENT_QUEUED} → ${TARGET_QUEUED}"
    sudo sysctl -w fs.inotify.max_queued_events="$TARGET_QUEUED" >/dev/null 2>&1
    print_ok "max_queued_events 已更新"
    CHANGED=true
fi

echo ""

# 4. 持久化
if $CHANGED; then
    print_info "持久化配置..."
    SYSCTL_FILE="/etc/sysctl.d/99-k8s-inotify.conf"
    sudo bash -c "cat > $SYSCTL_FILE << EOF
# K8s 节点 inotify 优化
fs.inotify.max_user_watches = ${TARGET_WATCHES}
fs.inotify.max_user_instances = ${TARGET_INSTANCES}
fs.inotify.max_queued_events = ${TARGET_QUEUED}
EOF"
    sudo sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1
    print_ok "配置已持久化到 ${SYSCTL_FILE}"
else
    print_ok "所有 inotify 参数已满足要求，无需修改"
fi

echo ""
echo "============================================================"
print_ok "inotify 修复完成"
echo "============================================================"
