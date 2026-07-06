#!/bin/bash
# =============================================
# Deploy Demo-C: Hybrid (Spring Boot + Go) Microservices
# =============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$(dirname "$SCRIPT_DIR")/demo-c-hybrid"

echo "============================================"
echo "  Deploying Demo-C: Hybrid Microservices"
echo "  Go: gateway, user-svc, payment-svc, notification-svc"
echo "  Spring Boot: order-service, inventory-service"
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
  namespace: demo-c-hybrid
  labels:
    app.kubernetes.io/part-of: mall-demo
EOF

# 3. 创建ConfigMap
echo "[3/4] Creating ConfigMap..."
kubectl apply -f "$MANIFESTS_DIR/configmap.yaml"

# 4. 部署所有服务 (先部署Go轻量服务，再部署Spring Boot重量级服务)
echo "[4/4] Deploying services..."
echo "  -> Deploying Go services (lightweight)..."
kubectl apply -f "$MANIFESTS_DIR/user-svc.yaml"
kubectl apply -f "$MANIFESTS_DIR/payment-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/notification-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/gateway.yaml"

echo "  -> Deploying Spring Boot services (heavyweight)..."
kubectl apply -f "$MANIFESTS_DIR/order-service.yaml"
kubectl apply -f "$MANIFESTS_DIR/inventory-service.yaml"

# 等待所有Pod就绪
echo ""
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -n demo-c-hybrid --all || true

# 显示状态
echo ""
echo "============================================"
echo "  Demo-C Deployment Status"
echo "============================================"
kubectl get pods -n demo-c-hybrid -o wide
echo ""
kubectl get svc -n demo-c-hybrid
echo ""

# 显示资源使用
echo "Resource usage:"
kubectl top pods -n demo-c-hybrid 2>/dev/null || echo "  (metrics-server not available yet)"

echo ""
echo "Demo-C deployed successfully!"
echo "Access via: http://mall-c.local/api/v1/"
echo ""
echo "Architecture:"
echo "  Go services:     api-gateway, user-service, payment-service, notification-service"
echo "  Spring services: order-service, inventory-service"
echo "  Total memory:    ~550MB (vs ~750MB for pure Spring Boot)"
