#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本 (合并版)
# 脚本名称: check-os-process.sh
# 功能: 进程状态 + 启动诊断 + 日志扫描
# 用法: ./check-os-process.sh
# 合并自: check-process.sh + check-boot.sh + check-log.sh
# ============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

echo "============================================================"
echo "    进程与系统健康 — 进程状态 | 启动 | 日志扫描"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

ISSUE_COUNT=0

# ======================== 进程状态 ========================
print_info ">>> [PROC/1] 进程状态分布 ..."
ps aux | awk 'NR>1 {
    s=substr($8,1,1); count[s]++
} END {
    printf "    %-10s %-10s %s\n", "状态", "数量", "说明"
    states["R"]="Running"; states["S"]="Sleeping"; states["D"]="DiskSleep(IO)"; states["Z"]="Zombie"; states["T"]="Stopped"; states["I"]="Idle"
    for(s in count) printf "    %-10s %-10s %s\n", s, count[s], states[s]
    total=0; for(s in count) total+=count[s]; printf "    %-10s %-10s %s\n", "总计", total, ""
}'
echo ""

# 僵尸进程
ZOMBIE_COUNT=$(ps aux | awk '$8 ~ /^Z/' | wc -l)
[ "$ZOMBIE_COUNT" -gt 10 ] && { print_fail "僵尸进程过多 (${ZOMBIE_COUNT})"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || { [ "$ZOMBIE_COUNT" -gt 0 ] && { print_warn "僵尸进程: ${ZOMBIE_COUNT}"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }; } || print_ok "无僵尸进程"
[ "$ZOMBIE_COUNT" -gt 0 ] && ps aux | awk '$8 ~ /^Z/ {printf "    PID=%-8s CMD=%s\n", $2, $11}' | head -10

# D状态进程
D_COUNT=$(ps aux | awk '$8 ~ /^D/' | wc -l)
[ "$D_COUNT" -gt 0 ] && { print_fail "D状态进程: ${D_COUNT}个 (IO阻塞)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); ps aux | awk '$8 ~ /^D/ {print "    PID="$2" "$11}' | head -10; } || print_ok "无D状态进程"
echo ""

# 文件句柄TOP
print_info ">>> [PROC/2] FD TOP10 进程 ..."
printf "    %-8s %-8s %-10s %s\n" "PID" "FDS" "USER" "COMMAND"
for pid in $(ls /proc/ 2>/dev/null | grep -E '^[0-9]+$'); do
    [ -d "/proc/$pid/fd" ] && {
        fd_count=$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)
        cmd=$(cat "/proc/$pid/comm" 2>/dev/null)
        user=$(stat -c '%U' "/proc/$pid" 2>/dev/null)
        echo "${fd_count} ${pid} ${user} ${cmd}"
    }
done 2>/dev/null | sort -rn | head -10 | while read fds pid user cmd; do
    printf "    %-8s %-8s %-10s %s\n" "$pid" "$fds" "$user" "$cmd"
done
echo ""


# ======================== 系统启动 ========================
print_info ">>> [BOOT/1] 系统启动信息 ..."
echo "    运行时间: $(uptime -p 2>/dev/null || uptime)"
LAST_REBOOT=$(last reboot -1 2>/dev/null | head -1)
[ -n "$LAST_REBOOT" ] && echo "    上次重启: $LAST_REBOOT"

if command -v systemd-analyze &>/dev/null; then
    echo "    启动耗时: $(systemd-analyze 2>/dev/null | head -1)"
    echo "    启动最慢服务:"
    systemd-analyze blame 2>/dev/null | head -5 | while read l; do echo "    $l"; done
fi
echo ""

# 内核Panic/Oops (统一扫描，避免check-boot和check-kernel重复)
print_info ">>> [BOOT/2] 内核异常 (Panic/Oops/MCE) ..."
PANIC_COUNT=$(dmesg 2>/dev/null | grep -ci "panic")
OOPS_COUNT=$(dmesg 2>/dev/null | grep -ci "oops")
MCE_LOGS=$(dmesg 2>/dev/null | grep -i "machine check" | tail -3)
WARN_COUNT=$(dmesg 2>/dev/null | grep -ci "WARNING:")

[ "$PANIC_COUNT" -gt 0 ] && { print_fail "内核Panic: ${PANIC_COUNT}条"; dmesg 2>/dev/null | grep -i "panic" | tail -3 | while read l; do echo "    $l"; done; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无Panic"
[ "$OOPS_COUNT" -gt 0 ] && { print_fail "内核Oops: ${OOPS_COUNT}条"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无Oops"
[ -n "$MCE_LOGS" ] && { print_fail "Machine Check错误!"; echo "$MCE_LOGS" | while read l; do echo "    $l"; done; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无MCE"
[ "$WARN_COUNT" -gt 0 ] && print_warn "内核WARNING: ${WARN_COUNT}条" || print_ok "无WARNING"
echo ""

# 内核参数
print_info ">>> [BOOT/3] 内核启动参数 ..."
echo "    命令行: $(cat /proc/cmdline 2>/dev/null)"
PANIC_PARAM=$(cat /proc/sys/kernel/panic 2>/dev/null)
[ "$PANIC_PARAM" -eq 0 ] && print_warn "kernel.panic=0，建议设为5+自动重启" || print_ok "kernel.panic=${PANIC_PARAM}"
echo "    内核版本: $(uname -r)"
echo ""


# ======================== 日志扫描 ========================
print_info ">>> [LOG/1] dmesg 异常扫描 ..."
DMESG_CRIT=$(dmesg 2>/dev/null | grep -iE "killed process|Out of memory|BUG:|Call Trace|segfault|filesystem.*error|I/O error" | tail -10)
if [ -n "$DMESG_CRIT" ]; then
    CRIT_CNT=$(echo "$DMESG_CRIT" | wc -l)
    print_warn "dmesg异常: ${CRIT_CNT}条"
    echo "$DMESG_CRIT" | while read l; do echo "    $l"; done
else
    print_ok "dmesg无严重异常"
fi
echo ""

print_info ">>> [LOG/2] journalctl 错误 (最近1小时) ..."
if command -v journalctl &>/dev/null && journalctl --no-pager -n 1 &>/dev/null 2>&1; then
    JRNL_ERR=$(journalctl --no-pager -p err --since "1 hour ago" 2>/dev/null | tail -10)
    if [ -n "$JRNL_ERR" ]; then
        ERR_CNT=$(journalctl --no-pager -p err --since "1 hour ago" 2>/dev/null | wc -l)
        print_warn "journalctl ERROR: ${ERR_CNT}条"
        echo "$JRNL_ERR" | while read l; do echo "    $l"; done
    else
        print_ok "最近1小时无ERROR"
    fi
else
    print_info "journalctl不可用"
fi
echo ""

# /var/log 扫描
print_info ">>> [LOG/3] 系统日志文件扫描 ..."
[ -f /var/log/messages ] && { MSG_ERR=$(grep -ciE "error|fail|critical|emergency" /var/log/messages 2>/dev/null); [ "$MSG_ERR" -gt 0 ] && print_warn "/var/log/messages: ${MSG_ERR}条异常" || print_ok "/var/log/messages正常"; }
[ -f /var/log/syslog ] && { SYSLOG_ERR=$(grep -ciE "error|fail|critical" /var/log/syslog 2>/dev/null); [ "$SYSLOG_ERR" -gt 0 ] && print_warn "/var/log/syslog: ${SYSLOG_ERR}条异常" || print_ok "/var/log/syslog正常"; }

# 安全日志
for sf in /var/log/auth.log /var/log/secure; do
    [ -f "$sf" ] && {
        AUTH_FAIL=$(grep -ci "Failed password\|authentication failure\|Invalid user" "$sf" 2>/dev/null)
        [ "$AUTH_FAIL" -gt 50 ] && print_warn "$(basename $sf): ${AUTH_FAIL}次认证失败" || print_ok "$(basename $sf) 认证正常"
    }
done
echo ""

# 日志大小
print_info ">>> [LOG/4] 日志文件大小 ..."
for lf in /var/log/messages /var/log/syslog /var/log/kern.log /var/log/auth.log /var/log/secure; do
    [ -f "$lf" ] && { SIZE_MB=$(($(du -k "$lf" 2>/dev/null | awk '{print $1}') / 1024)); [ "$SIZE_MB" -gt 500 ] && print_warn "$lf: ${SIZE_MB}MB (过大)"; }
done

echo ""
echo "============================================================"
echo "                     进程与日志诊断结论"
echo "============================================================"
[ "$ISSUE_COUNT" -eq 0 ] && echo -e "  ${GREEN}[正常]${NC} 系统进程与日志状态健康"
echo "============================================================"
