#!/bin/bash
# =============================================
# Deploy Demo-B: Pure Golang Microservices
# =============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$(dirname "$SCRIPT_DIR")/demo-b-golang"

echo "============================================"
echo "  Deploying Demo-B: Golang Microservices"
echo "============================================"

# 1. 创建命名空间
echo "[1/4] Creating namespace..."
kubectl apply -f "$MANIFESTS_DIR/namespace.yaml"

# 2. 创建ServiceAccount
echo "[2/4] Creating ServiceAccount..."
kubectl apply -f "$MANIFESTS_DIR/" - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mall-demo-sa
  namespace: demo-b-golang
  labels:
    app.kubernetes.io/part-of: mall-demo
EOF

# 3. 创建ConfigMap
echo "[3/4] Creating ConfigMap..."
kubectl apply -f "$MANIFESTS_DIR/configmap.yaml"

# 4. 部署所有服务
echo "[4/4] Deploying services..."
kubectl apply -f "$MANIFESTS_DIR/user-svc.yaml"
kubectl apply -f "$MANIFESTS_DIR/order-svc.yaml"
kubectl apply -f "$MANIFESTS_DIR/inventory-svc.yaml"
kubectl apply -f "$MANIFESTS_DIR/payment-svc.yaml"
kubectl apply -f "$MANIFESTS_DIR/notification-svc.yaml"
kubectl apply -f "$MANIFESTS_DIR/gateway.yaml"

# 等待所有Pod就绪
echo ""
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=available --timeout=180s deployment -n demo-b-golang --all || true

# 显示状态
echo ""
echo "============================================"
echo "  Demo-B Deployment Status"
echo "============================================"
kubectl get pods -n demo-b-golang -o wide
echo ""
kubectl get svc -n demo-b-golang
echo ""
echo "Demo-B deployed successfully!"
echo "Access via: http://mall-b.local/api/v1/"
