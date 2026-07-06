#!/bin/bash
# ============================================================
# 一键部署脚本：将全部诊断修复脚本 + Monit 布署到 t1 节点
# 用法: 在 Windows 上运行此脚本 (Git Bash / WSL)
# ============================================================
set -euo pipefail

TARGET="t1"
TARGET_IP="192.168.1.71"
REMOTE_HOME="/home/tmsxj"
SCRIPT_BASE="${REMOTE_HOME}/linux-scripts"
MONIT_CONF="/etc/monit/monitrc"
MONIT_SERVICE="/etc/systemd/system/monit.service"
SUDO_PASS="123"

# 当前脚本所在目录 (troubleshoot-scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================="
echo " 一键部署诊断脚本 + Monit → t1"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="

# ---- Step 1: 检查 t1 连通性 ----
echo ""
echo "[1/6] 检查 t1 连通性..."
if ! ssh -o ConnectTimeout=5 ${TARGET} "hostname" &>/dev/null; then
    echo "ERROR: 无法连接 t1 (${TARGET_IP})，请确认 VM 已启动"
    exit 1
fi
echo "  ✓ t1 可达"

# ---- Step 2: 创建远程目录 ----
echo ""
echo "[2/6] 创建远程目录结构..."
ssh ${TARGET} "mkdir -p ${SCRIPT_BASE}/{31-linux,32-network,33-kernel,29-k8s,29-k8s/node,30-middleware,34-deploy,35-alert,36-daily,auto-fix}"

# ---- Step 3: 上传所有脚本 ----
echo ""
echo "[3/6] 上传脚本文件..."

upload_dir() {
    local local_dir="$1"
    local remote_dir="$2"
    if [ -d "${SCRIPT_DIR}/${local_dir}" ] && [ "$(ls -A "${SCRIPT_DIR}/${local_dir}"/*.sh 2>/dev/null)" ]; then
        echo "  上传 ${local_dir}/ → ${remote_dir}/"
        scp -q "${SCRIPT_DIR}/${local_dir}"/*.sh ${TARGET}:${remote_dir}/
    fi
}

upload_dir "31-linux"      "${SCRIPT_BASE}/31-linux"
upload_dir "32-network"    "${SCRIPT_BASE}/32-network"
upload_dir "33-kernel"     "${SCRIPT_BASE}/33-kernel"
upload_dir "29-k8s"        "${SCRIPT_BASE}/29-k8s"
upload_dir "29-k8s/node"   "${SCRIPT_BASE}/29-k8s/node"
upload_dir "30-middleware" "${SCRIPT_BASE}/30-middleware"
upload_dir "34-deploy"     "${SCRIPT_BASE}/34-deploy"
upload_dir "35-alert"      "${SCRIPT_BASE}/35-alert"
upload_dir "36-daily"      "${SCRIPT_BASE}/36-daily"
upload_dir "auto-fix"      "${SCRIPT_BASE}/auto-fix"

# 上传根目录文件
echo "  上传根目录脚本..."
scp -q "${SCRIPT_DIR}/run-all.sh" ${TARGET}:${SCRIPT_BASE}/ 2>/dev/null || true

echo "  ✓ 脚本上传完成"

# ---- Step 4: 设置执行权限 ----
echo ""
echo "[4/6] 设置执行权限..."
ssh ${TARGET} "chmod +x ${SCRIPT_BASE}/**/*.sh ${SCRIPT_BASE}/*.sh 2>/dev/null; chmod +x ${SCRIPT_BASE}/31-linux/*.sh ${SCRIPT_BASE}/32-network/*.sh ${SCRIPT_BASE}/33-kernel/*.sh ${SCRIPT_BASE}/29-k8s/*.sh ${SCRIPT_BASE}/29-k8s/node/*.sh ${SCRIPT_BASE}/30-middleware/*.sh ${SCRIPT_BASE}/auto-fix/*.sh 2>/dev/null"
echo "  ✓ 权限设置完成"

# ---- Step 5: 部署 Monit ----
echo ""
echo "[5/6] 部署 Monit 配置..."

# 上传 monitrc
scp -q "${SCRIPT_DIR}/monitrc" ${TARGET}:/tmp/monitrc
ssh ${TARGET} "echo '${SUDO_PASS}' | sudo -S cp /tmp/monitrc ${MONIT_CONF} && echo '${SUDO_PASS}' | sudo -S chmod 600 ${MONIT_CONF}"

# 上传 monit.service
scp -q "${SCRIPT_DIR}/monit.service" ${TARGET}:/tmp/monit.service
ssh ${TARGET} "echo '${SUDO_PASS}' | sudo -S cp /tmp/monit.service ${MONIT_SERVICE}"

# 检查 monit 二进制是否存在
MONIT_EXISTS=$(ssh ${TARGET} "test -f /usr/local/bin/monit && echo 'yes' || echo 'no'")
if [ "$MONIT_EXISTS" = "no" ]; then
    echo "  ⚠ monit 未安装，正在安装..."
    ssh ${TARGET} "echo '${SUDO_PASS}' | sudo -S apt-get update -qq && echo '${SUDO_PASS}' | sudo -S apt-get install -y -qq monit"
fi

echo "  ✓ Monit 配置部署完成"

# ---- Step 6: 重载 Monit ----
echo ""
echo "[6/6] 重载 Monit..."
ssh ${TARGET} "echo '${SUDO_PASS}' | sudo -S systemctl daemon-reload && echo '${SUDO_PASS}' | sudo -S systemctl enable monit && echo '${SUDO_PASS}' | sudo -S monit reload 2>/dev/null || echo '${SUDO_PASS}' | sudo -S systemctl restart monit"

echo "  ✓ Monit 已重载"

# ---- 验证 ----
echo ""
echo "============================================="
echo " 部署完成！验证状态："
echo "============================================="
echo ""
echo "--- Monit 服务状态 ---"
ssh ${TARGET} "echo '${SUDO_PASS}' | sudo -S systemctl is-active monit && echo '${SUDO_PASS}' | sudo -S monit summary"
echo ""
echo "--- 脚本文件统计 ---"
ssh ${TARGET} "find ${SCRIPT_BASE} -name '*.sh' | wc -l | xargs echo '脚本总数:'"
echo ""
echo "部署完毕。Monit 每 60 秒自动巡检。" 
