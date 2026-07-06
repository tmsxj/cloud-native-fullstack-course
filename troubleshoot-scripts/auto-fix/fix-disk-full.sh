#!/bin/bash
# ============================================================================
# 自动修复脚本 - fix-disk-full.sh
# 功能: 安全清理磁盘空间
# 用法: ./fix-disk-full.sh [--dry-run]
# 安全阈值: 仅在使用率 > 85% 时执行, 最多释放 30% 空间
# 说明: 自动清理apt缓存、旧内核、journal日志、临时文件
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
    print_info "*** 试运行模式 (不会实际删除文件) ***"
fi

echo "============================================================"
echo "          磁盘空间安全清理工具"
echo "          执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ======================== 安全检查 ========================
ROOT_USAGE=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
print_info "当前根分区使用率: ${ROOT_USAGE}%"

if [ "${ROOT_USAGE:-0}" -lt 85 ] 2>/dev/null; then
    print_ok "磁盘使用率在安全范围内 (${ROOT_USAGE}%), 无需清理"
    exit 0
fi

# 记录清理前空间
BEFORE_AVAIL=$(df / | awk 'NR==2 {print $4}')

TOTAL_FREED=0

# ======================== 1. 清理包管理器缓存 ========================
print_info ">>> [1/5] 清理包管理器缓存 ..."

