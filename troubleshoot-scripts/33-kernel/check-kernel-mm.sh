#!/bin/bash
# ============================================================================
# 模块33-内核诊断 (合并版)
# 脚本名称: check-kernel-mm.sh
# 功能: 内存管理 — PageCache + 缺页中断
# 用法: ./check-kernel-mm.sh [pid]
# 合并自: check-pagecache.sh + check-pagefault.sh
# ============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

TARGET_PID=""
[ -n "$1" ] && { TARGET_PID=$1; if ! kill -0 "$TARGET_PID" 2>/dev/null; then print_fail "PID=$TARGET_PID 不存在"; exit 1; fi; print_info "指定PID: $TARGET_PID"; }

echo "============================================================"
echo "    内存管理诊断 — PageCache | 缺页 | Swap"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

ISSUE_COUNT=0

# ======================== PageCache ========================
print_info ">>> [PC/1] PageCache统计 ..."
MEMINFO=$(cat /proc/meminfo 2>/dev/null)
CACHED=$(echo "$MEMINFO" | grep "^Cached:" | awk '{print $2}')
DIRTY=$(echo "$MEMINFO" | grep "^Dirty:" | awk '{print $2}')
WRITEBACK=$(echo "$MEMINFO" | grep "^Writeback:" | awk '{print $2}')
MAPPED=$(echo "$MEMINFO" | grep "^Mapped:" | awk '{print $2}')
ACTIVE_FILE=$(echo "$MEMINFO" | grep "^Active(file):" | awk '{print $2}')
INACTIVE_FILE=$(echo "$MEMINFO" | grep "^Inactive(file):" | awk '{print $2}')
SLAB=$(echo "$MEMINFO" | grep "^SReclaimable:" | awk '{print $2}')

printf "    %-25s %-12s %s\n" "指标" "大小" "说明"
printf "    %-25s %-12s %s\n" "Cached" "$((CACHED/1024))MB" "页缓存"
printf "    %-25s %-12s %s\n" "Dirty" "$((DIRTY/1024))MB" "脏页(待写入)"
printf "    %-25s %-12s %s\n" "Writeback" "$((WRITEBACK/1024))MB" "正在回写"
printf "    %-25s %-12s %s\n" "Mapped" "$((MAPPED/1024))MB" "被映射文件"
printf "    %-25s %-12s %s\n" "Active(file)" "$((ACTIVE_FILE/1024))MB" "活跃文件页"
printf "    %-25s %-12s %s\n" "Inactive(file)" "$((INACTIVE_FILE/1024))MB" "非活跃文件页"
printf "    %-25s %-12s %s\n" "SReclaimable" "$((SLAB/1024))MB" "可回收slab"

# 脏页判断
[ "$DIRTY" -gt 1048576 ] && { print_warn "脏页过多 ($((DIRTY/1024))MB > 1GB)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "脏页正常 ($((DIRTY/1024))MB)"
echo ""

# 脏页参数
print_info ">>> [PC/2] 脏页内核参数 ..."
DR=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null); DBR=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null)
DEC=$(cat /proc/sys/vm/dirty_expire_centisecs 2>/dev/null); DWC=$(cat /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null)
echo "    dirty_ratio=${DR}%  background_ratio=${DBR}%  expire=$((DEC/100))s  writeback=$((DWC/100))s"
[ "$DR" -gt 20 ] && print_warn "dirty_ratio偏高(${DR}%)" || print_ok "dirty_ratio合理"
[ "$DBR" -gt 10 ] && print_warn "dirty_background_ratio偏高(${DBR}%)" || print_ok "dirty_background_ratio合理"
echo ""


