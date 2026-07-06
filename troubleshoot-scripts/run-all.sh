#!/bin/bash
# ============================================================================
# Linux 故障排查脚本 - 统一运行器 (生产版)
# 用法:
#   bash run-all.sh                       # 运行全部诊断脚本(只读)
#   bash run-all.sh --module os           # 仅运行系统模块 (31-linux)
#   bash run-all.sh --module network      # 仅运行网络模块 (32-network)
#   bash run-all.sh --module kernel       # 仅运行内核模块 (33-kernel)
#   bash run-all.sh --module k8s          # 仅运行K8s模块 (29-k8s)
#   bash run-all.sh --module middleware   # 仅运行中间件诊断 (30-middleware)
#   bash run-all.sh --module daily        # 仅运行日常巡检 (36-daily)
#   bash run-all.sh --module deploy       # 仅运行发布脚本 (34-deploy) ⚠️有副作用
#   bash run-all.sh --module alert        # 仅运行告警脚本 (35-alert)
#   bash run-all.sh --script check-cpu    # 运行单个脚本
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/diagnosis-results"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT="${OUT_DIR}/report_${TIMESTAMP}.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ======================== 脚本清单 ========================
declare -A MODULES
MODULES["os"]="31-linux/check-os-resource.sh 31-linux/check-os-storage.sh 31-linux/check-os-process.sh 31-linux/check-security.sh"
MODULES["network"]="32-network/check-network-tcp.sh 32-network/check-network-other.sh"
MODULES["kernel"]="33-kernel/check-kernel-core.sh 33-kernel/check-kernel-mm.sh 33-kernel/check-kernel-sys.sh"
MODULES["k8s"]="29-k8s/check-*.sh 29-k8s/node/check-*.sh"
MODULES["middleware"]="30-middleware/check-elasticsearch.sh 30-middleware/check-kafka.sh 30-middleware/check-mysql.sh 30-middleware/check-nginx.sh 30-middleware/check-redis.sh"
MODULES["daily"]="36-daily/daily-check.sh 36-daily/daily-check-auto.sh"
MODULES["deploy"]="34-deploy/deploy-blue-green.sh 34-deploy/deploy-canary.sh 34-deploy/deploy-check.sh 34-deploy/deploy-rollback.sh 34-deploy/deploy-rollout.sh"
MODULES["alert"]="35-alert/alert-ack.sh 35-alert/alert-auto-fix.sh 35-alert/alert-postmortem.sh 35-alert/alert-triage.sh 35-alert/alert-wechat-notify.sh"

# all模式仅运行诊断类模块(只读, 有默认值)
DIAGNOSTIC_MODS="os network kernel k8s middleware daily"
# 操作类模块(仅通过--module运行, 有副作用或需参数)
OPERATIONAL_MODS="deploy alert"

ALL_MODS="$DIAGNOSTIC_MODS $OPERATIONAL_MODS"

mkdir -p "$OUT_DIR"

# 依赖检查
check_deps() {
    local missing=""
    for cmd in top vmstat ps uptime nproc awk grep sed; do
        if ! command -v "$cmd" &>/dev/null; then missing="$missing $cmd"; fi
    done
    for cmd in ss netstat iostat mpstat iotop traceroute dig curl strace ethtool; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "  ${YELLOW}[WARN]${NC} 可选依赖缺失: $cmd (功能可能受限)"
        fi
    done
    if [ -n "$missing" ]; then
        echo -e "${RED}[FATAL]${NC} 必要依赖缺失:$missing"
        exit 1
    fi
}

run_script() {
    local script="$1"
    local name
    name=$(basename "$script" .sh)
    local log="${OUT_DIR}/${name}_${TIMESTAMP}.log"

    echo -ne "  [$(date '+%H:%M:%S')] ${CYAN}${script}${NC} ... "
    if bash "${SCRIPT_DIR}/${script}" > "$log" 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        echo "  PASS  ${script}" >> "$REPORT"
    else
        echo -e "${RED}FAIL${NC} (查看日志: $log)"
        echo "  FAIL ${script}  => $log" >> "$REPORT"
    fi
}

# 命令行解析
MODE="all"
SCRIPT_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --module) MODE="$2"; shift 2 ;;
        --script) MODE="single"; SCRIPT_FILTER="$2"; shift 2 ;;
        -h|--help)
            echo "用法: bash run-all.sh [--module <mod>] [--script <name>]"
            echo ""
            echo "诊断模块 (all模式自动运行):"
            echo "  os, network, kernel, k8s, middleware, daily"
            echo ""
            echo "操作模块 (仅通过--module运行):"
            echo "  deploy  - 版本发布脚本 (⚠️ 有副作用，需传参)"
            echo "  alert   - 告警处置脚本 (需配置webhook)"
            exit 0 ;;
        *) shift ;;
    esac
done

# 开始
echo "================================================================"
echo "  Linux 故障排查诊断工具集 - 生产版 v1.2"
echo "  运行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  主机名:   $(hostname)"
echo "  结果目录: $OUT_DIR"
echo "================================================================"
echo ""

check_deps

echo "开始诊断..." | tee "$REPORT"
echo "时间: $(date)" >> "$REPORT"
echo "主机: $(hostname) ($(uname -r))" >> "$REPORT"
echo "================================================================" >> "$REPORT"

if [ "$MODE" = "single" ]; then
    # 查找匹配的脚本
    FOUND=""
    for mod in $ALL_MODS; do
        for s in ${MODULES[$mod]}; do
            if [[ "$(basename "$s" .sh)" == *"$SCRIPT_FILTER"* ]]; then
                FOUND="$s"; break 2
            fi
        done
    done
    if [ -n "$FOUND" ]; then
        run_script "$FOUND"
    else
        echo -e "${RED}[ERROR]${NC} 未找到脚本: $SCRIPT_FILTER"
        exit 1
    fi
elif [ "$MODE" = "all" ]; then
    for mod in $DIAGNOSTIC_MODS; do
        echo -e "\n${YELLOW}>>> 模块: ${mod}${NC}"
        for s in ${MODULES[$mod]}; do
            run_script "$s"
        done
    done
    echo -e "\n${CYAN}[INFO]${NC} 操作类模块(deploy/alert)未在all模式运行, 请用 --module deploy|alert"
else
    scripts="${MODULES[$MODE]:-}"
    if [ -z "$scripts" ]; then
        echo -e "${RED}[ERROR]${NC} 未知模块: $MODE"
        echo "可用模块: $ALL_MODS"
        exit 1
    fi
    # 操作类模块警告
    if echo "$OPERATIONAL_MODS" | grep -qw "$MODE"; then
        echo -e "${YELLOW}⚠️  操作类模块 [${MODE}] — 确认后继续 (Ctrl+C 取消)...${NC}"
        sleep 2
    fi
    echo -e "\n${YELLOW}>>> 模块: ${MODE}${NC}"
    for s in $scripts; do
        run_script "$s"
    done
fi

echo ""
echo "================================================================"
echo "  诊断完成！"
echo "  结果报告: $REPORT"
echo "  详细日志: ${OUT_DIR}/"
echo "================================================================"
