#!/bin/bash
# ============================================================================
# 模块33-内核诊断 (合并版)
# 脚本名称: check-kernel-sys.sh
# 功能: 系统调用 + 调度器分析
# 用法: ./check-kernel-sys.sh [pid]
# 合并自: check-syscall.sh + check-scheduler.sh
# ============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

TARGET_PID=""
[ -n "$1" ] && { TARGET_PID=$1; if ! kill -0 "$TARGET_PID" 2>/dev/null; then print_fail "PID=$TARGET_PID 不存在"; exit 1; fi; print_info "指定PID: $TARGET_PID"; }

echo "============================================================"
echo "    调度与系统调用 — 调度器 | 系统调用分析"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

ISSUE_COUNT=0
CPU_CORES=$(nproc)

# ======================== 调度器 ========================
print_info ">>> [SCH/1] CPU与调度 ..."
echo "    CPU型号: $(lscpu 2>/dev/null | grep 'Model name:' | sed 's/.*: *//')"
echo "    逻辑核心: ${CPU_CORES}  |  插槽: $(lscpu 2>/dev/null | grep 'Socket(s):' | awk '{print $2}')"
echo ""

# 上下文切换
print_info ">>> [SCH/2] 上下文切换率 (采样3秒) ..."
VMSTAT_SAMPLES=$(vmstat 1 3 2>/dev/null)
CS_SUM=0; CS_CNT=0; R_SUM=0; R_CNT=0; R_MAX=0

echo "$VMSTAT_SAMPLES" | awk 'NR>2' | while read r b swpd free buff cache si so bi bo in cs us sy id wa st; do
    [ -n "$cs" ] && echo "$cs $r"
done > /tmp/.vmstat_parsed.$$
while read cs r; do
    CS_SUM=$((CS_SUM + cs)); CS_CNT=$((CS_CNT + 1))
    R_SUM=$((R_SUM + r)); R_CNT=$((R_CNT + 1))
    [ "$r" -gt "$R_MAX" ] && R_MAX=$r
done < /tmp/.vmstat_parsed.$$ 2>/dev/null

CS_AVG=$([ "$CS_CNT" -gt 0 ] && echo $((CS_SUM / CS_CNT)) || echo 0)
R_AVG=$([ "$R_CNT" -gt 0 ] && echo $((R_SUM / R_CNT)) || echo 0)
rm -f /tmp/.vmstat_parsed.$$

echo "    上下文切换: ${CS_AVG}/s  (每核: $((CS_AVG/CPU_CORES))/s)"
[ "$CS_AVG" -gt 50000 ] && { print_fail "上下文切换极高 (${CS_AVG}/s)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
{ [ "$CS_AVG" -gt 10000 ] && print_warn "上下文切换偏高 (${CS_AVG}/s)"; } || print_ok "上下文切换正常"

# 运行队列
echo "    运行队列: avg=${R_AVG} max=${R_MAX}  (核心数=${CPU_CORES})"
[ "$R_MAX" -gt $((CPU_CORES*2)) ] && { print_fail "运行队列过长 (max=${R_MAX})"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || \
{ [ "$R_MAX" -gt "$CPU_CORES" ] && print_warn "运行队列偏长 (max=${R_MAX})"; } || print_ok "运行队列正常"

# 线程TOP
print_info "    线程数TOP5:"
ps -eo pid,nlwp,comm --sort=-nlwp | head -6 | awk 'NR==1{printf "    %-8s %-8s %s\n","PID","线程","CMD"} NR>1{printf "    %-8s %-8s %s\n",$1,$2,$3}'
echo ""


# ======================== 系统调用 ========================
print_info ">>> [SYS/1] 系统调用分析 ..."
if [ -n "$TARGET_PID" ]; then
    PROC_NAME=$(ps -p "$TARGET_PID" -o comm --no-headers 2>/dev/null)
    echo "    进程: ${PROC_NAME} (PID=${TARGET_PID})"

    if command -v strace &>/dev/null; then
        print_info "strace采样3秒..."
        STRACE_R=$(timeout 3 strace -c -p "$TARGET_PID" 2>&1)
        echo "$STRACE_R" | grep -v "^strace:" | tail -n +2 | head -20 | while read l; do echo "    $l"; done

        # 高频syscall分析
        STRACE_TOP=$(echo "$STRACE_R" | awk 'NR>2 && $1!~/total/ && $1!~/---/ && $1+0>0 {print $1, $6}' | sort -rn | head -5)
        [ -n "$STRACE_TOP" ] && {
            echo ""
            echo "$STRACE_TOP" | while read cnt sc; do
                case "$sc" in
                    read|write) echo "    - $sc频率高(${cnt}次): 考虑更大缓冲区或mmap";;
                    futex) echo "    - futex频率高(${cnt}次): 存在锁竞争";;
                    mmap|munmap) echo "    - mmap/munmap频繁(${cnt}次): 考虑内存池";;
                    clone) echo "    - clone频繁(${cnt}次): 考虑线程池";;
                    open|openat) echo "    - open频繁(${cnt}次): 考虑文件缓存";;
                    epoll_wait|poll|select) echo "    - IO多路复用频繁(${cnt}次): 检查事件循环";;
                    *) echo "    - ${sc}高频(${cnt}次)";;
                esac
            done
        }
    else
        print_warn "strace不可用"
    fi

    # utime/stime
    if [ -f "/proc/$TARGET_PID/stat" ]; then
        UTIME=$(awk '{print $14}' /proc/$TARGET_PID/stat)
        STIME=$(awk '{print $15}' /proc/$TARGET_PID/stat)
        THREADS=$(awk '{print $20}' /proc/$TARGET_PID/stat)
        HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
        TOTAL=$((UTIME + STIME))
        [ "$TOTAL" -gt 0 ] && KERNEL_PCT=$((STIME * 100 / TOTAL))
        echo "    utime/stime比例: $(echo "scale=1; $KERNEL_PCT" | bc 2>/dev/null || echo $KERNEL_PCT)%内核态"
        [ "$KERNEL_PCT" -gt 50 ] && print_warn "内核态占比过高 (${KERNEL_PCT}%)"
    fi
else
    print_info "跳过进程级syscall分析 (未指定PID)"
    print_info "用法: ./check-kernel-sys.sh <pid>"
fi
echo ""

# 全局CPU分布
print_info ">>> [SYS/2] 全局CPU时间分布 ..."
CPU_STATS=$(cat /proc/stat 2>/dev/null | grep "^cpu ")
if [ -n "$CPU_STATS" ]; then
    USER=$(echo "$CPU_STATS" | awk '{print $2}'); SYSTEM=$(echo "$CPU_STATS" | awk '{print $4}')
    IDLE=$(echo "$CPU_STATS" | awk '{print $5}'); IOWAIT=$(echo "$CPU_STATS" | awk '{print $6}')
    TOTAL=$((USER + SYSTEM + IDLE + IOWAIT))
    [ "$TOTAL" -gt 0 ] && {
        printf "    用户态:%d%% 内核态:%d%% 空闲:%d%% IO等待:%d%%\n" \
            $((USER*100/TOTAL)) $((SYSTEM*100/TOTAL)) $((IDLE*100/TOTAL)) $((IOWAIT*100/TOTAL))
    }
fi
echo ""


echo "============================================================"
echo "                   调度与系统调用结论"
echo "============================================================"
[ "$ISSUE_COUNT" -eq 0 ] && echo -e "  ${GREEN}[正常]${NC} 调度和系统调用状态健康"
echo "============================================================"
