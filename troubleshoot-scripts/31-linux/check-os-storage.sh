#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本 (合并版)
# 脚本名称: check-os-storage.sh
# 功能: 磁盘IO + 文件系统综合诊断
# 用法: ./check-os-storage.sh [device]
# 合并自: check-diskio.sh + check-filesystem.sh
# ============================================================================

# ======================== 颜色输出函数 ========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

TARGET_DEVICE=""
[ -n "$1" ] && { TARGET_DEVICE=$1; print_info "指定设备: ${TARGET_DEVICE}"; }

echo "============================================================"
echo "    存储综合诊断 — 磁盘IO | 文件系统"
echo "    检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

ISSUE_COUNT=0

# ======================== 磁盘空间 ========================
print_info ">>> [1/4] 磁盘空间与inode ..."
echo "    分区使用情况:"
printf "    %-20s %-8s %-8s %-8s %-6s %s\n" "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted"
df -h | awk 'NR>1 && /^\/dev/ {printf "    %-20s %-8s %-8s %-8s %-6s %s\n", $1, $2, $3, $4, $5, $6}'
echo ""

# inode
echo "    inode使用情况:"
printf "    %-20s %-10s %-10s %-8s %s\n" "Filesystem" "Inodes" "IUsed" "IUse%" "Mounted"
df -i | awk 'NR==1 || /^\/dev/ || /^tmpfs/ {printf "    %-20s %-10s %-10s %-8s %s\n", $1, $2, $3, $5, $6}'
echo ""

# 检查阈值
DISK_WARN=$(df -h | awk 'NR>1 && /^\/dev/ {usage=$5; sub(/%/,"",usage); if(usage+0>=80 && usage+0<90) print $6" ("usage"%)"}')
DISK_CRIT=$(df -h | awk 'NR>1 && /^\/dev/ {usage=$5; sub(/%/,"",usage); if(usage+0>=90) print $6" ("usage"%)"}')
INODE_HIGH=$(df -i | awk 'NR>1 && /^\/dev/ {usage=$5; sub(/%/,"",usage); if(usage+0>80) print $6" (inode:"usage"%)"}')