# ======================== 缺页中断 ========================
print_info ">>> [PF/1] 缺页统计 ..."
if command -v sar &>/dev/null; then
    SR=$(sar -B 1 3 2>/dev/null | tail -1)
    MAJFLT=$(echo "$SR" | awk '{print $6}')
    echo "    主缺页(majflt/s): ${MAJFLT}"
    MAJFLT_INT=${MAJFLT%.*}
    [ "$MAJFLT_INT" -gt 100 ] && { print_fail "主缺页过高 (${MAJFLT}/s)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
    { [ "$MAJFLT_INT" -gt 10 ] && print_warn "主缺页偏高 (${MAJFLT}/s)"; } || print_ok "主缺页正常"
else
    PGFAULT=$(cat /proc/vmstat 2>/dev/null | grep "^pgfault" | awk '{print $2}')
    PGMAJFAULT=$(cat /proc/vmstat 2>/dev/null | grep "^pgmajfault" | awk '{print $2}')
    echo "    pgfault(总): ${PGFAULT}  pgmajfault(主): ${PGMAJFAULT}"
fi

# 进程级缺页
if [ -n "$TARGET_PID" ]; then
    PROC_MINFLT=$(awk '{print $10}' /proc/$TARGET_PID/stat 2>/dev/null)
    PROC_MAJFLT=$(awk '{print $12}' /proc/$TARGET_PID/stat 2>/dev/null)
    echo "    进程缺页: minflt=${PROC_MINFLT} majflt=${PROC_MAJFLT}"
else
    print_info "    缺页TOP5进程:"
    ps -eo pid,minflt,majflt,comm --sort=-majflt | head -6 | awk 'NR==1{printf "    %-8s %-12s %-12s %s\n", "PID","MINFLT","MAJFLT","CMD"} NR>1{printf "    %-8s %-12s %-12s %s\n", $1,$2,$3,$4}'
fi
echo ""


# ======================== Swap ========================
print_info ">>> [SWP/1] Swap与Swappiness ..."
SWAP_TOTAL_KB=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
SWAP_FREE_KB=$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2}')
SWAP_USED_KB=$((SWAP_TOTAL_KB - SWAP_FREE_KB))
SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null)

echo "    Swap使用: $((SWAP_USED_KB/1024))MB / $((SWAP_TOTAL_KB/1024))MB"
echo "    vm.swappiness = ${SWAPPINESS}"

[ "$SWAP_TOTAL_KB" -eq 0 ] && print_info "未配置Swap"
[ "$SWAP_USED_KB" -gt 0 ] && { print_warn "Swap被使用 ($((SWAP_USED_KB/1024))MB)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ "$SWAPPINESS" -gt 60 ] && print_warn "swappiness偏高(${SWAPPINESS})" || print_ok "swappiness合理(${SWAPPINESS})"

# VFS/overcommit/min_free
echo "    vfs_cache_pressure=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"
echo "    overcommit_memory=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null)"
echo "    min_free_kbytes=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null)"

# Swap TOP
if [ "$SWAP_USED_KB" -gt 0 ]; then
    print_info "    Swap TOP5进程:"
    for pid in $(ls /proc/ 2>/dev/null | grep -E '^[0-9]+$' | head -500); do
        [ -f "/proc/$pid/status" ] && {
            VSWAP=$(grep "VmSwap" /proc/$pid/status 2>/dev/null | awk '{print $2}')
            [ -n "$VSWAP" ] && [ "$VSWAP" != "0" ] && echo "$VSWAP $pid $(cat /proc/$pid/comm 2>/dev/null)"
        }
    done 2>/dev/null | sort -rn | head -5 | while read vs pid cmd; do
        echo "    PID=$pid ${cmd}: ${vs}KB swap"
    done
fi

# 内存回收
DMESG_RECLAIM=$(dmesg 2>/dev/null | grep -i "direct reclaim" | tail -2)
[ -n "$DMESG_RECLAIM" ] && print_warn "直接内存回收事件: $(echo $DMESG_RECLAIM | wc -l)条"
# ======================== HugePages ========================
print_info ">>> [HP/1] HugePages 大页内存 ..."
HP_TOTAL=$(awk '/HugePages_Total/{print $2}' /proc/meminfo 2>/dev/null)
HP_FREE=$(awk '/HugePages_Free/{print $2}' /proc/meminfo 2>/dev/null)
HP_SIZE=$(awk '/Hugepagesize/{print $2$3}' /proc/meminfo 2>/dev/null)
if [ "$HP_TOTAL" -gt 0 ] 2>/dev/null; then
    HP_USED=$((HP_TOTAL - HP_FREE))
    HP_PCT=$((HP_USED * 100 / HP_TOTAL))
    echo "    总数: ${HP_TOTAL}  已用: ${HP_USED}  空闲: ${HP_FREE}  (${HP_SIZE}/页)"
    [ "$HP_PCT" -ge 90 ] && { print_fail "HugePages 使用率 ${HP_PCT}% (余量不足)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
    [ "$HP_PCT" -ge 70 ] && [ "$HP_PCT" -lt 90 ] && print_warn "HugePages 使用率 ${HP_PCT}%"
else
    echo "    HugePages 未启用 (总计=0)"
fi
# THP (Transparent HugePages)
THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)
[ -n "$THP" ] && echo "    THP状态: $THP"
echo ""

echo ""
echo "============================================================"
echo "                   内存管理诊断结论"
echo "============================================================"
[ "$ISSUE_COUNT" -eq 0 ] && echo -e "  ${GREEN}[正常]${NC} PageCache/缺页/Swap状态健康"
echo "============================================================"
