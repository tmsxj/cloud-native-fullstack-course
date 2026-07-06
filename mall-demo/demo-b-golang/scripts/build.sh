#!/bin/bash
set -e

echo "=== Building all services ==="
SERVICES="user-svc order-svc inventory-svc payment-svc notification-svc gateway"

mkdir -p bin

for svc in $SERVICES; do
    echo "  -> Building $svc..."
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o bin/$svc ./cmd/$svc
done

echo "=== All services built ==="
ls -lh bin/
