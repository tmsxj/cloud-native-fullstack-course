#!/bin/bash
# ============================================================================
# 自动修复脚本 - fix-fd-limit.sh
# 功能: 安全调整文件描述符限制
# 用法: ./fix-fd-limit.sh [target] [--dry-run]
# 安全阈值: file-max 不超过 1048576, nofile 不超过 1048576
# 说明: 调整系统和进程级别的fd限制
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
TARGET="system"  # system | session | all

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        session) TARGET="session"; shift ;;
        all) TARGET="all"; shift ;;
        -h|--help)
            echo "用法: ./fix-fd-limit.sh [session|all] [--dry-run]"
            echo "  session  仅调整当前会话的ulimit"
            echo "  all      调整系统级+会话级"
            echo "  默认      仅调整系统级 (/etc/sysctl.conf + /etc/security/limits.conf)"
            exit 0 ;;
        *) shift ;;
    esac
done

echo "============================================================"
echo "          文件描述符限制调整工具"
echo "          执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# 安全上限
SAFE_FILE_MAX=1048576
SAFE_NOFILE=1048576

# ======================== 当前状态 ========================
print_info ">>> 当前FD限制状态 ..."

CURRENT_FILE_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null || echo "?")
CURRENT_FILE_NR=$(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}' || echo "?")
CURRENT_NOFILE_SOFT=$(ulimit -n 2>/dev/null || echo "?")
CURRENT_NOFILE_HARD=$(ulimit -Hn 2>/dev/null || echo "?")

echo "    系统级:"
echo "      fs.file-max = ${CURRENT_FILE_MAX}"
echo "      已分配FD:   ${CURRENT_FILE_NR}"
echo "    会话级:"
echo "      nofile soft = ${CURRENT_NOFILE_SOFT}"
echo "      nofile hard = ${CURRENT_NOFILE_HARD}"

NEED_FIX=0

# ======================== 系统级调整 ========================
if [ "$TARGET" = "system" ] || [ "$TARGET" = "all" ]; then
    echo ""
    print_info ">>> 调整系统级FD限制 ..."

    # 检查是否需要增大 file-max
    if [ "${CURRENT_FILE_MAX:-0}" -lt "$SAFE_FILE_MAX" ] 2>/dev/null; then
        print_warn "file-max 偏低 (${CURRENT_FILE_MAX}), 建议调整为 ${SAFE_FILE_MAX}"

        if [ "$DRY_RUN" = false ]; then
            # 检查是否已存在配置
            if grep -q "^fs.file-max" /etc/sysctl.conf 2>/dev/null; then
                # 更新已有配置
                if sed -i "s/^fs.file-max.*/fs.file-max = ${SAFE_FILE_MAX}/" /etc/sysctl.conf 2>/dev/null; then
                    print_ok "已更新 /etc/sysctl.conf: fs.file-max = ${SAFE_FILE_MAX}"
                else
                    print_info "需要root权限修改 /etc/sysctl.conf"
                    echo "fs.file-max = ${SAFE_FILE_MAX}" | sudo tee -a /etc/sysctl.conf 2>/dev/null && \
                        print_ok "已追加到 /etc/sysctl.conf" || \
                        print_warn "无法写入 /etc/sysctl.conf (需要root)"
                fi
            else
                echo "fs.file-max = ${SAFE_FILE_MAX}" | sudo tee -a /etc/sysctl.conf 2>/dev/null && \
                    print_ok "已添加 fs.file-max = ${SAFE_FILE_MAX} 到 /etc/sysctl.conf" || \
                    print_warn "无法写入 /etc/sysctl.conf"
            fi

            # 立即生效
            sysctl -w fs.file-max="$SAFE_FILE_MAX" 2>/dev/null && \
                print_ok "sysctl已生效: fs.file-max = ${SAFE_FILE_MAX}" || \
                print_info "需要root权限执行sysctl"

            NEED_FIX=1
        else
            print_info "  [DRY-RUN] 会将 file-max 从 ${CURRENT_FILE_MAX} 调整为 ${SAFE_FILE_MAX}"
        fi
    else
        print_ok "file-max 已足够 (${CURRENT_FILE_MAX})"
    fi

    # 检查 nr_open (单进程上限)
    CURRENT_NR_OPEN=$(cat /proc/sys/fs/nr_open 2>/dev/null || echo "?")
    if [ "${CURRENT_NR_OPEN:-0}" -lt 1048576 ] 2>/dev/null; then
        print_warn "nr_open 偏低 (${CURRENT_NR_OPEN}), 建议调整为 1048576"
        if [ "$DRY_RUN" = false ]; then
            sysctl -w fs.nr_open=1048576 2>/dev/null && \
                print_ok "nr_open已生效: 1048576" || \
                print_info "需要root权限"
        else
            print_info "  [DRY-RUN] 会将 nr_open 调整为 1048576"
        fi
    fi

    # 检查 inotify (常见瓶颈)
    CURRENT_INOTIFY=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo "?")
    if [ "${CURRENT_INOTIFY:-0}" -lt 524288 ] 2>/dev/null; then
        print_warn "inotify watches 偏低 (${CURRENT_INOTIFY}), 建议调整为 524288"
        if [ "$DRY_RUN" = false ]; then
            sysctl -w fs.inotify.max_user_watches=524288 2>/dev/null && \
                print_ok "inotify已生效: 524288" || \
                print_info "需要root权限"
        else
            print_info "  [DRY-RUN] 会将 inotify watches 调整为 524288"
        fi
    fi
