#!/bin/bash
# ============================================================================
# 自动修复脚本 - fix-zombie.sh
# 功能: 清理僵尸进程
# 用法: ./fix-zombie.sh [--dry-run]
# 安全阈值: 仅清理僵尸进程, 不影响正常进程
# 说明: 僵尸进程不可直接kill, 需要kill父进程或重启服务
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
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    print_info "*** 试运行模式 (不会实际操作) ***"
fi

echo "============================================================"
echo "          僵尸进程清理工具"
echo "          执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 检测僵尸进程 ========================
print_info ">>> 检测僵尸进程 ..."

ZOMBIES=$(ps aux 2>/dev/null | awk '$8 ~ /^Z/ {print $2, $11}')

if [ -z "$ZOMBIES" ]; then
    print_ok "未检测到僵尸进程, 无需处理"
    exit 0
fi

ZOMBIE_COUNT=$(echo "$ZOMBIES" | wc -l)
print_warn "检测到 ${ZOMBIE_COUNT} 个僵尸进程:"

echo "    ------------------------------------------------------------------"
printf "    %-8s %-10s %-15s %s\n" "ZOMBIE_PID" "PARENT_PID" "PARENT_NAME" "COMMAND"
echo "    ------------------------------------------------------------------"

declare -A PARENT_MAP
PARENT_LIST=""

echo "$ZOMBIES" | while read zpid zcmd; do
    # 获取僵尸进程的父进程
    PPID=$(cat /proc/"$zpid"/stat 2>/dev/null | awk '{print $4}')
    if [ -n "$PPID" ]; then
        PNAME=$(cat /proc/"$PPID"/comm 2>/dev/null || echo "unknown")
        echo "    $zpid     $PPID       $PNAME            $zcmd"
    fi
done
echo "    ------------------------------------------------------------------"
echo ""

# ======================== 分析僵尸进程 ========================
print_info ">>> 分析僵尸进程的父进程 ..."

# 说明: 僵尸进程状态为Z, 已经终止但父进程未wait()
# 解决方案: kill父进程或让父进程调用wait()

FIXED=0
SKIPPED=0

for zpid in $(ps aux | awk '$8 ~ /^Z/ {print $2}'); do
    PPID=$(cat /proc/"$zpid"/stat 2>/dev/null | awk '{print $4}')
    PNAME=$(cat /proc/"$PPID"/comm 2>/dev/null || echo "unknown")

    if [ -z "$PPID" ] || [ "$PPID" = "1" ]; then
        # 父进程是init/systemd, 这是罕见情况
        print_info "僵尸进程 $zpid 的父进程是init/systemd (PID=1), 系统即将自动回收"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # 检查父进程是否是用户登录shell (避免杀shell)
    if [ "$PNAME" = "bash" ] || [ "$PNAME" = "zsh" ] || [ "$PNAME" = "sh" ] || [ "$PNAME" = "sshd" ]; then
        print_warn "僵尸进程 $zpid 的父进程是 $PNAME (PID=$PPID), 跳过自动处理"
        print_info "建议: 手动确认后 kill -HUP $PPID 或重新登录"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo "    处理僵尸进程: PID=$zpid 父进程=$PNAME ($PPID)"

    if [ "$DRY_RUN" = false ]; then
        # 尝试SIGHUP先, 让父进程优雅回收
        if kill -HUP "$PPID" 2>/dev/null; then
            sleep 1
            # 检查僵尸是否消失
            if ! ps -p "$zpid" &>/dev/null 2>&1; then
                print_ok "  已通过HUP信号清理: PID=$zpid"
                FIXED=$((FIXED + 1))
                continue
            fi
        fi

        # HUP无效, 尝试kill父进程
        print_warn "  HUP信号无法清理, 尝试终止父进程 $PPID ($PNAME)"
        if kill "$PPID" 2>/dev/null; then
            sleep 1
            if ! ps -p "$zpid" &>/dev/null 2>&1; then
                print_ok "  已通过kill父进程清理: PID=$zpid"
                FIXED=$((FIXED + 1))
            else
                print_fail "  无法清理僵尸进程 $zpid"
            fi
        else
            print_fail "  无法kill父进程 $PPID (权限不足或进程受保护)"
        fi
    else
        print_info "  [DRY-RUN] 会尝试: kill -HUP $PPID, 无效则 kill $PPID"
    fi
done

echo ""
echo "============================================================"
echo "                     清理结果"
echo "============================================================"

REMAINING=$(ps aux 2>/dev/null | awk '$8 ~ /^Z/' | wc -l)
echo "  已清理: ${FIXED} 个"
echo "  已跳过: ${SKIPPED} 个"
echo "  剩余僵尸: ${REMAINING} 个"

if [ "$REMAINING" -gt 0 ]; then
    echo ""
    echo "  无法自动清理的僵尸进程 (父进程受保护):"
    ps aux 2>/dev/null | awk '$8 ~ /^Z/ {printf "    PID=%-8s CMD=%s\n", $2, $11}'
    echo ""
    print_info "建议: 重启对应的父进程服务 (systemctl restart <service>)"
else
    print_ok "所有僵尸进程已清理完成"
fi

echo "============================================================"
