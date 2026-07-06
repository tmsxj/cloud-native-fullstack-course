#!/bin/bash
# ============================================================================
# 模块33-内核诊断 (合并版)
# 脚本名称: check-kernel-core.sh
# 功能: 内核健康 + systemd服务管理
# 用法: ./check-kernel-core.sh
# 合并自: check-kernel-health.sh + check-systemd.sh
# ============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

echo "============================================================"
echo "    内核与服务健康 — 内核状态 | systemd"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

ISSUE_COUNT=0
HEALTH_SCORE=100

# ======================== 内核版本 ========================
print_info ">>> [KERN/1] 内核版本 ..."
KERNEL_VER=$(uname -r); KERNEL_ARCH=$(uname -m)
echo "    内核: ${KERNEL_VER} (${KERNEL_ARCH})"

K_MAJ=$(echo "$KERNEL_VER" | cut -d. -f1); K_MIN=$(echo "$KERNEL_VER" | cut -d. -f2)
[ "$K_MAJ" -lt 4 ] && { print_fail "内核过旧 (${KERNEL_VER})"; HEALTH_SCORE=$((HEALTH_SCORE-10)); } || \
{ [ "$K_MAJ" -eq 4 ] && [ "$K_MIN" -lt 14 ] && print_warn "内核较旧 (${KERNEL_VER})"; } || print_ok "内核版本合理 (${KERNEL_VER})"
echo "$KERNEL_VER" | grep -qi "rt" && print_info "实时(RT)内核"
echo ""

# ======================== 内核异常 ========================
print_info ">>> [KERN/2] 内核异常事件 ..."
PANIC_COUNT=$(dmesg 2>/dev/null | grep -ci "panic")
OOPS_COUNT=$(dmesg 2>/dev/null | grep -ci "oops")
WARN_COUNT=$(dmesg 2>/dev/null | grep -ci "WARNING:")
MCE_LOGS=$(dmesg 2>/dev/null | grep -i "machine check" | tail -3)
PCI_ERR=$(dmesg 2>/dev/null | grep -iE "aer|pcie.*error" | tail -3)
ECC_ERR=$(dmesg 2>/dev/null | grep -iE "ecc|corrected memory" | tail -3)

