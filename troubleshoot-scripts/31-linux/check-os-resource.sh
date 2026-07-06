#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本 (合并版)
# 脚本名称: check-os-resource.sh
# 功能: CPU + 内存 + FD 三大核心资源诊断
# 用法: ./check-os-resource.sh [pid]
# 合并自: check-cpu.sh + check-memory.sh + check-fd.sh
# ============================================================================

# ======================== 颜色输出函数 ========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

TARGET_PID=""
[ -n "$1" ] && { TARGET_PID=$1; if ! kill -0 "$TARGET_PID" 2>/dev/null; then print_fail "进程 PID=$TARGET_PID 不存在"; exit 1; fi; print_info "指定进程 PID=$TARGET_PID"; }

echo "============================================================"
echo "    核心资源综合诊断 — CPU | 内存 | FD"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== CPU ========================
print_info ">>> [CPU/1] 整体CPU使用率 ..."
CPU_LINE=$(top -bn1 2>/dev/null | head -20 | grep '%Cpu(s)')

_cpu_extract() {
    local val
    val=$(echo "$CPU_LINE" | sed -E "s/.*[^0-9]([0-9.]+)[[:space:]]*$1.*/\1/" 2>/dev/null)
    echo "$val" | grep -qE '^[0-9.]+$' && echo "$val" || echo "0"
}
CPU_US=$(_cpu_extract "us"); CPU_US=${CPU_US%.*}
CPU_SY=$(_cpu_extract "sy"); CPU_SY=${CPU_SY%.*}
CPU_WA=$(_cpu_extract "wa"); CPU_WA=${CPU_WA%.*}
CPU_ID=$(_cpu_extract "id"); CPU_ID=${CPU_ID%.*}

# fallback mpstat
if [ -z "$CPU_LINE" ] || { [ "$CPU_US" = "0" ] && [ "$CPU_SY" = "0" ] && [ "$CPU_ID" = "0" ]; }; then
    CPU_RAW=$(mpstat 1 1 2>/dev/null | tail -1)
    CPU_US=$(echo "$CPU_RAW" | awk '{print $3}' | cut -d. -f1); CPU_US=${CPU_US:-0}
    CPU_SY=$(echo "$CPU_RAW" | awk '{print $5}' | cut -d. -f1); CPU_SY=${CPU_SY:-0}
    CPU_WA=$(echo "$CPU_RAW" | awk '{print $6}' | cut -d. -f1); CPU_WA=${CPU_WA:-0}
    CPU_ID=$(echo "$CPU_RAW" | awk '{print $NF}' | cut -d. -f1); CPU_ID=${CPU_ID:-0}
fi
CPU_US=${CPU_US:-0}; CPU_SY=${CPU_SY:-0}; CPU_WA=${CPU_WA:-0}; CPU_ID=${CPU_ID:-0}

echo "    用户态(us): ${CPU_US}%  |  内核态(sy): ${CPU_SY}%  |  IO等待(wa): ${CPU_WA}%  |  空闲(id): ${CPU_ID}%"

[ "$CPU_US" -gt 80 ] && print_fail "用户态CPU过高 (${CPU_US}%)" || { [ "$CPU_US" -gt 60 ] && print_warn "用户态CPU偏高 (${CPU_US}%)"; } || print_ok "用户态CPU正常 (${CPU_US}%)"
[ "$CPU_SY" -gt 30 ] && print_fail "内核态CPU过高 (${CPU_SY}%)" || { [ "$CPU_SY" -gt 20 ] && print_warn "内核态CPU偏高 (${CPU_SY}%)"; } || print_ok "内核态CPU正常 (${CPU_SY}%)"
[ "$CPU_WA" -gt 20 ] && print_fail "IO等待过高 (${CPU_WA}%)" || { [ "$CPU_WA" -gt 10 ] && print_warn "IO等待偏高 (${CPU_WA}%)"; } || print_ok "IO等待正常 (${CPU_WA}%)"
echo ""

# CPU - 进程级
if [ -n "$TARGET_PID" ]; then
    print_info ">>> [CPU/2] 进程 PID=$TARGET_PID CPU分析 ..."
    PROC_CPU=$(ps -p "$TARGET_PID" -o %cpu --no-headers 2>/dev/null | awk '{printf "%.1f", $1}')
    PROC_NAME=$(ps -p "$TARGET_PID" -o comm --no-headers 2>/dev/null)
    PROC_CPU_INT=${PROC_CPU%.*}
    PROC_THREADS=$(ps -o nlwp -p "$TARGET_PID" --no-headers 2>/dev/null)
    echo "    进程: ${PROC_NAME}  CPU: ${PROC_CPU}%  线程: ${PROC_THREADS}"
    [ "$PROC_CPU_INT" -gt 80 ] && print_fail "进程CPU过高" || { [ "$PROC_CPU_INT" -gt 50 ] && print_warn "进程CPU偏高"; } || print_ok "进程CPU正常"