[ -n "$DISK_CRIT" ] && { print_fail "磁盘使用率>90%: $DISK_CRIT"; ISSUE_COUNT=$((ISSUE_COUNT+1)); }
[ -n "$DISK_WARN" ] && { print_warn "磁盘使用率>80%: $DISK_WARN"; }
[ -z "$DISK_CRIT" ] && [ -z "$DISK_WARN" ] && print_ok "磁盘空间正常"
[ -n "$INODE_HIGH" ] && { print_fail "inode使用率>80%: $INODE_HIGH"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "inode正常"
echo ""


# ======================== IO性能 ========================
print_info ">>> [2/4] 磁盘IO性能 (采样3秒) ..."
if ! command -v iostat &>/dev/null; then
    print_warn "iostat不可用，安装: yum/apt install sysstat"
else
    IO_DATA=$(iostat -x 1 3 2>/dev/null)
    if [ -n "$TARGET_DEVICE" ]; then
        IO_LINE=$(echo "$IO_DATA" | grep -E "^${TARGET_DEVICE}" | tail -1)
        [ -n "$IO_LINE" ] && {
            AWAIT=$(echo "$IO_LINE" | awk '{print $10}'); UTIL=$(echo "$IO_LINE" | awk '{print $16}')
            R_S=$(echo "$IO_LINE" | awk '{print $4}'); W_S=$(echo "$IO_LINE" | awk '{print $5}')
            echo "    ${TARGET_DEVICE}: await=${AWAIT}ms util=${UTIL}% r/s=${R_S} w/s=${W_S}"
            [ "${UTIL%.*}" -gt 90 ] && { print_fail "IO利用率过高 (${UTIL}%)"; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || { [ "${UTIL%.*}" -gt 70 ] && print_warn "IO利用率偏高 (${UTIL}%)"; } || print_ok "IO利用率正常 (${UTIL}%)"
            [ "${AWAIT%.*}" -gt 50 ] && { print_fail "IO等待过长 (${AWAIT}ms)"; } || { [ "${AWAIT%.*}" -gt 20 ] && print_warn "IO等待偏高 (${AWAIT}ms)"; } || print_ok "IO等待正常 (${AWAIT}ms)"
        } || print_warn "未找到设备 ${TARGET_DEVICE}"
    else
        printf "    %-10s %-8s %-8s %-8s %-8s\n" "Device" "await" "%util" "r/s" "w/s"
        echo "$IO_DATA" | grep -E "^sd|^vd|^nvme|^xvd|^dm-" | awk '{printf "    %-10s %-8s %-8s %-8s %-8s\n", $1, $10"ms", $16"%", $4, $5}'
        HIGH_AWAIT=$(echo "$IO_DATA" | grep -E "^sd|^vd|^nvme|^xvd|^dm-" | awk '$10+0>50{print $1" "$10"ms"}')
        HIGH_UTIL=$(echo "$IO_DATA" | grep -E "^sd|^vd|^nvme|^xvd|^dm-" | awk '$16+0>90{print $1" "$16"%"}')
        [ -n "$HIGH_AWAIT" ] && print_fail "IO等待>50ms: $HIGH_AWAIT"
        [ -n "$HIGH_UTIL" ] && print_fail "IO利用率>90%: $HIGH_UTIL"
        [ -z "$HIGH_AWAIT" ] && [ -z "$HIGH_UTIL" ] && print_ok "所有设备IO正常"
    fi
fi
echo ""

# IO调度器
print_info ">>>  IO调度器 ..."
for dp in /sys/block/sd* /sys/block/vd* /sys/block/nvme* /sys/block/xvd*; do
    [ -d "$dp" ] && [ -f "$dp/queue/scheduler" ] && {
        DEV=$(basename "$dp"); SCHED=$(grep -o '\[.*\]' "$dp/queue/scheduler" | tr -d '[]')
        echo "    ${DEV}: ${SCHED}"
    }
done
echo ""


# ======================== 挂载与文件系统 ========================
print_info ">>> [3/4] 挂载状态与文件系统健康 ..."

# fstab vs 实际挂载
if [ -f /etc/fstab ]; then
    FSTAB_MOUNTS=$(grep -E "^/dev|^UUID" /etc/fstab | grep -v "^#" | awk '{print $2}')
    ACTUAL_MOUNTS=$(mount | awk '{print $3}')
    UNMOUNTED=""
    while IFS= read -r mp; do
        echo "$ACTUAL_MOUNTS" | grep -qxF "$mp" || { [ "$mp" != "swap" ] && [ "$mp" != "none" ] && UNMOUNTED="$UNMOUNTED $mp"; }
    done <<< "$FSTAB_MOUNTS"
    [ -n "$UNMOUNTED" ] && print_warn "未挂载:${UNMOUNTED}" || print_ok "所有fstab配置已挂载"
fi

# 只读挂载
READONLY=$(mount | grep "([a-z]*ro[,\)]" | grep -v "proc\|sysfs\|devpts")
[ -n "$READONLY" ] && print_info "只读挂载: $READONLY"

# 文件系统错误
FS_ERR=$(dmesg 2>/dev/null | grep -iE "ext[2-4] error|xfs error|btrfs error|I/O error.*dev" | tail -5)
[ -n "$FS_ERR" ] && { print_fail "文件系统I/O错误!"; echo "$FS_ERR" | while read l; do echo "    $l"; done; ISSUE_COUNT=$((ISSUE_COUNT+1)); } || print_ok "无文件系统I/O错误"
echo ""

# NFS/CIFS
NFS_MOUNTS=$(mount | grep -E "type nfs|type nfs4" 2>/dev/null)
[ -n "$NFS_MOUNTS" ] && echo "    NFS挂载: $(echo $NFS_MOUNTS | wc -l)个" || print_info "无NFS挂载"
echo ""


# ======================== 文件扫描 ========================
print_info ">>> [4/4] 大文件与已删除文件扫描 ..."

for tmpd in /tmp /var/tmp; do
    [ -d "$tmpd" ] && {
        BIG=$(find "$tmpd" -xdev -type f -size +100M -exec ls -lh {} \; 2>/dev/null | head -5)
        [ -n "$BIG" ] && print_warn "${tmpd} >100MB文件:" && echo "$BIG" | while read l; do echo "    $l"; done
    }
done

# deleted but held
DELETED=$(lsof +L1 2>/dev/null | head -10)
[ -n "$DELETED" ] && print_warn "已删除但仍占用的文件:" && echo "$DELETED" | while read l; do echo "    $l"; done

# 大日志
for logd in /var/log; do
    [ -d "$logd" ] && {
        BIG_LOG=$(find "$logd" -xdev -type f -size +500M -exec ls -lh {} \; 2>/dev/null | head -5)
        [ -n "$BIG_LOG" ] && print_warn "大日志文件(>500MB):" && echo "$BIG_LOG" | while read l; do echo "    $l"; done
    }
done

# ======================== SMART 磁盘健康 ========================
if command -v smartctl &>/dev/null; then
    print_info ">>> [DISK/5] SMART 磁盘健康 ..."
    SMART_ISSUE=0
    for dev in $(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); do
        SMART_OUT=$(smartctl -H /dev/$dev 2>/dev/null)
        if echo "$SMART_OUT" | grep -q "PASSED"; then
            echo "    ${GREEN}[+]${NC} /dev/$dev: SMART PASSED"
        elif echo "$SMART_OUT" | grep -q "FAILED"; then
            print_fail "/dev/$dev: SMART FAILED — 磁盘即将故障！"
            SMART_ISSUE=$((SMART_ISSUE+1)); ISSUE_COUNT=$((ISSUE_COUNT+1))
        fi
        # Reallocated / Pending / UDMA CRC
        for attr in Reallocated_Sector_Ct Current_Pending_Sector UDMA_CRC_Error_Count; do
            VAL=$(smartctl -A /dev/$dev 2>/dev/null | awk -v a="$attr" '$0~a{print $NF}' | head -1)
            [ -n "$VAL" ] && [ "$VAL" != "0" ] && { print_warn "/dev/$dev: $attr = $VAL"; SMART_ISSUE=$((SMART_ISSUE+1)); }
        done
    done
    [ "$SMART_ISSUE" -eq 0 ] && print_ok "所有磁盘 SMART 无异常"
    echo ""
elif lsblk &>/dev/null; then
    # 虚拟机/云主机通常不支持 smartctl，改用简单检查
    echo "    SMART: 本机不支持或未安装 smartctl (虚拟机环境跳过)"
    echo ""
fi

echo ""
echo "============================================================"
echo "                     存储诊断结论"
echo "============================================================"
[ "$ISSUE_COUNT" -eq 0 ] && echo -e "  ${GREEN}[正常]${NC} 磁盘与文件系统状态健康"
echo "============================================================"