[ "$PANIC_COUNT" -gt 0 ] && { print_fail "内核Panic: ${PANIC_COUNT}条"; HEALTH_SCORE=$((HEALTH_SCORE-30)); ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无Panic"
[ "$OOPS_COUNT" -gt 0 ] && { print_fail "内核Oops: ${OOPS_COUNT}条"; HEALTH_SCORE=$((HEALTH_SCORE-20)); ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无Oops"
[ -n "$MCE_LOGS" ] && { print_fail "Machine Check错误!"; echo "$MCE_LOGS" | while read l; do echo "    $l"; done; HEALTH_SCORE=$((HEALTH_SCORE-25)); ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无MCE"
[ "$WARN_COUNT" -gt 0 ] && { print_warn "内核WARNING: ${WARN_COUNT}条"; HEALTH_SCORE=$((HEALTH_SCORE-5)); }
[ -n "$PCI_ERR" ] && print_warn "PCIe错误: $(echo $PCI_ERR | head -1)"
[ -n "$ECC_ERR" ] && print_warn "ECC错误: $(echo $ECC_ERR | head -1)"

# panic_on_oops
PANIC_ON_OOPS=$(cat /proc/sys/kernel/panic_on_oops 2>/dev/null)
[ "$PANIC_ON_OOPS" -eq 1 ] && print_info "kernel.panic_on_oops=1 (Oops时触发重启)"
# ======================== 内核 Tainted ========================
TAINTED=$(cat /proc/sys/kernel/tainted 2>/dev/null)
if [ -n "$TAINTED" ] && [ "$TAINTED" != "0" ]; then
    print_fail "内核被污染 (Tainted=0x$(printf '%x' $TAINTED))"
    # 解析常见位
    [ $((TAINTED & 1)) -ne 0 ] && echo "    - G: 加载了 GPL 以外许可证的模块"
    [ $((TAINTED & 8)) -ne 0 ] && echo "    - U: 用户空间触发 Oops/Warning"
    [ $((TAINTED & 256)) -ne 0 ] && echo "    - O: 加载了外部(out-of-tree)模块"
    [ $((TAINTED & 512)) -ne 0 ] && echo "    - E: 加载了不受支持的模块"
    [ $((TAINTED & 4096)) -ne 0 ] && echo "    - D: 内核 Oops 后仍继续运行"
    HEALTH_SCORE=$((HEALTH_SCORE-10))
    ISSUE_COUNT=$((ISSUE_COUNT+1))
elif [ "$TAINTED" = "0" ]; then
    print_ok "内核未被污染 (Tainted=0)"
fi
echo ""

# ======================== 内核模块 ========================
print_info ">>> [KERN/3] 内核模块 ..."
MOD_COUNT=$(lsmod 2>/dev/null | wc -l)
echo "    已加载模块: ${MOD_COUNT}"
[ "$MOD_COUNT" -gt 0 ] && {
    echo "    关键模块:"
    for mod in ext4 xfs nfs bonding bridge ip_tables netfilter; do
        lsmod 2>/dev/null | grep -q "^${mod}" && { SIZE=$(lsmod | grep "^${mod}" | awk '{print $2}'); echo "    ${GREEN}[+]${NC} ${mod} (${SIZE})"; }
    done
}
echo ""

# ======================== 内核参数 ========================
print_info ">>> [KERN/4] 关键内核参数 ..."
for p in \
    "kernel.panic:kernel/panic:Panic后重启秒数" \
    "vm.swappiness:vm/swappiness:Swap倾向" \
    "vm.overcommit_memory:vm/overcommit_memory:内存过度提交" \
    "vm.dirty_ratio:vm/dirty_ratio:脏页同步阈值%" \
    "vm.dirty_background_ratio:vm/dirty_background_ratio:后台回写阈值%" \
    "net.core.somaxconn:net/core/somaxconn:监听队列" \
    "fs.file-max:fs/file-max:最大FD" \
    "fs.nr_open:fs/nr_open:单进程最大FD"; do
    LABEL=$(echo "$p" | cut -d: -f1); PATH_=$(echo "$p" | cut -d: -f2); DESC=$(echo "$p" | cut -d: -f3)
    VAL=$(cat "/proc/sys/$PATH_" 2>/dev/null)
    [ -n "$VAL" ] && printf "    %-35s = %-10s # %s\n" "$LABEL" "$VAL" "$DESC"
done
echo ""

# 内核命令行
echo "    启动参数: $(cat /proc/cmdline 2>/dev/null | head -c 120)..."
echo ""


# ======================== systemd服务 ========================
if ! pidof systemd &>/dev/null && [ ! -d /run/systemd/system ]; then
    print_info "非systemd系统，跳过服务检查"
else
    print_info ">>> [SVC/1] 失败服务 ..."
    FAILED=$(systemctl list-units --state=failed --no-legend 2>/dev/null)
    if [ -n "$FAILED" ]; then
        FCNT=$(echo "$FAILED" | wc -l)
        print_fail "失败服务: ${FCNT}个"
        echo "$FAILED" | while read l; do echo "    $l"; done
        ISSUE_COUNT=$((ISSUE_COUNT+1))
    else
        print_ok "无失败服务"
    fi
    echo ""

    # restart-loop
    print_info ">>> [SVC/2] 重启循环检测 ..."
    LOOP_FOUND=""
    for svc in $(systemctl list-units --type=service --no-legend 2>/dev/null | awk '{print $1}'); do
        RST=$(systemctl show "$svc" -p NRestarts 2>/dev/null | cut -d= -f2)
        [ -n "$RST" ] && [ "$RST" -gt 10 ] 2>/dev/null && { STATE=$(systemctl show "$svc" -p ActiveState 2>/dev/null | cut -d= -f2); LOOP_FOUND="$LOOP_FOUND  $svc (重启${RST}次, ${STATE})\n"; }
    done
    [ -n "$LOOP_FOUND" ] && { print_fail "重启循环:"; echo -e "$LOOP_FOUND"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无重启循环"

    # activating卡住
    ACTIVATING=$(systemctl list-units --state=activating --no-legend 2>/dev/null)
    [ -n "$ACTIVATING" ] && print_warn "Activating卡住: $(echo $ACTIVATING | wc -l)个"
    echo ""

    # 关键服务
    print_info ">>> [SVC/3] 关键服务状态 ..."
    KEY_SVCS="sshd:SSH cron:定时任务 rsyslog:系统日志 systemd-journald:Journal firewalld:防火墙 chronyd:时间同步 containerd:容器 kubelet:K8s"
    OK_SVC=0; WARN_SVC=0
    for se in $KEY_SVCS; do
        SVC=$(echo "$se" | cut -d: -f1); DESC=$(echo "$se" | cut -d: -f2)
        STATE=$(systemctl is-active "$SVC" 2>/dev/null)
        if [ "$STATE" = "active" ]; then
            echo -e "    ${GREEN}[+]${NC} ${SVC} (${DESC})"; OK_SVC=$((OK_SVC+1))
        elif [ "$STATE" = "unknown" ]; then
            :
        else
            echo -e "    ${RED}[${STATE}]${NC} ${SVC} (${DESC})"; WARN_SVC=$((WARN_SVC+1))
        fi
    done
    [ "$WARN_SVC" -eq 0 ] && print_ok "关键服务正常" || print_warn "${WARN_SVC}个服务异常"
    echo ""

    # Journal
    print_info ">>> [SVC/4] Journal日志存储 ..."
    if [ -d /var/log/journal ]; then
        JRNL_MB=$(du -sm /var/log/journal 2>/dev/null | awk '{print $1}')
        echo "    Journal: ${JRNL_MB}MB (持久化)"
        [ "$JRNL_MB" -gt 1024 ] && print_warn "Journal过大 (${JRNL_MB}MB)"
    else
        print_info "Journal: 运行时存储 (/run)"
    fi
    echo ""
fi


# ======================== 结论 ========================
echo "============================================================"
echo "                   内核健康评分"
echo "============================================================"
if [ "$HEALTH_SCORE" -ge 90 ]; then STATUS="${GREEN}健康${NC}"
elif [ "$HEALTH_SCORE" -ge 70 ]; then STATUS="${YELLOW}亚健康${NC}"
else STATUS="${RED}不健康${NC}"; fi
echo -e "  评分: ${HEALTH_SCORE}/100 ($STATUS)"
[ "$HEALTH_SCORE" -lt 70 ] && {
    echo "  建议: 1.收集dmesg日志 2.分析Panic/Oops调用栈 3.检查硬件"
}
echo "============================================================"