else
    print_info ">>> [CPU/2] CPU TOP5 进程 ..."
    ps aux --sort=-%cpu | head -6 | awk 'NR==1{printf "    %-10s %-8s %-6s %-6s %s\n", "USER", "PID", "CPU%", "MEM%", "COMMAND"} NR>1{printf "    %-10s %-8s %-6s %-6s %s\n", $1, $2, $3, $4, $11}'
fi
echo ""

# CPU - 上下文切换
print_info ">>> [CPU/3] 上下文切换率 ..."
VMSTAT_DATA=$(vmstat 1 3 2>/dev/null | tail -1)
CS_VALUE=$(echo "$VMSTAT_DATA" | awk '{print $12}'); CS_VALUE=${CS_VALUE:-0}
echo "    上下文切换率: ${CS_VALUE}/s"
[ "$CS_VALUE" -gt 50000 ] && print_fail "上下文切换极高 (${CS_VALUE}/s)" || { [ "$CS_VALUE" -gt 10000 ] && print_warn "上下文切换偏高 (${CS_VALUE}/s)"; } || print_ok "上下文切换正常 (${CS_VALUE}/s)"
echo ""

# CPU - 系统负载
print_info ">>> [CPU/4] 系统负载 ..."
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
LOAD_1M=$(echo "$LOAD_AVG" | awk '{print $1}' | tr -d ',')
LOAD_5M=$(echo "$LOAD_AVG" | awk '{print $2}' | tr -d ',')
LOAD_15M=$(echo "$LOAD_AVG" | awk '{print $3}')
CPU_CORES=$(nproc)
echo "    核心数: ${CPU_CORES}  |  负载: 1m=${LOAD_1M} 5m=${LOAD_5M} 15m=${LOAD_15M}"

LOAD_INT=$(echo "$LOAD_1M" | awk '{printf "%d", $1}')
LOAD_THRESHOLD=$((CPU_CORES * 2))
[ "$LOAD_INT" -gt "$LOAD_THRESHOLD" ] && print_fail "负载过高 (${LOAD_1M} > ${LOAD_THRESHOLD})" || { [ "$LOAD_INT" -gt "$CPU_CORES" ] && print_warn "负载偏高 (${LOAD_1M})"; } || print_ok "负载正常 (${LOAD_1M})"
echo ""


# ======================== 内存 ========================
print_info ">>> [MEM/1] 内存使用情况 ..."
MEM_INFO=$(free -h)
MEM_TOTAL=$(echo "$MEM_INFO" | awk '/^Mem:/{print $2}')
MEM_USED=$(echo "$MEM_INFO" | awk '/^Mem:/{print $3}')
MEM_AVAILABLE=$(echo "$MEM_INFO" | awk '/^Mem:/{print $7}')

MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAILABLE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
[ "$MEM_TOTAL_KB" -gt 0 ] && AVAILABLE_PCT=$((MEM_AVAILABLE_KB * 100 / MEM_TOTAL_KB)) || AVAILABLE_PCT=100

echo "    总内存: ${MEM_TOTAL}  |  已用: ${MEM_USED}  |  可用: ${MEM_AVAILABLE} (${AVAILABLE_PCT}%)"
[ "$AVAILABLE_PCT" -lt 20 ] && print_fail "可用内存严重不足 (${AVAILABLE_PCT}%)" || { [ "$AVAILABLE_PCT" -lt 40 ] && print_warn "可用内存偏低 (${AVAILABLE_PCT}%)"; } || print_ok "可用内存充足 (${AVAILABLE_PCT}%)"
echo ""

# 内存 - Swap
print_info ">>> [MEM/2] Swap使用 ..."
SWAP_TOTAL=$(echo "$MEM_INFO" | awk '/^Swap:/{print $2}')
SWAP_USED=$(echo "$MEM_INFO" | awk '/^Swap:/{print $3}')
SWAP_TOTAL_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
SWAP_FREE_KB=$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2}')
[ -z "$SWAP_FREE_KB" ] && SWAP_USED_KB=0 || SWAP_USED_KB=$((SWAP_TOTAL_KB - SWAP_FREE_KB))

echo "    Swap总量: ${SWAP_TOTAL}  |  已用: ${SWAP_USED}"
[ "$SWAP_TOTAL_KB" -eq 0 ] && print_info "未配置Swap" || { [ "$SWAP_USED_KB" -gt 0 ] && print_warn "Swap已被使用 (${SWAP_USED})，物理内存可能不足"; } || print_ok "Swap未使用，物理内存充足"
echo ""

