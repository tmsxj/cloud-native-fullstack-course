#!/bin/bash
# ============================================================================
# 自动修复脚本 - fix-service.sh
# 功能: 安全重启失败服务
# 用法: ./fix-service.sh [service-name] [--dry-run] [--all]
# 安全阈值: 仅重启已failed的服务, 最多尝试3次, 间隔5秒
# 说明: 自动检测失败服务并尝试安全重启
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

DRY_RUN=false
TARGET_SVC=""
FIX_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --all) FIX_ALL=true; shift ;;
        -h|--help)
            echo "用法: ./fix-service.sh [service-name] [--all] [--dry-run]"
            echo "  service-name  指定重启的服务名"
            echo "  --all         重启所有失败的服务"
            echo "  --dry-run     试运行, 不实际重启"
            exit 0 ;;
        *) TARGET_SVC="$1"; shift ;;
    esac
done

if ! pidof systemd &>/dev/null && [ ! -d /run/systemd/system ]; then
    print_warn "系统未使用systemd, 本工具仅支持systemd服务管理"
    exit 1
fi

echo "============================================================"
echo "          失败服务安全重启工具"
echo "          执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 服务安全白名单 ========================
# 禁止自动重启的服务 (可能导致系统不稳定)
NO_AUTO_RESTART=(
    "network.target"
    "network-online.target"
    "multi-user.target"
    "graphical.target"
    "dbus.service"
    "systemd-logind.service"
    "getty@.service"
    "serial-getty@.service"
    "emergency.service"
    "rescue.service"
)

_is_safe() {
    local svc="$1"
    for banned in "${NO_AUTO_RESTART[@]}"; do
        if [ "$svc" = "$banned" ]; then
            return 1
        fi
    done
    return 0
}

# ======================== 查找失败服务 ========================
FAILED_SVCS=""

if [ -n "$TARGET_SVC" ]; then
    # 指定服务
    STATE=$(systemctl is-active "$TARGET_SVC" 2>/dev/null || echo "unknown")
    if [ "$STATE" = "failed" ] || [ "$STATE" = "inactive" ]; then
        FAILED_SVCS="$TARGET_SVC"
        echo "    指定服务: $TARGET_SVC (状态: $STATE)"
    elif [ "$STATE" = "unknown" ]; then
        print_fail "服务 $TARGET_SVC 不存在"
        exit 1
    else
        print_ok "服务 $TARGET_SVC 当前状态: $STATE, 无需重启"
        exit 0
    fi
elif [ "$FIX_ALL" = true ]; then
    FAILED_SVCS=$(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}')
    if [ -z "$FAILED_SVCS" ]; then
        print_ok "未检测到失败的服务"
        exit 0
    fi
    FAILED_COUNT=$(echo "$FAILED_SVCS" | wc -l)
    print_warn "检测到 ${FAILED_COUNT} 个失败的服务"
else
    print_info "请指定服务名或使用 --all"
    echo ""
    echo "用法:"
    echo "  ./fix-service.sh <service-name>  重启指定服务"
    echo "  ./fix-service.sh --all          重启所有失败服务"
    echo "  ./fix-service.sh --dry-run      试运行模式"
    exit 1
fi

echo ""

# ======================== 重启服务 ========================
echo "============================================================"
echo "                    执行服务重启"
echo "============================================================"

SUCCESS_COUNT=0
FAIL_COUNT=0
SKIPPED_COUNT=0
MAX_ATTEMPTS=3

for svc in $FAILED_SVCS; do
    echo ""
    print_info ">>> 处理: $svc"

    SVC_STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
    echo "    当前状态: $SVC_STATE"

    # 安全检查
    if ! _is_safe "$svc"; then
        print_warn "  $svc 在禁止自动重启名单中, 跳过"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # 查看失败日志 (最近3条)
    echo "    最近日志:"
    journalctl --no-pager -u "$svc" -n 3 2>/dev/null | while read line; do
        echo "      $line"
    done

    if [ "$DRY_RUN" = true ]; then
        print_info "  [DRY-RUN] 会执行: systemctl restart $svc"
        continue
    fi

    # 执行重启 (带重试)
    RESTARTED=false
    for attempt in $(seq 1 $MAX_ATTEMPTS); do
        echo "    尝试重启 ($attempt/$MAX_ATTEMPTS) ..."

        # 先重置失败状态
        systemctl reset-failed "$svc" 2>/dev/null || true

        if systemctl restart "$svc" 2>/dev/null; then
            sleep 3
            NEW_STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
            if [ "$NEW_STATE" = "active" ]; then
                print_ok "  服务已恢复: $svc (active)"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                RESTARTED=true
                break
            else
                print_warn "  重启后状态: $NEW_STATE, 重试..."
            fi
        else
            print_warn "  重启命令失败, 重试..."
        fi
        sleep 5
    done

    if [ "$RESTARTED" = false ]; then
        print_fail "  服务 $svc 重启失败 ($MAX_ATTEMPTS 次尝试)"
        echo ""
        echo "    完整失败日志:"
        journalctl --no-pager -u "$svc" --since "1 minute ago" 2>/dev/null | tail -20 | while read line; do
            echo "      $line"
        done
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "============================================================"
echo "                     重启结果"
echo "============================================================"
echo "  成功: ${SUCCESS_COUNT} 个"
echo "  失败: ${FAIL_COUNT} 个"
echo "  跳过: ${SKIPPED_COUNT} 个"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    print_info "重启失败的服务需要手动排查:"
    print_info "  journalctl -u <service> -n 50"
    print_info "  systemctl status <service>"
fi

echo "============================================================"