fi

# ======================== 会话级调整 ========================
if [ "$TARGET" = "session" ] || [ "$TARGET" = "all" ]; then
    echo ""
    print_info ">>> 调整会话级FD限制 (/etc/security/limits.conf) ..."

    if [ "${CURRENT_NOFILE_HARD:-0}" -lt "$SAFE_NOFILE" ] 2>/dev/null || [ "${CURRENT_NOFILE_SOFT:-0}" -lt 65535 ] 2>/dev/null; then
        print_warn "nofile限制偏低 (soft=${CURRENT_NOFILE_SOFT}, hard=${CURRENT_NOFILE_HARD})"

        if [ "$DRY_RUN" = false ]; then
            # 添加 limits.conf 条目 (避免重复)
            LIMITS_FILE="/etc/security/limits.conf"
            if ! grep -q "^*.*nofile.*${SAFE_NOFILE}" "$LIMITS_FILE" 2>/dev/null; then
                cat >> "$LIMITS_FILE" << 'LIMITSEOF'
# Added by fix-fd-limit.sh - safe defaults for production
* soft nofile 65535
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
LIMITSEOF
                print_ok "已更新 limits.conf"
            else
                print_info "limits.conf 中已存在nofile配置"
            fi

            # 当前会话立即生效
            ulimit -n 65535 2>/dev/null && print_ok "当前会话nofile已设置为65535" || \
                print_info "当前会话无法调整ulimit (需要重新登录)"
        else
            print_info "  [DRY-RUN] 会更新 /etc/security/limits.conf, nofile=65535/1048576"
        fi

        NEED_FIX=1
    else
        print_ok "nofile限制已足够"
    fi
fi

echo ""
echo "============================================================"
echo "                     调整结果"
echo "============================================================"

if [ "$NEED_FIX" -eq 0 ]; then
    echo -e "  ${GREEN}[OK]${NC} FD限制已足够, 无需调整"
else
    echo -e "  ${GREEN}[完成]${NC} FD限制已调整"
    echo ""
    echo "  验证方法:"
    echo "    sysctl fs.file-max"
    echo "    ulimit -n"
    echo ""
    echo "  持久化配置:"
    echo "    /etc/sysctl.conf     (重启后生效)"
    echo "    /etc/security/limits.conf  (重新登录后生效)"
fi

echo "============================================================"