# 内存 - TOP进程
print_info ">>> [MEM/3] 内存TOP10进程 ..."
printf "    %-10s %-8s %-8s %-8s %s\n" "USER" "PID" "RSS" "%MEM" "COMMAND"
ps aux --sort=-%mem | head -11 | tail -10 | awk '{printf "    %-10s %-8s %-8s %-8s %s\n", $1, $2, $6, $4"%", $11}'

HIGH_MEM=$(ps aux --sort=-%mem | awk 'NR>1 && $4+0 > 50 {print "    PID="$2" "$11" "$4"%"}')
[ -n "$HIGH_MEM" ] && echo "" && print_warn "以下进程内存>50%:" && echo "$HIGH_MEM"
echo ""

# 内存 - OOM
print_info ">>> [MEM/4] OOM事件 ..."
OOM_LOGS=$(dmesg 2>/dev/null | grep -i "killed process" | tail -5)
if [ -z "$OOM_LOGS" ]; then
    print_ok "未检测到OOM Killer"
else
    OOM_COUNT=$(dmesg 2>/dev/null | grep -ci "killed process")
    print_fail "检测到 ${OOM_COUNT} 次OOM Killer!"
    echo "$OOM_LOGS" | while read line; do echo "    $line"; done
fi
echo ""


# ======================== FD/资源限制 ========================
print_info ">>> [FD/1] 系统FD使用率 ..."
FILE_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null)
FILE_NR=$(cat /proc/sys/fs/file-nr 2>/dev/null)
if [ -n "$FILE_NR" ] && [ -n "$FILE_MAX" ]; then
    FD_ALLOCATED=$(echo "$FILE_NR" | awk '{print $1}')
    FD_UNUSED=$(echo "$FILE_NR" | awk '{print $2}')
    [ "$FILE_MAX" -gt 0 ] && FD_PCT=$((FD_ALLOCATED * 100 / FILE_MAX)) || FD_PCT=0
    echo "    上限: ${FILE_MAX}  |  已分配: ${FD_ALLOCATED}  |  使用率: ${FD_PCT}%"
    [ "$FD_PCT" -gt 80 ] && print_fail "系统FD过高 (${FD_PCT}%)" || { [ "$FD_PCT" -gt 60 ] && print_warn "系统FD偏高 (${FD_PCT}%)"; } || print_ok "系统FD正常 (${FD_PCT}%)"
else
    print_warn "无法读取FD信息"
fi
echo ""

# FD - 进程级
print_info ">>> [FD/2] 进程FD TOP10 ..."
printf "    %-8s %-8s %-20s %s\n" "PID" "FD数" "进程名" "上限(soft/hard)"
FD_TOP=$(for pd in /proc/[0-9]*; do
    pid=$(basename "$pd")
    fd_count=$(ls "$pd/fd" 2>/dev/null | wc -l)
    [ "$fd_count" -gt 0 ] || continue
    comm=$(cat "$pd/comm" 2>/dev/null)
    soft=$(cat "$pd/limits" 2>/dev/null | grep "open files" | awk '{print $4}')
    hard=$(cat "$pd/limits" 2>/dev/null | grep "open files" | awk '{print $5}')
    echo "$pid $fd_count $comm ${soft:-?}/${hard:-?}"
done | sort -t' ' -k2 -rn | head -10)

echo "$FD_TOP" | while read pid fd_cnt comm limits; do
    printf "    %-8s %-8s %-20s %s\n" "$pid" "$fd_cnt" "$comm" "$limits"
done

# 检测FD泄漏
echo "$FD_TOP" | while read pid fd_cnt comm limits; do
    soft=$(echo "$limits" | cut -d/ -f1)
    if [ "$soft" != "?" ] && [ "$soft" != "unlimited" ] && [ "$soft" -gt 0 ] 2>/dev/null; then
        pct=$((fd_cnt * 100 / soft))
        [ "$pct" -gt 80 ] && echo -e "    ${YELLOW}[WARN]${NC} PID=$pid ($comm): ${fd_cnt}/${soft} ($pct%)"
    fi
done
echo ""

# FD - PID检查
print_info ">>> [FD/3] PID使用情况 ..."
PROC_COUNT=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l)
PID_MAX=$(cat /proc/sys/kernel/pid_max 2>/dev/null)
ZOMBIE_COUNT=$(ps aux 2>/dev/null | awk '$8 ~ /^Z/ {print}' | wc -l)
echo "    进程数: ${PROC_COUNT}  |  PID上限: ${PID_MAX}  |  僵尸进程: ${ZOMBIE_COUNT}"