# APT (Debian/Ubuntu)
if command -v apt-get &>/dev/null; then
    CACHE_SIZE=$(du -sm /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
    if [ "${CACHE_SIZE:-0}" -gt 50 ]; then
        echo "    APT缓存大小: ${CACHE_SIZE}MB"
        if [ "$DRY_RUN" = false ]; then
            apt-get clean 2>/dev/null && print_ok "已清理APT缓存" || print_warn "APT清理失败"
        else
            print_info "  [DRY-RUN] 会执行: apt-get clean"
        fi
        TOTAL_FREED=$((TOTAL_FREED + CACHE_SIZE))
    fi
fi

# YUM/DNF (RHEL/CentOS/Fedora)
if command -v yum &>/dev/null; then
    CACHE_SIZE=$(du -sm /var/cache/yum 2>/dev/null | awk '{print $1}')
    if [ "${CACHE_SIZE:-0}" -gt 50 ]; then
        echo "    YUM缓存大小: ${CACHE_SIZE}MB"
        if [ "$DRY_RUN" = false ]; then
            yum clean all 2>/dev/null && print_ok "已清理YUM缓存" || print_warn "YUM清理失败"
        else
            print_info "  [DRY-RUN] 会执行: yum clean all"
        fi
        TOTAL_FREED=$((TOTAL_FREED + CACHE_SIZE))
    fi
fi

echo ""

# ======================== 2. 清理旧内核 ========================
print_info ">>> [2/5] 清理旧内核 ..."

KERNEL_COUNT=$(dpkg --list 2>/dev/null | grep -E "linux-image-[0-9]" | grep -v "$(uname -r)" | wc -l)
if [ "${KERNEL_COUNT:-0}" -gt 2 ]; then
    echo "    可移除的旧内核: ${KERNEL_COUNT} 个"
    KERNEL_SIZE=$(dpkg --list 2>/dev/null | grep -E "linux-image-[0-9]" | grep -v "$(uname -r)" | awk '{sum+=$1} END {print sum}')
    if [ "$DRY_RUN" = false ]; then
        if command -v apt-get &>/dev/null; then
            apt-get autoremove --purge -y 2>/dev/null && \
                print_ok "已清理旧内核 (autoremove)" || \
                print_warn "旧内核自动清理失败, 可能需要手动确认"
        fi
    else
        print_info "  [DRY-RUN] 会执行: apt-get autoremove --purge -y"
    fi
else
    print_info "旧内核数量合理 (${KERNEL_COUNT}), 无需清理"
fi

echo ""

# ======================== 3. 清理journal日志 ========================
print_info ">>> [3/5] 清理journal日志 ..."

if command -v journalctl &>/dev/null; then
    if journalctl --no-pager -n 1 &>/dev/null 2>&1; then
        JRNL_SIZE=$(journalctl --disk-usage 2>/dev/null | awk '{print $NF}')
        echo "    Journal当前大小: ${JRNL_SIZE:-?}"

        if [ "$DRY_RUN" = false ]; then
            # 保留最近7天的日志
            journalctl --vacuum-time=7d 2>/dev/null && \
                print_ok "已清理7天前的journal日志" || \
                print_info "journal清理需要root权限"
        else
            print_info "  [DRY-RUN] 会执行: journalctl --vacuum-time=7d"
        fi
    fi
fi

echo ""

# ======================== 4. 清理临时文件 ========================
print_info ">>> [4/5] 清理临时文件 ..."

# 清理 /tmp 中超过7天的文件
TMP_OLD=$(find /tmp -type f -atime +7 2>/dev/null | wc -l)
if [ "${TMP_OLD:-0}" -gt 100 ]; then
    echo "    /tmp中超过7天的文件: ${TMP_OLD} 个"
    if [ "$DRY_RUN" = false ]; then
        find /tmp -type f -atime +7 -delete 2>/dev/null
        print_ok "已清理/tmp中的旧文件"
    else
        print_info "  [DRY-RUN] 会清理 ${TMP_OLD} 个临时文件"
    fi
else
    print_info "/tmp中旧文件数量正常"
fi

# 清理 /var/tmp 中超过30天的文件
VAR_TMP_OLD=$(find /var/tmp -type f -atime +30 2>/dev/null | wc -l)
if [ "${VAR_TMP_OLD:-0}" -gt 50 ]; then
    echo "    /var/tmp中超过30天的文件: ${VAR_TMP_OLD} 个"
    if [ "$DRY_RUN" = false ]; then
        find /var/tmp -type f -atime +30 -delete 2>/dev/null
        print_ok "已清理/var/tmp中的旧文件"
    else
        print_info "  [DRY-RUN] 会清理 ${VAR_TMP_OLD} 个文件"
    fi
fi

echo ""

# ======================== 5. 清理已删除但占用的文件句柄 ========================
print_info ">>> [5/5] 提示已删除但仍占用的文件 (不会自动处理) ..."

DELETED_INFO=$(lsof +L1 2>/dev/null | awk 'NR>1 {
    pid=$2; comm=$1; size=$7
    if (size+0 > 1048576) printf "    PID=%-8s COMM=%-15s SIZE=%.0fMB\n", pid, comm, size/1024/1024
}')
if [ -n "$DELETED_INFO" ]; then
    print_warn "以下进程持有已删除的大文件句柄 (需手动重启进程释放):"
    echo "$DELETED_INFO"
    echo ""
    print_info "建议: 找到对应服务执行 systemctl restart <service>"
fi

echo ""

# ======================== 结论 ========================
AFTER_AVAIL=$(df / | awk 'NR==2 {print $4}')
AFTER_USAGE=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')

echo "============================================================"
echo "                     清理结果"
echo "============================================================"

# 计算释放空间 (简单对比)
BEFORE_MB=$(echo "$BEFORE_AVAIL" | sed 's/G/*1024/;s/M//' | bc 2>/dev/null || echo 0)
AFTER_MB=$(echo "$AFTER_AVAIL" | sed 's/G/*1024/;s/M//' | bc 2>/dev/null || echo 0)

echo "  清理前可用: ${BEFORE_AVAIL}"
echo "  清理后可用: ${AFTER_AVAIL}"
echo "  当前使用率: ${AFTER_USAGE}%"

if [ "$AFTER_USAGE" -lt 85 ] 2>/dev/null; then
    echo -e "  ${GREEN}[完成]${NC} 磁盘使用率已降至安全范围"
else
    echo -e "  ${YELLOW}[注意]${NC} 使用率仍然偏高, 请检查大文件:"
    echo "  find / -xdev -type f -size +500M -exec ls -lh {} \\;"
fi

echo "============================================================"
