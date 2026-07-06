#!/bin/bash
# =============================================
# Clean All Mall Demo Resources
# Usage:
#   ./clean-all.sh              # Clean all demos
#   ./clean-all.sh demo-a       # Clean only demo-a
#   ./clean-all.sh demo-b       # Clean only demo-b
#   ./clean-all.sh demo-c       # Clean only demo-c
#   ./clean-all.sh --pvc        # Clean all including PVC
# =============================================
set -e

DEMO_TO_CLEAN="${1:-all}"
DELETE_PVC=false
if [[ "$DEMO_TO_CLEAN" == "--pvc" ]]; then
    DELETE_PVC=true
    DEMO_TO_CLEAN="all"
fi

echo "============================================"
echo "  Cleaning Mall Demo Resources"
echo "  Target: $DEMO_TO_CLEAN"
echo "  Delete PVC: $DELETE_PVC"
echo "============================================"

clean_demo() {
    local ns=$1
    local name=$2

    echo ""
    echo "--- Cleaning $name (namespace: $ns) ---"

    # 删除Istio资源
    if kubectl get crd virtualservices.networking.istio.io &>/dev/null; then
        echo "  Removing Istio resources..."
        kubectl delete virtualservice --all -n "$ns" 2>/dev/null || true
        kubectl delete destinationrule --all -n "$ns" 2>/dev/null || true
    fi

    # 删除Ingress
    echo "  Removing Ingress..."
    kubectl delete ingress --all -n "$ns" 2>/dev/null || true

    # 删除Deployments
    echo "  Removing Deployments..."
    kubectl delete deployment --all -n "$ns" 2>/dev/null || true

    # 删除Services
    echo "  Removing Services..."
    kubectl delete service --all -n "$ns" 2>/dev/null || true

    # 删除ConfigMaps
    echo "  Removing ConfigMaps..."
    kubectl delete configmap --all -n "$ns" 2>/dev/null || true

    # 删除Secrets
    echo "  Removing Secrets..."
    kubectl delete secret --all -n "$ns" 2>/dev/null || true

    # 删除ServiceAccounts
    echo "  Removing ServiceAccounts..."
    kubectl delete serviceaccount --all -n "$ns" 2>/dev/null || true

    # 可选: 删除PVC
    if [[ "$DELETE_PVC" == true ]]; then
        echo "  Removing PVCs..."
        kubectl delete pvc --all -n "$ns" 2>/dev/null || true
    fi

    # 最后删除命名空间
    echo "  Removing namespace..."
    kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || true

    echo "  $name cleaned!"
}

case "$DEMO_TO_CLEAN" in
    demo-a|a)
        clean_demo "demo-a-springboot" "Demo-A (Spring Boot)"
        ;;
    demo-b|b)
        clean_demo "demo-b-golang" "Demo-B (Golang)"
        ;;
    demo-c|c)
        clean_demo "demo-c-hybrid" "Demo-C (Hybrid)"
        ;;
    all)
        clean_demo "demo-c-hybrid" "Demo-C (Hybrid)"
        clean_demo "demo-b-golang" "Demo-B (Golang)"
        clean_demo "demo-a-springboot" "Demo-A (Spring Boot)"
        ;;
    *)
        echo "Usage: $0 [demo-a|demo-b|demo-c|all|--pvc]"
        exit 1
        ;;
esac

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"

# 验证
echo ""
echo "Remaining namespaces:"
kubectl get ns | grep demo || echo "  All demo namespaces removed."