if [ -n "$PID_MAX" ] && [ "$PID_MAX" -gt 0 ]; then
    PID_PCT=$((PROC_COUNT * 100 / PID_MAX))
    [ "$PID_PCT" -gt 70 ] && print_fail "PID使用率过高 (${PID_PCT}%)" || { [ "$PID_PCT" -gt 50 ] && print_warn "PID使用率偏高 (${PID_PCT}%)"; } || print_ok "PID使用率正常 (${PID_PCT}%)"
fi
[ "$ZOMBIE_COUNT" -gt 0 ] && print_warn "存在 ${ZOMBIE_COUNT} 个僵尸进程" || print_ok "无僵尸进程"
echo ""

# FD - ulimit
print_info ">>> [FD/4] 资源限制 ..."
OPEN_FILES_LIMIT=$(ulimit -n 2>/dev/null)
[ "$OPEN_FILES_LIMIT" -lt 1024 ] && print_fail "open files过低 (${OPEN_FILES_LIMIT})" || { [ "$OPEN_FILES_LIMIT" -lt 65535 ] && print_warn "open files偏低 (${OPEN_FILES_LIMIT})"; } || print_ok "open files合理 (${OPEN_FILES_LIMIT})"
MAX_USER_PROC=$(ulimit -u 2>/dev/null)
[ "${MAX_USER_PROC:-0}" -lt 4096 ] 2>/dev/null && print_warn "max user processes偏低 (${MAX_USER_PROC})"
echo ""

# FD - /proc/sys 关键参数
print_info ">>> [FD/5] 内核资源参数 ..."
for param in \
    "fs.file-max:/proc/sys/fs/file-max:系统FD上限" \
    "fs.nr_open:/proc/sys/fs/nr_open:单进程最大FD" \
    "kernel.pid_max:/proc/sys/kernel/pid_max:最大PID" \
    "kernel.threads-max:/proc/sys/kernel/threads-max:最大线程" \
    "net.core.somaxconn:/proc/sys/net/core/somaxconn:监听队列" \
    "net.ipv4.tcp_max_syn_backlog:/proc/sys/net/ipv4/tcp_max_syn_backlog:SYN队列"; do
    LABEL=$(echo "$param" | cut -d: -f1)
    PATH_=$(echo "$param" | cut -d: -f2)
    DESC=$(echo "$param" | cut -d: -f3)
    VALUE=$(cat "$PATH_" 2>/dev/null)
    [ -n "$VALUE" ] && printf "    %-35s = %-10s # %s\n" "$LABEL" "$VALUE" "$DESC"
done

echo ""
echo "============================================================"
echo "                     综合诊断结论"
echo "============================================================"
ISSUE_COUNT=0

# CPU
[ "$CPU_US" -gt 80 ] || [ "$CPU_SY" -gt 30 ] || [ "$CPU_WA" -gt 20 ] && { echo -e "  ${RED}[严重]${NC} CPU瓶颈"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ "$CS_VALUE" -gt 10000 ] && { echo -e "  ${YELLOW}[警告]${NC} 上下文切换偏高"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ "${LOAD_INT:-0}" -gt "$CPU_CORES" ] && { echo -e "  ${YELLOW}[警告]${NC} 系统负载偏高"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }

# Memory
[ "$AVAILABLE_PCT" -lt 20 ] && { echo -e "  ${RED}[严重]${NC} 可用内存不足${AVAILABLE_PCT}%"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
{ [ "$AVAILABLE_PCT" -lt 40 ] && [ "$AVAILABLE_PCT" -ge 20 ]; } && { echo -e "  ${YELLOW}[警告]${NC} 可用内存偏低${AVAILABLE_PCT}%"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ "$SWAP_USED_KB" -gt 0 ] && [ "$SWAP_TOTAL_KB" -gt 0 ] && { echo -e "  ${YELLOW}[警告]${NC} Swap被使用"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ -n "$OOM_LOGS" ] && { echo -e "  ${RED}[严重]${NC} 存在OOM事件"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }

# FD
[ "${FD_PCT:-0}" -gt 80 ] && { echo -e "  ${RED}[严重]${NC} 系统FD使用率${FD_PCT}%"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ "${PID_PCT:-0}" -gt 70 ] && { echo -e "  ${RED}[严重]${NC} PID使用率${PID_PCT}%"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ "$OPEN_FILES_LIMIT" -lt 1024 ] && { echo -e "  ${RED}[严重]${NC} open files过低(${OPEN_FILES_LIMIT})"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ -n "$ZOMBIE_COUNT" ] && [ "$ZOMBIE_COUNT" -gt 0 ] && { echo -e "  ${YELLOW}[警告]${NC} 僵尸进程: ${ZOMBIE_COUNT}"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }

[ "$ISSUE_COUNT" -eq 0 ] && echo -e "  ${GREEN}[正常]${NC} CPU/内存/FD三大核心资源状态健康"
echo "============================================================"
