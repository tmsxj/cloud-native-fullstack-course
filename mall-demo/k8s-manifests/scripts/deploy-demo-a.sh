#!/bin/bash
# =============================================
# Deploy Demo-A: Pure Spring Boot Microservices
# =============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$(dirname "$SCRIPT_DIR")/demo-a-springboot"

echo "============================================"
echo "  Deploying Demo-A: Spring Boot Microservices"
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
  namespace: demo-a-springboot
  labels:
    app.kubernetes.io/part-of: mall-demo
EOF

# 3. 创建ConfigMap和Secret
echo "[3/4] Creating ConfigMap and Secrets..."
kubectl apply -f "$MANIFESTS_DIR/configmap.yaml"

# 4. 部署所有服务
echo "[4/4] Deploying services..."
kubectl apply -f "$MANIFESTS_DIR/user-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/order-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/inventory-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/payment-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/notification-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/api-gateway.yaml"

# 可选: Istio VirtualService
if kubectl get crd virtualservices.networking.istio.io &>/dev/null; then
    echo "[Optional] Applying Istio VirtualService..."
    kubectl apply -f "$MANIFESTS_DIR/istio-virtualservice.yaml"
fi

# 等待所有Pod就绪
echo ""
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -n demo-a-springboot --all || true

# 显示状态
echo ""
echo "============================================"
echo "  Demo-A Deployment Status"
echo "============================================"
kubectl get pods -n demo-a-springboot -o wide
echo ""
kubectl get svc -n demo-a-springboot
echo ""
echo "Demo-A deployed successfully!"
echo "Access via: http://mall-a.local/api/v1/"
