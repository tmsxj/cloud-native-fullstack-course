#!/bin/bash
# ============================================================================
# 模块31-Linux系统故障排查脚本
# 脚本名称: check-security.sh
# 功能: 安全审计诊断
# 用法: ./check-security.sh
# 说明: 检查异常端口、SUID文件、无属主文件、可疑进程、可疑网络连接
# ============================================================================

# ======================== 颜色输出函数定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }

echo "============================================================"
echo "          安全审计诊断报告 (只读, 不做任何修改)"
echo "          检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

SECURITY_RISK=0

# ======================== 1. 监听端口审计 ========================
print_info ">>> [1/7] 监听端口审计 ..."

# 获取所有监听端口
if command -v ss &>/dev/null; then
    LISTEN_PORTS=$(ss -tlnp 2>/dev/null)
elif command -v netstat &>/dev/null; then
    LISTEN_PORTS=$(netstat -tlnp 2>/dev/null)
else
    LISTEN_PORTS=""
fi

echo "    当前监听端口:"
echo "    ------------------------------------------------------------------"
if [ -n "$LISTEN_PORTS" ]; then
    echo "$LISTEN_PORTS" | head -30 | while read line; do
        echo "    $line"
    done
    PORT_COUNT=$(echo "$LISTEN_PORTS" | grep -c "LISTEN" 2>/dev/null)
    echo "    ------------------------------------------------------------------"
    echo "    共 ${PORT_COUNT:-0} 个监听端口"

    # 检查非标准端口 (排除常见的 HTTP/HTTPS/SSH/数据库/监控)
    KNOWN_PORTS="80|443|22|3306|5432|6379|27017|9090|9093|9100|3000|8080|8443|6443|2379|2380|10250|10251|10252|10255|10256|53"
    UNKNOWN_PORTS=$(echo "$LISTEN_PORTS" | awk -v known="$KNOWN_PORTS" '
        /LISTEN/ {
            split($4, a, ":")
            port = a[length(a)]
            if (port !~ /^('"$KNOWN_PORTS"')$/ && port+0 > 0 && port+0 < 65535) {
                print
            }
        }
    ')
    if [ -n "$UNKNOWN_PORTS" ]; then
        UNK_COUNT=$(echo "$UNKNOWN_PORTS" | wc -l)
        print_warn "检测到 ${UNK_COUNT} 个非标准端口正在监听:"
        echo "$UNKNOWN_PORTS" | while read line; do
            echo "      $line"
        done
        SECURITY_RISK=$((SECURITY_RISK + UNK_COUNT))
    fi

    # 检查0.0.0.0监听的高危端口
    HIGH_RISK_PORTS=$(echo "$LISTEN_PORTS" | awk '
        /0\.0\.0\.0|:::/ {
            split($4, a, ":")
            port = a[length(a)]
            if (port+0 == 6379 || port+0 == 27017 || port+0 == 11211) print
        }
    ')
    if [ -n "$HIGH_RISK_PORTS" ]; then
        print_fail "检测到高危端口对外监听(Redis/MongoDB/Memcache无密码):"
        echo "$HIGH_RISK_PORTS" | while read line; do
            echo "      $line"
        done
        SECURITY_RISK=$((SECURITY_RISK + 10))
    fi
else
    print_info "无权限获取端口信息 (需要root)"
fi

echo ""

# ======================== 2. SUID/SGID 文件检查 ========================
print_info ">>> [2/7] SUID/SGID 文件审计 ..."

# 限制扫描范围到关键目录，避免全盘扫描
SUID_FILES=$(find /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin \
    -xdev -type f \( -perm -4000 -o -perm -2000 \) -exec ls -la {} \; 2>/dev/null)

if [ -n "$SUID_FILES" ]; then
    SUID_COUNT=$(echo "$SUID_FILES" | wc -l)
    echo "    发现 ${SUID_COUNT} 个SUID/SGID文件 (仅列出非标准项):"

    # 常见安全的SUID文件白名单
    SAFE_SUID="passwd|ping|su|sudo|mount|umount|fusermount|newgrp|chsh|chfn|gpasswd|pkexec|unix_chkpwd|polkit-agent|dbus-daemon|ssh-keysign|Xorg|X|Xwrapper|bwrap"

    UNSAFE_SUID=$(echo "$SUID_FILES" | awk -v safe="$SAFE_SUID" '
        {
            name = $NF
            if (name !~ /('"$SAFE_SUID"')$/) {
                print
            }
        }
    ')
    if [ -n "$UNSAFE_SUID" ]; then
        UNSAFE_COUNT=$(echo "$UNSAFE_SUID" | wc -l)
        print_warn "发现 ${UNSAFE_COUNT} 个非标准SUID/SGID文件:"
        echo "$UNSAFE_SUID" | while read line; do
            echo "      $line"
        done
        SECURITY_RISK=$((SECURITY_RISK + UNSAFE_COUNT * 3))
    else
        print_ok "所有SUID文件均为已知安全文件"
    fi
else
    print_ok "未发现SUID/SGID文件"
fi

echo ""

# ======================== 3. 无属主文件检查 ========================
print_info ">>> [3/7] 无属主文件/目录检查 ..."

NO_OWNER=$(find / -xdev -nouser -o -nogroup 2>/dev/null | head -20)
if [ -n "$NO_OWNER" ]; then
    NO_OWNER_COUNT=$(echo "$NO_OWNER" | wc -l)
    print_warn "发现 ${NO_OWNER_COUNT} 个无属主/属组的文件:"
    echo "$NO_OWNER" | while read line; do
        echo "    $line"
    done
    SECURITY_RISK=$((SECURITY_RISK + NO_OWNER_COUNT))
else
    print_ok "未发现无属主文件"
fi

echo ""

# ======================== 4. 全局可写文件检查 ========================
print_info ">>> [4/7] 全局可写文件/目录检查 (关键路径) ..."

WORLD_WRITABLE=$(find /etc /usr/local/etc /opt -xdev -type f -perm -002 ! -path "*/.*" 2>/dev/null | head -20)
if [ -n "$WORLD_WRITABLE" ]; then
    WW_COUNT=$(echo "$WORLD_WRITABLE" | wc -l)
    print_warn "发现 ${WW_COUNT} 个全局可写文件:"
    echo "$WORLD_WRITABLE" | while read line; do
        echo "    $line"
    done
    print_info "建议: 检查这些文件权限是否必要 (chmod o-w)"
    SECURITY_RISK=$((SECURITY_RISK + WW_COUNT))
else
    print_ok "关键路径下未发现异常的全局可写文件"
fi

echo ""

# ======================== 5. 异常进程检查 ========================
print_info ">>> [5/7] 可疑进程检查 ..."

# 检查以root运行的进程
ROOT_PROCS=$(ps aux 2>/dev/null | awk '$1=="root" && $2>10' | wc -l)
echo "    root用户进程数: ${ROOT_PROCS}"

# 检查隐藏进程 (ps中出现的/proc中没有的)
HIDDEN_PROCS=0
for pid_dir in /proc/[0-9]*; do
    pid=$(basename "$pid_dir")
    if ! ps -p "$pid" &>/dev/null 2>&1; then
        HIDDEN_PROCS=$((HIDDEN_PROCS + 1))
    fi
done
# Note: /proc 中存在但 ps 看不到的情况极少, 这个检测有局限性
if [ "$HIDDEN_PROCS" -gt 5 ]; then
    print_warn "注意: 可能存在隐藏进程 (ps可见性异常)"
fi

# 检查CPU使用率异常高的进程 (>200% 多核)
HIGH_CPU=$(ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && $3+0>200 {print $2, $3"%", $11}')
if [ -n "$HIGH_CPU" ]; then
    print_warn "CPU使用率超过200%的进程 (可能是挖矿/恶意程序):"
    echo "$HIGH_CPU" | while read line; do
        echo "    $line"
    done
    SECURITY_RISK=$((SECURITY_RISK + 5))
fi

# 检查最近启动的异常进程 (过去10分钟)
if command -v journalctl &>/dev/null; then
    RECENT_PROCS=$(journalctl --no-pager _COMM=bash --since "10 min ago" 2>/dev/null | grep -i "curl\|wget\|nc\|ncat\|base64\|eval" | tail -5)
    if [ -n "$RECENT_PROCS" ]; then
        print_warn "最近10分钟存在可疑命令执行:"
        echo "$RECENT_PROCS" | while read line; do
            echo "    $line"
        done
    fi
fi

echo ""

# ======================== 6. 活跃网络连接审计 ========================
print_info ">>> [6/7] 活跃外部连接审计 ..."

if command -v ss &>/dev/null; then
    # 检查对外连接 (排除localhost和常见内网段)
    EXT_CONNECTIONS=$(ss -tnp 2>/dev/null | grep -v "127.0.0.1\|::1\|192.168\|10\.\|172\." | grep -v "LISTEN" | head -15)
    if [ -n "$EXT_CONNECTIONS" ]; then
        EXT_COUNT=$(echo "$EXT_CONNECTIONS" | grep -c "ESTAB" 2>/dev/null)
        echo "    当前活跃外部连接 (ESTABLISHED): ${EXT_COUNT:-0} 个"
        echo "$EXT_CONNECTIONS" | while read line; do
            echo "    $line"
        done

        # 检查连接到可疑端口 (IRC/暗网常用端口)
        SUSPICIOUS=$(echo "$EXT_CONNECTIONS" | awk '{
            split($5, a, ":")
            port = a[length(a)]
            if (port+0 == 6667 || port+0 == 9050 || port+0 == 9150 || port+0 == 4444 || port+0 == 1337) print
        }')
        if [ -n "$SUSPICIOUS" ]; then
            print_fail "检测到可疑外部连接! (IRC/暗网相关端口)"
            echo "$SUSPICIOUS" | while read line; do
                echo "    $line"
            done
            SECURITY_RISK=$((SECURITY_RISK + 20))
        fi
    else
        print_ok "未发现异常外部连接"
    fi
fi

echo ""

# ======================== 7. Crontab/.ssh 安全检查 ========================
print_info ">>> [7/7] 计划任务/SSH授权检查 ..."

# 检查crontab中的可疑条目
CRON_WARN=0
for cron_dir in /etc/crontab /etc/cron.d/* /var/spool/cron/crontabs/* /var/spool/cron/*; do
    if [ -f "$cron_dir" ]; then
        SUS_CRON=$(grep -iE "curl.*\|.*bash|wget.*-O.*\|nc.*-e|/dev/tcp" "$cron_dir" 2>/dev/null)
        if [ -n "$SUS_CRON" ]; then
            print_fail "发现可疑计划任务 ($cron_dir):"
            echo "$SUS_CRON" | while read line; do
                echo "    $line"
            done
            CRON_WARN=$((CRON_WARN + 1))
            SECURITY_RISK=$((SECURITY_RISK + 15))
        fi
    fi
done
if [ "$CRON_WARN" -eq 0 ]; then
    print_ok "计划任务未发现可疑条目"
fi

# 检查SSH authorized_keys
AUTH_KEYS=$(find /root /home -name "authorized_keys" -type f 2>/dev/null)
if [ -n "$AUTH_KEYS" ]; then
    KEY_COUNT=$(echo "$AUTH_KEYS" | wc -l)
    print_info "发现 ${KEY_COUNT} 个 authorized_keys 文件"
    for keyfile in $AUTH_KEYS; do
        KEY_ENTRIES=$(wc -l < "$keyfile" 2>/dev/null)
        OWNER=$(stat -c "%U" "$keyfile" 2>/dev/null || stat -f "%Su" "$keyfile" 2>/dev/null)
        echo "    $keyfile ($KEY_ENTRIES keys, owner=$OWNER)"
    done

    # 检查是否有免密root登录
    EMPTY_ROOT=$(find /root -name "authorized_keys" -type f -size +0c 2>/dev/null)
    if [ -n "$EMPTY_ROOT" ]; then
        print_info "root用户配置了SSH密钥登录"
    fi
fi

echo ""
echo "============================================================"
echo "                     安全审计结论"
echo "============================================================"

if [ "$SECURITY_RISK" -ge 30 ]; then
    echo -e "  ${RED}[高危]${NC} 安全风险评分: ${SECURITY_RISK} (需立即排查)"
    echo ""
    echo "  建议处置措施:"
    echo "  1. 检查非标准监听端口，确认服务合法性"
    echo "  2. 审查非标准SUID文件来源"
    echo "  3. 排查可疑网络连接和计划任务"
    echo "  4. 检查root SSH密钥授权"
elif [ "$SECURITY_RISK" -ge 10 ]; then
    echo -e "  ${YELLOW}[警告]${NC} 安全风险评分: ${SECURITY_RISK} (建议复查)"
else
    echo -e "  ${GREEN}[正常]${NC} 安全风险评分: ${SECURITY_RISK} (未发现明显威胁)"
fi

echo "============================================================"
