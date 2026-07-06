# 模块08：Ingress与Istio服务网格

---

## 1. 概述与架构图

### 1.1 南北流量 vs 东西流量

```
                        Internet
                           |
                           v
              +------------------------+
              |    DNS (NodePort)      |
              +------------------------+
                           |
              +------------------------+
              |   Ingress Controller   |  <-- 南北流量入口
              |   (Nginx Ingress)      |     VMware 裸金属环境使用 NodePort
              +------------------------+     或 hostPort 方式暴露
                     /          \
                    /            \
         +----------+    +--------+----------+
         | Service A |    | Service B        |   <-- K8s Service
         +----------+    +--------+----------+
                                |
              +----------------------------------+
              |       Istio Service Mesh         |  <-- 东西流量
              |  +------+    +------+    +------+|
              |  |Svc C |<-->|Svc D |<-->|Svc E ||
              |  +------+    +------+    +------+|
              |  (Envoy Sidecar 每个Pod注入)      |
              +----------------------------------+
```

### 1.2 完整流量架构

```
                         Internet
                            |
              +-----------------------------+
              |  NodePort / hostPort         |
              |  (VMware裸金属无LB环境)       |
              +-----------------------------+
                            |
              +-----------------------------+
              |   Nginx Ingress Controller   |  ingress-nginx Namespace
              |   (Deployment + NodePort)    |
              +-----------------------------+
                     /             \
        +------------+             +------------+
        | IngressRule|             | IngressRule|
        | api.shop.  |             | web.shop.  |
        | com        |             | com        |
        +------------+             +------------+
              |                         |
        +-----------+            +-----------+
        | api-svc   |            | web-svc   |    istio-system Namespace
        +-----------+            +-----------+
              |                         |
      +-------+-------+         +-------+-------+
      | user-svc      |         | frontend-svc  |
      | (Envoy Sidecar)|        | (Envoy Sidecar)|
      +-------+-------+         +-------+-------+
              |                         |
      +-------+-------+         +-------+-------+
      | order-svc     |<------->| cart-svc      |
      | (Envoy Sidecar)|        | (Envoy Sidecar)|
      +---------------+         +---------------+
              |
      +-------+-------+
      | inventory-svc |
      | (Envoy Sidecar)|
      +---------------+
```

### 1.3 Istio 数据面与控制面

```
+================================================+
|                Istio Control Plane             |
|               (istiod)                         |
|  +----------+ +----------+ +----------+       |
|  | Pilot    | | Citadel  | | Galley   |       |
|  | (xDS API)| | (mTLS CA)| | (Config) |       |
|  +----------+ +----------+ +----------+       |
+================================================+
        |  xDS (gRPC)  |  xDS (gRPC)  |
        v               v               v
+-------------+ +-------------+ +-------------+
| Pod A       | | Pod B       | | Pod C       |
| +---------+ | | +---------+ | | +---------+ |
| | App     | | | | App     | | | | App     | |
| +---------+ | | +---------+ | | +---------+ |
| | Envoy   | | | | Envoy   | | | | Envoy   | |
| | Sidecar | | | | Sidecar | | | | Sidecar | |
| +---------+ | | +---------+ | | +---------+ |
+-------------+ +-------------+ +-------------+
```

---

## 2. 理论基础

### 2.1 Ingress 核心概念

**Ingress** 是 Kubernetes 中管理集群外部访问到集群内服务的 API 对象，主要提供 HTTP/HTTPS 路由功能。

| 概念 | 说明 |
|------|------|
| Ingress Resource（Ingress 资源） | 定义路由规则（Host、Path、TLS）的 K8s 资源对象 |
| Ingress Controller（Ingress 控制器） | 实际执行路由转发的组件，监听 Ingress 资源变化并动态更新配置 |
| Ingress Class（Ingress 类） | K8s 1.18+ 引入，用于区分不同类型的 Ingress Controller |
| Backend（后端） | 路由目标，通常是 Service 名称和端口 |

**Ingress vs NodePort vs LoadBalancer 对比：**

| 特性 | NodePort | LoadBalancer | Ingress |
|------|----------|-------------|---------|
| 暴露端口数 | 每个Service一个 | 每个Service一个 | 共享80/443 |
| TLS终止 | 需自行处理 | 需自行处理 | Ingress Controller统一处理 |
| 路由能力 | 无 | 无 | 基于Host/Path路由 |
| VIP/域名 | 不支持 | 支持 | 支持 |
| 适用场景 | 开发测试 | 云环境单服务 | 生产多服务 |

> **离线环境注意：** 本集群为 VMware 裸金属环境，无 Cloud Provider，**LoadBalancer 类型 Service 不可用**。请使用 NodePort 或 hostPort 方式暴露服务。

### 2.2 Nginx Ingress Controller 架构

Nginx Ingress Controller 是最广泛使用的 Ingress Controller 实现：

- **配置热更新**：通过 Lua + NGINX 动态 reload，无需重启
- **自定义资源**：IngressRoute (TCPRoute, UDPRoute, VirtualServer, VirtualServerRoute)
- **注解驱动**：通过 Ingress 注解配置限流、CORS、认证等高级功能
- **监控集成**：内置 Prometheus metrics 端点 `/metrics`

### 2.3 Istio 核心概念

**Istio** 是一个开源的服务网格（Service Mesh）平台，提供流量管理、安全性和可观测性。

| 组件 | 功能 |
|------|------|
| istiod | 控制面统一组件（合并了 Pilot、Citadel、Galley） |
| Envoy Proxy（Envoy 代理） | 数据面代理，以 Sidecar 形式注入每个 Pod |
| istio-ingressgateway | 网格入口网关（替代 Ingress） |
| istio-egressgateway | 网格出口网关 |
| Kiali | 服务网格可视化仪表板 |

**核心资源类型：**

| 资源 | 作用 |
|------|------|
| VirtualService（虚拟服务） | 定义路由规则（版本路由、金丝雀发布、故障注入） |
| DestinationRule（目标规则） | 定义目标服务的策略（负载均衡、连接池、熔断） |
| Gateway（网关） | 定义入口/出口网关的端口和协议 |
| PeerAuthentication（对等认证） | 定义 mTLS 策略 |
| AuthorizationPolicy（授权策略） | 定义访问控制策略 |
| ServiceEntry（服务条目） | 注册网格外部的服务 |
| Sidecar | 定义 Sidecar 代理的配置范围 |

### 2.4 mTLS（Mutual TLS，双向TLS）

```
Pod A (Envoy)  <---- mTLS ---->  Pod B (Envoy)

1. Pod A Envoy 发送 ClientHello + SNI
2. Pod B Envoy 返回 ServerHello + Certificate
3. Pod A Envoy 验证 Pod B 证书（由 istiod CA 签发）
4. Pod A Envoy 发送自己的 Certificate
5. Pod B Envoy 验证 Pod A 证书
6. 双方协商密钥，建立加密通道
7. Istio 自动证书轮转（默认24小时）
```

**mTLS 模式：**

| 模式 | 说明 |
|------|------|
| STRICT | 严格模式，所有流量必须使用 mTLS |
| PERMISSIVE | 宽容模式，同时接受 mTLS 和明文流量（迁移过渡用） |
| DISABLE | 禁用 mTLS |

---

## 3. 离线前置准备

> **环境说明：** 本文档所有操作均基于 6 节点 K8s v1.28.15 离线集群，Harbor 地址 `192.168.1.61`（HTTP 协议，密码 `Harbor12345`），无外网访问。Master 节点 2C4G，Worker 节点 4C8G，已部署 `local-path` StorageClass（名称 `local-path`）。VMware 裸金属环境，无 Cloud Provider，**不支持 LoadBalancer 类型 Service**。

### 3.0.1 确认 StorageClass 可用

```bash
# 确认 local-path StorageClass 已就绪
kubectl get sc
# 预期输出：
# NAME         PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
# local-path   rancher.io/local-path  Delete          WaitForFirstConsumer

# 设为默认（如尚未设置）
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 3.0.2 Helm 离线安装

```bash
# 在有外网的机器上下载 Helm 二进制包，然后拷贝到 Master 节点
# 方法一：直接拷贝已编译的二进制文件
# 将 helm 二进制文件拷贝到 /usr/local/bin/helm 并赋权
chmod +x /usr/local/bin/helm
helm version

# 方法二：离线安装（推荐在有网机器上提前下载）
# 在有网机器上：
#   wget https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz
#   拷贝到 Master 节点后执行：
tar -zxvf helm-v3.14.0-linux-amd64.tar.gz
cp linux-amd64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm
helm version
```

### 3.0.3 Helm Chart 离线打包

```bash
# ===== 以下命令在有外网的机器上执行 =====

# ==== Ingress NGINX ====
# helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# helm pull ingress-nginx/ingress-nginx --version 4.10.1
# 生成文件：ingress-nginx-4.10.1.tgz

# ==== cert-manager ====
# helm repo add jetstack https://charts.jetstack.io
# helm pull jetstack/cert-manager --version v1.14.4
# 生成文件：cert-manager-v1.14.4.tgz

# ==== Kiali ====
# helm repo add kiali https://kiali.org/helm-charts
# helm pull kiali/kiali-server --version 1.80.0
# 生成文件：kiali-server-1.80.0.tgz

# 将以上 .tgz 文件拷贝到 Master 节点的 /root/charts/ 目录
mkdir -p /root/charts
# 拷贝 ingress-nginx-4.10.1.tgz cert-manager-v1.14.4.tgz kiali-server-1.80.0.tgz 到此目录

# 从本地 Chart 安装（示例）
helm install <release-name> /root/charts/<chart-file>.tgz --namespace <ns>
```

### 3.0.4 镜像清单与预推送

以下为本模块所需的全部镜像，需在有外网的机器上提前拉取、打标签并推送到 Harbor。

| 组件 | 原始镜像 | Harbor 镜像 |
|------|---------|-------------|
| Nginx Ingress Controller | registry.k8s.io/ingress-nginx/controller:v1.10.1 | 192.168.1.61/ingress-nginx/controller:v1.10.1 |
| Nginx Ingress Admission Webhook | registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.1 | 192.168.1.61/ingress-nginx/kube-webhook-certgen:v1.4.1 |
| Nginx Ingress Default Backend | registry.k8s.io/defaultbackend-amd64:1.5 | 192.168.1.61/ingress-nginx/defaultbackend-amd64:1.5 |
| cert-manager | quay.io/jetstack/cert-manager-controller:v1.14.4 | 192.168.1.61/jetstack/cert-manager-controller:v1.14.4 |
| cert-manager cainjector | quay.io/jetstack/cert-manager-cainjector:v1.14.4 | 192.168.1.61/jetstack/cert-manager-cainjector:v1.14.4 |
| cert-manager webhook | quay.io/jetstack/cert-manager-webhook:v1.14.4 | 192.168.1.61/jetstack/cert-manager-webhook:v1.14.4 |
| Istio pilot (istiod) | docker.io/istio/pilot:1.21.0 | 192.168.1.61/istio/pilot:1.21.0 |
| Istio proxyv2 | docker.io/istio/proxyv2:1.21.0 | 192.168.1.61/istio/proxyv2:1.21.0 |
| Istio ingressgateway | docker.io/istio/proxyv2:1.21.0 | 192.168.1.61/istio/proxyv2:1.21.0 |
| Kiali | quay.io/kiali/kiali:v1.80.0 | 192.168.1.61/kiali/kiali:v1.80.0 |
| Demo 应用 (nginx) | docker.io/library/nginx:1.25-alpine | 192.168.1.61/library/nginx:1.25-alpine |
| Demo 应用 v2 (nginx) | docker.io/library/nginx:1.26-alpine | 192.168.1.61/library/nginx:1.26-alpine |

```bash
# 在有外网的机器上执行镜像拉取、打标签、推送
# ==== 1. 登录 Harbor ====
docker login 192.168.1.61 -u admin -p Harbor12345

# ==== 2. 创建 Harbor 项目 ====
# 在 Harbor UI 中创建以下项目（或使用 API）：
#   ingress-nginx, jetstack, istio, kiali, library

# ==== 3. 拉取、打标签、推送（以 ingress-nginx 为例）====
docker pull registry.k8s.io/ingress-nginx/controller:v1.10.1
docker tag registry.k8s.io/ingress-nginx/controller:v1.10.1 192.168.1.61/ingress-nginx/controller:v1.10.1
docker push 192.168.1.61/ingress-nginx/controller:v1.10.1

# ==== 4. 批量处理所有镜像 ====
IMAGES=(
  "registry.k8s.io/ingress-nginx/controller:v1.10.1 192.168.1.61/ingress-nginx/controller:v1.10.1"
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.1 192.168.1.61/ingress-nginx/kube-webhook-certgen:v1.4.1"
  "registry.k8s.io/defaultbackend-amd64:1.5 192.168.1.61/ingress-nginx/defaultbackend-amd64:1.5"
  "quay.io/jetstack/cert-manager-controller:v1.14.4 192.168.1.61/jetstack/cert-manager-controller:v1.14.4"
  "quay.io/jetstack/cert-manager-cainjector:v1.14.4 192.168.1.61/jetstack/cert-manager-cainjector:v1.14.4"
  "quay.io/jetstack/cert-manager-webhook:v1.14.4 192.168.1.61/jetstack/cert-manager-webhook:v1.14.4"
  "docker.io/istio/pilot:1.21.0 192.168.1.61/istio/pilot:1.21.0"
  "docker.io/istio/proxyv2:1.21.0 192.168.1.61/istio/proxyv2:1.21.0"
  "quay.io/kiali/kiali:v1.80.0 192.168.1.61/kiali/kiali:v1.80.0"
  "docker.io/library/nginx:1.25-alpine 192.168.1.61/library/nginx:1.25-alpine"
  "docker.io/library/nginx:1.26-alpine 192.168.1.61/library/nginx:1.26-alpine"
)

for item in "${IMAGES[@]}"; do
  SRC=$(echo $item | awk '{print $1}')
  DST=$(echo $item | awk '{print $2}')
  docker pull $SRC
  docker tag $SRC $DST
  docker push $DST
done

# ==== 5. 在离线集群的每个节点上配置 containerd/docker 拉取 Harbor 镜像 ====
# 如果 Harbor 使用 HTTP，需配置 insecure registry
# containerd 方式：编辑 /etc/containerd/config.toml
#   [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.61".tls]
#     insecure_skip_verify = true
# systemctl restart containerd

# docker 方式：编辑 /etc/docker/daemon.json
#   { "insecure-registries": ["192.168.1.61"] }
# systemctl restart docker
```

### 3.0.5 istioctl 离线安装

```bash
# 在有外网的机器上下载 istioctl 二进制文件
# curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.21.0 sh -
# 拷贝 istio-1.21.0/bin/istioctl 到 Master 节点

cp istioctl /usr/local/bin/istioctl
chmod +x /usr/local/bin/istioctl
istioctl version
```

---

## 4. 部署实战

### 4.1 部署 Nginx Ingress Controller

#### 4.1.1 安装 Helm（如未安装）

> Helm 离线安装方式请参见 [3.0.2 Helm 离线安装](#302-helm-离线安装) 章节。

```bash
# 确认 Helm 已安装
helm version
```

#### 4.1.2 使用离线 Chart 安装

> **说明：** VMware 裸金属环境没有 Cloud Provider，**LoadBalancer 类型的 Service 无法分配外部 IP**（会一直处于 Pending 状态）。因此本部署使用 `NodePort` 方式暴露 Ingress Controller，通过 `Worker节点IP:NodePort` 访问。如需使用 hostPort 方式（直接占用节点 80/443 端口），可参考下方注释。

```bash
# 使用离线 Chart 安装（Chart 文件已提前拷贝到 /root/charts/）
# 如未准备 Chart 文件，请参见 3.0.3 节进行离线打包

# 创建命名空间
kubectl create namespace ingress-nginx

# 安装 Nginx Ingress Controller（NodePort 方式）
helm install ingress-nginx /root/charts/ingress-nginx-4.10.1.tgz \
  --namespace ingress-nginx \
  --set controller.image.registry=192.168.1.61 \
  --set controller.image.image=ingress-nginx/controller \
  --set controller.image.tag=v1.10.1 \
  --set controller.admissionWebhooks.patch.image.registry=192.168.1.61 \
  --set controller.admissionWebhooks.patch.image.image=ingress-nginx/kube-webhook-certgen \
  --set controller.admissionWebhooks.patch.image.tag=v1.4.1 \
  --set defaultBackend.image.registry=192.168.1.61 \
  --set defaultBackend.image.image=ingress-nginx/defaultbackend-amd64 \
  --set defaultBackend.image.tag=1.5 \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.config.proxy-body-size="50m" \
  --set controller.config.proxy-connect-timeout="60" \
  --set controller.config.proxy-read-timeout="600" \
  --set controller.config.proxy-send-timeout="600" \
  --set controller.config.client-max-body-size="50m" \
  --set controller.config.proxy-buffer-size="128k" \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.admissionWebhooks.enabled=true \
  --set controller.admissionWebhooks.patch.enabled=true \
  --set controller.replicaCount=2 \
  --set controller.resources.requests.cpu=200m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.resources.limits.cpu=500m \
  --set controller.resources.limits.memory=512Mi \
  --set defaultBackend.enabled=true \
  --set defaultBackend.replicaCount=1 \
  --wait --timeout 120s

# ---- hostPort 方式（可选，直接占用节点 80/443 端口，无需 NodePort）----
# helm install ingress-nginx /root/charts/ingress-nginx-4.10.1.tgz \
#   --namespace ingress-nginx \
#   --set controller.image.registry=192.168.1.61 \
#   --set controller.image.image=ingress-nginx/controller \
#   --set controller.image.tag=v1.10.1 \
#   --set controller.admissionWebhooks.patch.image.registry=192.168.1.61 \
#   --set controller.admissionWebhooks.patch.image.image=ingress-nginx/kube-webhook-certgen \
#   --set controller.admissionWebhooks.patch.image.tag=v1.4.1 \
#   --set controller.kind=DaemonSet \
#   --set controller.hostPort.enabled=true \
#   --set controller.hostPort.ports.http=80 \
#   --set controller.hostPort.ports.https=443 \
#   --set controller.service.type=ClusterIP \
#   --set controller.admissionWebhooks.enabled=true \
#   --set controller.admissionWebhooks.patch.enabled=true \
#   --set controller.resources.requests.cpu=200m \
#   --set controller.resources.requests.memory=256Mi \
#   --set controller.resources.limits.cpu=500m \
#   --set controller.resources.limits.memory=512Mi \
#   --wait --timeout 120s
```

#### 4.1.3 验证安装

```bash
# 检查 Pod 状态
kubectl get pods -n ingress-nginx -o wide

# 检查 Service
kubectl get svc -n ingress-nginx

# 预期输出
# NAME                                 TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
# ingress-nginx-controller             NodePort   10.96.xxx.xxx     <none>        80:30080/TCP,443:30443/TCP   5m
# ingress-nginx-controller-admission   ClusterIP  10.96.xxx.xxx     <none>        443/TCP                      5m
# ingress-nginx-defaultbackend         ClusterIP  10.96.xxx.xxx     <none>        80/TCP                       5m

# 测试访问
curl -I http://192.168.1.54:30080
# 预期返回 404（无默认路由）
```

### 4.2 部署 Demo 应用

```bash
# 创建命名空间
kubectl create namespace demo

# 部署 Spring Boot 后端 API 服务
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: demo
  labels:
    app: api-server
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
        version: v1
    spec:
      containers:
      - name: api-server
        image: 192.168.1.61/library/nginx:1.25-alpine
        ports:
        - containerPort: 8080
        env:
        - name: SERVER_PORT
          value: "8080"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: api-server
  namespace: demo
spec:
  selector:
    app: api-server
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF

# 部署前端服务
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  namespace: demo
  labels:
    app: web-frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-frontend
  template:
    metadata:
      labels:
        app: web-frontend
    spec:
      containers:
      - name: web-frontend
        image: 192.168.1.61/library/nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: web-frontend
  namespace: demo
spec:
  selector:
    app: web-frontend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
```

### 4.3 创建 Ingress 路由规则

```bash
# 基础 Ingress 规则
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress                  # K8s Ingress 资源
metadata:
  name: demo-ingress
  namespace: demo
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2      # URL 重写
    nginx.ingress.kubernetes.io/enable-cors: "true"       # 启用跨域
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, PUT, POST, DELETE, PATCH, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"    # 请求体大小限制
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"  # 读取超时
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"  # 发送超时
    nginx.ingress.kubernetes.io/ssl-redirect: "true"      # 强制 HTTPS
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/use-regex: "true"         # 启用正则匹配
spec:
  ingressClassName: nginx        # 指定 Ingress Controller 类
  tls:                           # TLS 证书配置
  - hosts:
    - api.demo.local
    - web.demo.local
    secretName: demo-tls-secret  # TLS 证书 Secret 名称
  rules:
  - host: api.demo.local
    http:
      paths:
      - path: /api(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: api-server
            port:
              number: 80
  - host: web.demo.local
    http:
      paths:
      - path: /(.*)
        pathType: Prefix
        backend:
          service:
            name: web-frontend
            port:
              number: 80
EOF
```

### 4.4 部署 cert-manager 自动 TLS

```bash
# 使用离线 Chart 安装 cert-manager
# Chart 文件路径：/root/charts/cert-manager-v1.14.4.tgz
helm install cert-manager /root/charts/cert-manager-v1.14.4.tgz \
  --namespace cert-manager \
  --create-namespace \
  --set image.repository=192.168.1.61/jetstack/cert-manager-controller \
  --set cainjector.image.repository=192.168.1.61/jetstack/cert-manager-cainjector \
  --set webhook.image.repository=192.168.1.61/jetstack/cert-manager-webhook \
  --set installCRDs=true \
  --set replicaCount=1 \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=200m \
  --set resources.limits.memory=256Mi \
  --wait --timeout 120s

# 验证 cert-manager
kubectl get pods -n cert-manager
# 预期：cert-manager-xxx, cert-manager-cainjector-xxx, cert-manager-webhook-xxx Running

# 创建自签名 ClusterIssuer（用于测试环境，离线环境推荐）
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer              # 集群级证书签发者
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

# 注意：Let's Encrypt 需要外网访问，离线环境不可用
# 以下 Let's Encrypt Issuer 仅在有外网的环境中可用，离线集群请使用自签名 Issuer
# cat <<'EOF' | kubectl apply -f -
# apiVersion: cert-manager.io/v1
# kind: ClusterIssuer
# metadata:
#   name: letsencrypt-staging
# spec:
#   acme:
#     server: https://acme-staging-v02.api.letsencrypt.org/directory
#     email: admin@example.com
#     privateKeySecretRef:
#       name: letsencrypt-staging-key
#     solvers:
#     - http01:
#         ingress:
#           class: nginx
# EOF

# 使用自签名证书创建 TLS Ingress
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate               # 证书资源 CRD
metadata:
  name: demo-tls
  namespace: demo
spec:
  secretName: demo-tls-secret    # 证书存储到该 Secret
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - api.demo.local
  - web.demo.local
  commonName: demo.local
EOF

# 检查证书状态
kubectl get certificate -n demo
# 预期：demo-tls True（Ready）

# 检查 Secret
kubectl get secret demo-tls-secret -n demo
```

### 4.5 部署 Istio

#### 4.5.1 安装 istioctl

> istioctl 离线安装方式请参见 [3.0.5 istioctl 离线安装](#305-istioctl-离线安装) 章节。

```bash
# 确认 istioctl 已安装
istioctl version

# 验证集群兼容性
istioctl x precheck
```

#### 4.5.2 安装 Istio（最小化配置，适配 Master 2C4G 节点）

> **资源优化说明：** 由于 Master 节点仅 2C4G，istiod 资源已降低为 requests cpu:100m/memory:256Mi, limits cpu:500m/memory:1Gi。副本数设为 1，关闭 HPA。istio-ingressgateway 同样降低资源需求。

```bash
# 创建 IstioOperator 配置
cat <<'EOF' > istio-operator.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator             # Istio 安装配置 CRD
metadata:
  namespace: istio-system
  name: istio-operator
spec:
  profile: minimal               # 最小化安装配置
  hub: 192.168.1.61
  tag: "istio/pilot:1.21.0"
  values:
    global:
      hub: 192.168.1.61
      tag: "istio"
      proxy:
        image: proxyv2           # Envoy 代理镜像
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        logLevel: warning
      proxyInit:                 # Sidecar 初始化容器
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
          limits:
            cpu: 100m
            memory: 64Mi
  components:
    pilot:                       # istiod 控制面组件
      enabled: true
      k8s:
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
        replicas: 1
    ingressGateways:
    - name: istio-ingressgateway  # 入口网关
      enabled: true
      k8s:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        replicas: 1
        service:
          type: NodePort
          ports:
          - port: 80
            targetPort: 8080
            nodePort: 31080        # HTTP 外部访问端口
            name: http2
          - port: 443
            targetPort: 8443
            nodePort: 31443        # HTTPS 外部访问端口
            name: https
    egressGateways:
    - name: istio-egressgateway
      enabled: false
EOF

# 执行安装
istioctl install -f istio-operator.yaml -y

# 验证安装
kubectl get pods -n istio-system
# 预期：istiod-xxx Running

kubectl get svc -n istio-system
# 预期：istiod ClusterIP, istio-ingressgateway NodePort
```

#### 4.5.3 为命名空间启用 Istio Sidecar 自动注入

```bash
# 标记命名空间启用自动注入
kubectl label namespace demo istio-injection=enabled --overwrite

# 验证标签
kubectl get namespace demo --show-labels

# 重启 demo 命名空间中的 Pod 以注入 Sidecar
kubectl rollout restart deployment api-server -n demo
kubectl rollout restart deployment web-frontend -n demo

# 验证 Sidecar 注入（每个 Pod 应有 2/2 容器）
kubectl get pods -n demo
kubectl describe pod -l app=api-server -n demo | grep -A 5 "Containers:"

# 验证 Envoy 配置
kubectl exec -it deploy/api-server -n demo -c istio-proxy -- pilot-agent request GET config_dump | head -50
```

### 4.6 Istio Gateway 与 VirtualService

```bash
# 创建 Istio Gateway
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway                  # Istio 网关资源
metadata:
  name: demo-gateway
  namespace: demo
spec:
  selector:
    istio: ingressgateway      # 绑定到入口网关
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "api.demo.local"
    - "web.demo.local"
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE             # 单向 TLS 模式
      credentialName: demo-tls-secret
    hosts:
    - "api.demo.local"
    - "web.demo.local"
EOF

# 创建 VirtualService
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server-vs
  namespace: demo
spec:
  hosts:
  - "api.demo.local"
  gateways:
  - demo-gateway
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: api-server
        port:
          number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: web-frontend-vs
  namespace: demo
spec:
  hosts:
  - "web.demo.local"
  gateways:
  - demo-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: web-frontend
        port:
          number: 80
EOF
```

### 4.7 部署 Kiali 可视化

```bash
# Kiali YAML 文件需提前下载到本地（在有网机器上执行）：
#   wget https://raw.githubusercontent.com/istio/istio/release-1.21/samples/addons/kiali.yaml -O /root/manifests/kiali.yaml
# 拷贝到 Master 节点后执行：
kubectl apply -f /root/manifests/kiali.yaml

# 或者使用离线 Helm Chart 安装（推荐）
helm install kiali-server /root/charts/kiali-server-1.80.0.tgz \
  --namespace istio-system \
  --set image.repository=192.168.1.61/kiali/kiali \
  --set image.tag=v1.80.0 \
  --set auth.strategy="anonymous" \
  --set server.web_port=20001 \
  --set external_services.istio.url="http://istiod.istio-system.svc:15014" \
  --set external_services.prometheus.url="http://prometheus-server.monitoring.svc:9090" \
  --wait --timeout 120s

# 使用 NodePort 暴露 Kiali
kubectl patch svc kiali-server -n istio-system -p '{"spec":{"type":"NodePort","ports":[{"port":20001,"targetPort":20001,"nodePort":32001}]}}'

# 访问 Kiali：http://<Worker节点IP>:32001
```

---

## 5. 配置详解 / 高级功能

### 5.1 Nginx Ingress 高级注解

```bash
# 限流配置
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-rate-limit
  namespace: demo
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/limit-connections: "50"
    nginx.ingress.kubernetes.io/limit-burst: "200"
    nginx.ingress.kubernetes.io/limit-rpm: "3000"
    # 白名单
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
    # 基础认证
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
    # 代理配置
    nginx.ingress.kubernetes.io/upstream-hash-by: "$request_uri"
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "route"
    nginx.ingress.kubernetes.io/session-cookie-max-age: "172800"
    # 自定义错误页
    nginx.ingress.kubernetes.io/custom-http-errors: "404,502,503"
    nginx.ingress.kubernetes.io/default-backend: "ingress-nginx/defaultbackend"
    # 禁用访问日志
    nginx.ingress.kubernetes.io/enable-access-log: "false"
    # 配置 Snippet（高级）
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: SAMEORIGIN";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
spec:
  ingressClassName: nginx
  rules:
  - host: api.demo.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-server
            port:
              number: 80
EOF

# 创建基础认证 Secret
kubectl create secret generic basic-auth -n demo \
  --from-literal=auth=admin:$(echo -n 'admin:Admin@123' | base64)
```

### 5.2 Istio 金丝雀发布（Canary Release）

```bash
# 部署 v2 版本
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server-v2
  namespace: demo
  labels:
    app: api-server
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-server
      version: v2
  template:
    metadata:
      labels:
        app: api-server
        version: v2
    spec:
      containers:
      - name: api-server
        image: 192.168.1.61/library/nginx:1.26-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# DestinationRule 定义版本子集
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule           # 目标服务策略
metadata:
  name: api-server-dr
  namespace: demo
spec:
  host: api-server
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1000    # 最大 TCP 连接数
      http:
        h2UpgradePolicy: DEFAULT
        http1MaxPendingRequests: 1024
        http2MaxRequests: 1024
        maxRequestsPerConnection: 100
    outlierDetection:           # 异常检测（熔断）
      consecutive5xxErrors: 5    # 连续 5xx 错误次数
      interval: 30s
      baseEjectionTime: 30s      # 熔断恢复时间
      maxEjectionPercent: 50     # 最大熔断比例
  subsets:
  - name: v1                    # 版本子集 v1
    labels:
      version: v1
  - name: v2                    # 版本子集 v2
    labels:
      version: v2
EOF

# VirtualService 实现 90/10 金丝雀流量分配
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server-vs
  namespace: demo
spec:
  hosts:
  - "api.demo.local"
  gateways:
  - demo-gateway
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: api-server
        subset: v2
        port:
          number: 80
      weight: 100
  - route:
    - destination:
        host: api-server
        subset: v1
        port:
          number: 80
      weight: 90
    - destination:
        host: api-server
        subset: v2
        port:
          number: 80
      weight: 10
EOF

# 测试金丝雀路由
# 普通请求 -> 90% 概率到 v1
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code} " http://192.168.1.54:31080/api/health
done
echo

# 带 Header 的请求 -> 100% 到 v2
curl -H "x-canary: true" http://192.168.1.54:31080/api/health
```

### 5.3 Istio mTLS 配置

```bash
# 设置命名空间级别的 mTLS 宽容模式（迁移过渡）
cat <<'EOF' | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication          # 对等认证策略
metadata:
  name: default
  namespace: demo
spec:
  mtls:
    mode: PERMISSIVE             # 宽容模式（同时接受 mTLS 和明文）
EOF

# 对特定工作负载启用严格 mTLS
cat <<'EOF' | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: api-server-mtls
  namespace: demo
spec:
  selector:
    matchLabels:
      app: api-server
  mtls:
    mode: STRICT
EOF

# 验证 mTLS 状态
kubectl get peerauthentication -n demo

# 查看 mTLS 统计
kubectl exec -it deploy/api-server -n demo -c istio-proxy -- \
  pilot-agent request GET stats | grep ssl | head -20
```

### 5.4 AuthorizationPolicy 访问控制

```bash
# 只允许 web-frontend 访问 api-server
cat <<'EOF' | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy        # 授权策略
metadata:
  name: api-server-authz
  namespace: demo
spec:
  selector:
    matchLabels:
      app: api-server
  action: ALLOW                   # 允许策略
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/demo/sa/web-frontend"
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
EOF

# 拒绝特定路径的访问
cat <<'EOF' | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-server-deny-admin
  namespace: demo
spec:
  selector:
    matchLabels:
      app: api-server
  action: DENY
  rules:
  - to:
    - operation:
        paths: ["/api/admin/*"]
    when:
    - key: request.headers[x-user-role]
      notValues: ["admin"]
EOF

# 列出所有策略
kubectl get authorizationpolicy -n demo
```

### 5.5 Istio 故障注入

```bash
# 注入 HTTP 503 错误（10% 概率）
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server-fault
  namespace: demo
spec:
  hosts:
  - api-server
  http:
  - fault:
      abort:
        percentage:
          value: 10
        httpStatus: 503
    route:
    - destination:
        host: api-server
        port:
          number: 80
EOF

# 注入 500ms 延迟（对特定用户）
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server-delay
  namespace: demo
spec:
  hosts:
  - api-server
  http:
  - match:
    - headers:
        x-test-user:
          exact: "true"
    fault:
      delay:
        percentage:
          value: 100
        fixedDelay: 2s
    route:
    - destination:
        host: api-server
        port:
          number: 80
  - route:
    - destination:
        host: api-server
        port:
          number: 80
EOF

# 清除故障注入
kubectl delete virtualservice api-server-fault api-server-delay -n demo
```

---

## 6. 验证与测试

### 6.1 Ingress 验证

```bash
# 配置本地 hosts（在客户端机器上）
# 192.168.1.54 api.demo.local web.demo.local

# 测试 HTTP 路由
curl -v http://192.168.1.54:30080/ -H "Host: web.demo.local"
curl -v http://192.168.1.54:30080/api/health -H "Host: api.demo.local"

# 测试 HTTPS 路由
curl -k https://192.168.1.54:30443/ -H "Host: web.demo.local"
curl -k https://192.168.1.54:30443/api/health -H "Host: api.demo.local"

# 测试限流（超过 100 rps 应返回 503）
ab -n 200 -c 50 http://192.168.1.54:30080/api/health -H "Host: api.demo.local"

# 测试 CORS
curl -I -X OPTIONS http://192.168.1.54:30080/api/health \
  -H "Host: api.demo.local" \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: POST"

# 测试基础认证
curl -u admin:Admin@123 http://192.168.1.54:30080/api/health -H "Host: api.demo.local"
curl http://192.168.1.54:30080/api/health -H "Host: api.demo.local"
# 预期：未认证返回 401

# 检查 Ingress Controller 日志
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

### 6.2 Istio 验证

```bash
# 验证 Sidecar 注入
kubectl get pods -n demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# 验证 mTLS
kubectl exec -it deploy/api-server -n demo -c istio-proxy -- \
  openssl s_client -connect api-server.demo.svc.cluster.local:80 -showcerts </dev/null 2>/dev/null | grep "Verify return code"

# 验证流量路由
for i in $(seq 1 10); do
  kubectl exec -it deploy/web-frontend -n demo -c istio-proxy -- \
    curl -s api-server.demo.svc.cluster.local/api/health | head -1
done

# 查看 Envoy 配置
kubectl exec -it deploy/api-server -n demo -c istio-proxy -- \
  pilot-agent request GET clusters | grep api-server

# 查看 Proxy Status
istioctl proxy-status

# 查看配置分发
istioctl analyze -A

# 验证 Kiali
# 访问 http://192.168.1.54:32001
# 查看 Graph -> Service Graph
# 查看 Applications -> api-server -> Traffic
```

### 6.3 金丝雀发布验证

```bash
# 发送 100 次请求统计版本分布
for i in $(seq 1 100); do
  curl -s http://192.168.1.54:31080/api/health -H "Host: api.demo.local" -H "x-canary: false"
done | grep -c "v1"
# 预期约 90 次

# 调整流量比例到 50/50
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server-vs
  namespace: demo
spec:
  hosts:
  - "api.demo.local"
  gateways:
  - demo-gateway
  http:
  - route:
    - destination:
        host: api-server
        subset: v1
        port:
          number: 80
      weight: 50
    - destination:
        host: api-server
        subset: v2
        port:
          number: 80
      weight: 50
EOF

# 全量切换到 v2
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server-vs
  namespace: demo
spec:
  hosts:
  - "api.demo.local"
  gateways:
  - demo-gateway
  http:
  - route:
    - destination:
        host: api-server
        subset: v2
        port:
          number: 80
      weight: 100
EOF
```

---

## 7. CKA/CKS 考点融入

### 7.1 CKA 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Ingress 资源 | Ingress API 字段、pathType（Prefix/Exact/ImplementationSpecific） | 4.3 节 |
| IngressClass | ingressClassName 字段、默认 IngressClass | 4.3 节 |
| Service 类型 | ClusterIP/NodePort/LoadBalancer/ExternalName | 4.2 节 |
| 网络策略 | NetworkPolicy 限制 Pod 间通信 | 5.4 节 |
| 标签与选择器 | Service selector、Deployment matchLabels | 4.2 节 |
| 滚动更新 | rollout restart、Deployment 策略 | 4.5.3 节 |

### 7.2 CKS 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| mTLS 加密 | PeerAuthentication STRICT 模式 | 5.3 节 |
| 网络策略 | AuthorizationPolicy 细粒度访问控制 | 5.4 节 |
| TLS 终止 | cert-manager 自动证书管理 | 4.4 节 |
| 安全注解 | 安全 Header 注解（CSP、X-Frame-Options） | 5.1 节 |
| 基础认证 | Secret 管理认证信息 | 5.1 节 |
| 审计日志 | Ingress 访问日志、Istio 访问日志 | 6.1 节 |
| 网络隔离 | Sidecar 网络隔离、Egress 控制 | 5.4 节 |

### 7.3 考试模拟命令

```bash
# CKA: 创建 Ingress 路由（考试高频）
kubectl create ingress test-ingress \
  --class=nginx \
  --rule="test.local/*=test-svc:80" \
  --annotation="nginx.ingress.kubernetes.io/rewrite-target=/"

# CKS: 创建 NetworkPolicy 只允许特定命名空间访问
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
  namespace: demo
spec:
  podSelector:
    matchLabels:
      app: api-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 8080
EOF

# CKS: 检查 Pod 安全标准
kubectl get podsecuritypolicy
kubectl label namespace demo pod-security.kubernetes.io/enforce=restricted --overwrite
```

---

## 8. 高频面试题

### Q1: Ingress Controller 的工作原理是什么？（难度：中等）

**答案：** Ingress Controller 是一个反向代理服务器，它持续 watch Kubernetes API Server 中 Ingress 资源和 Service/Endpoint 的变化。当检测到 Ingress 规则变化时，Controller 会动态更新其内部配置（如 Nginx 的 nginx.conf）。以 Nginx Ingress Controller 为例，它通过 Lua 模块实现了配置的热加载，无需重启 Nginx 进程。请求到达时，Nginx 根据 Host 头和 URL 路径匹配 Ingress 规则，将请求转发到对应的 Service 后端 Pod。整个流程是：Client -> DNS -> LoadBalancer/NodePort -> Ingress Controller -> Service -> Pod。Ingress Controller 本质上是一个七层负载均衡器，工作在 HTTP/HTTPS 层面，相比四层的 Service 提供了更丰富的路由能力。

### Q2: Ingress 的 pathType 有哪几种？区别是什么？（难度：简单）

**答案：** pathType 有三种类型：**Prefix** 按路径前缀匹配，类似 Nginx 的 location /path/，匹配 /path、/path/xxx 等；**Exact** 精确匹配，只有完全相同的路径才匹配；**ImplementationSpecific** 由具体的 Ingress Controller 决定匹配行为，不同 Controller 实现可能不同。在实际使用中，Prefix 最常用但需要注意路径分割问题（如 /api 会匹配 /api、/api/v1、/apixxx），建议使用 Prefix 时路径以 / 结尾。Exact 适用于精确路由场景。ImplementationSpecific 在多 Controller 环境中可能导致行为不一致，不推荐使用。

### Q3: Istio 的数据面和控制面分别是什么？如何协作？（难度：中等）

**答案：** Istio 采用经典的数据面-控制面分离架构。**控制面**由 istiod 统一提供，它合并了 Pilot（流量管理）、Citadel（证书管理）和 Galley（配置管理）三个组件。istiod 通过 xDS 协议（CDS/EDS/LDS/RDS/SDS）向数据面下发配置。**数据面**由 Envoy 代理组成，以 Sidecar 形式注入到每个应用 Pod 中，拦截所有入站和出站流量。协作流程：应用 Pod 启动时，istioctl 或 webhook 自动注入 Envoy Sidecar 容器；Envoy 启动后通过 gRPC 连接 istiod，获取服务发现、路由规则、证书等配置；当 VirtualService 或 DestinationRule 变更时，istiod 增量推送配置更新给受影响的 Envoy 实例；Envoy 根据最新配置执行流量路由、负载均衡、mTLS 等策略。

### Q4: 什么是 mTLS？Istio 如何实现自动证书管理？（难度：中等）

**答案：** mTLS（Mutual TLS，双向 TLS）是指通信双方都需要出示证书并验证对方身份的 TLS 加密方式。在传统 TLS 中只有服务端出示证书，客户端验证服务端；而 mTLS 中客户端也需要出示证书，服务端同样验证客户端。Istio 通过 Citadel（集成在 istiod 中）实现自动证书管理：Citadel 作为内部 CA 运行，为每个工作负载签发 SPIFFE 格式的证书（格式为 spiffe://cluster.local/ns/namespace/sa/serviceaccount）；证书有效期默认 24 小时，Envoy 会在证书过期前自动向 istiod 续期；证书和私钥通过 SDS（Secret Discovery Service）动态下发，不需要挂载 Secret Volume。这种机制实现了零信任网络模型，所有服务间通信默认加密且双向认证。

### Q5: Istio VirtualService 和 DestinationRule 的区别是什么？（难度：中等）

**答案：** VirtualService 定义"流量如何路由"，DestinationRule 定义"到达目标后的策略"。具体来说，VirtualService 负责路由决策：基于 Host、Header、URI 等条件将流量路由到不同的服务版本，实现金丝雀发布、A/B 测试、流量镜像等。DestinationRule 负责目标策略：定义服务的负载均衡策略（Round Robin/Random/Locality）、连接池设置（maxConnections、http2MaxRequests）、熔断器（outlierDetection）以及版本子集（subsets）定义。两者配合使用：VirtualService 引用 DestinationRule 中定义的 subset 来实现版本路由。没有 DestinationRule 的 subset 定义，VirtualService 无法实现基于版本的流量分配。

### Q6: 如何实现 Istio 金丝雀发布？有哪些策略？（难度：困难）

**答案：** Istio 金丝雀发布通过 VirtualService 的 weight 字段实现流量按比例分配。**基于权重的金丝雀**：在 VirtualService 的 route 中设置 v1 weight=90, v2 weight=10，逐步调整比例直到全量切换。**基于 Header 的路由**：通过 match 条件匹配特定请求头（如 x-canary: true），将特定用户路由到新版本，适合内部测试。**基于用户身份的路由**：匹配 JWT claims 中的用户信息，实现灰度发布。**流量镜像**：使用 mirror 字段将生产流量复制一份到新版本，新版本的响应被丢弃，用于验证新版本是否正常处理请求。**会话亲和性**：结合 DestinationRule 的 consistentHash 实现同一用户始终路由到同一版本。金丝雀发布的关键指标监控：错误率、延迟 P99、CPU/内存使用率，建议配合 Prometheus + Grafana 实现自动化金丝雀分析。

### Q7: Ingress 和 Istio Gateway 有什么区别？如何选择？（难度：困难）

**答案：** Ingress 是 Kubernetes 原生的南北流量入口标准，Istio Gateway 是 Istio 服务网格的入口网关。主要区别：**协议支持**：Ingress 主要支持 HTTP/HTTPS，扩展支持 TCP/UDP（通过自定义注解）；Istio Gateway 原生支持 HTTP/HTTPS/TCP/TLS/gRPC 等多种协议。**功能丰富度**：Ingress 功能依赖 Controller 实现，不同 Controller 功能差异大；Istio Gateway 与 VirtualService/DestinationRule 配合，提供流量管理、故障注入、重试、超时等丰富功能。**TLS 管理**：Ingress 依赖 cert-manager 等外部组件；Istio Gateway 内置 mTLS 支持。**适用场景**：Ingress 适合不需要服务网格的简单场景，Istio Gateway 适合需要服务网格流量管理的复杂微服务架构。**推荐方案**：生产环境中两者可以协同使用，Ingress 处理外部 TLS 终止和基础路由，Istio Gateway 处理网格内部的高级流量管理。

### Q8: Envoy Sidecar 注入对应用有什么影响？（难度：中等）

**答案：** Sidecar 注入对应用有多方面影响：**资源开销**：每个 Pod 额外消耗约 100-200m CPU 和 128-256Mi 内存（Envoy 代理），对于资源受限的环境需要评估；**启动延迟**：Pod 启动时间增加约 2-5 秒（init container 配置 iptables 规则 + Envoy 启动）；**网络延迟**：所有流量经过 Envoy 代理转发，增加约 1-2ms 的延迟；**流量劫持**：通过 iptables 将 Pod 的所有入站和出站流量重定向到 Envoy 的 15001（出站）和 15006（入站）端口；**调试复杂度**：网络问题排查需要同时考虑应用日志和 Envoy 日志，增加了排障难度。最佳实践：为 Envoy 设置合理的资源 requests/limits；在 Istio 纳管命名空间中避免使用 hostNetwork；使用 `istioctl proxy-status` 检查配置同步状态；生产环境建议设置 Envoy 的 access log。

### Q9: 如何排查 Ingress 502/503/504 错误？（难度：中等）

**答案：** 502 Bad Gateway 表示 Ingress Controller 无法连接到后端 Service。排查步骤：检查后端 Pod 是否正常运行（`kubectl get pods`）；检查 Service Endpoints 是否正确（`kubectl get endpoints`）；检查 Service selector 是否匹配 Pod labels；检查后端 Pod 的 readinessProbe 是否通过。503 Service Unavailable 可能原因：后端 Service 无可用 Endpoints；Ingress Controller 自身异常；限流配置触发。504 Gateway Timeout 表示后端响应超时，排查步骤：检查 `proxy-read-timeout` 和 `proxy-send-timeout` 注解配置；检查后端服务处理时间是否超过超时阈值；检查网络是否存在丢包或延迟。通用排查命令：`kubectl describe ingress <name>`、`kubectl logs -n ingress-nginx <controller-pod>`、`kubectl exec -it <controller-pod> -n ingress-nginx -- cat /etc/nginx/nginx.conf`。

### Q10: Istio 的流量故障注入有什么用途？（难度：中等）

**答案：** Istio 故障注入是混沌工程的重要工具，用于验证服务的弹性和容错能力。**HTTP Abort**：注入 HTTP 错误码（如 503），模拟服务不可用场景，验证客户端的重试机制和熔断器是否正常工作。**HTTP Delay**：注入固定延迟，模拟网络抖动或服务响应变慢，验证超时配置和级联故障防护。**百分比控制**：可以设置故障注入的百分比（如 10% 的请求返回 503），模拟间歇性故障。**条件匹配**：可以基于请求头、URI 等条件对特定流量注入故障，实现精准的混沌测试。典型使用场景：在上线前验证服务的容错能力；定期进行混沌工程演练；验证熔断器、重试、超时等弹性配置是否生效；配合监控告警验证告警是否及时触发。故障注入通过 VirtualService 的 fault 字段配置，测试完成后应及时删除配置。

### Q11: cert-manager 的证书签发流程是什么？（难度：中等）

**答案：** cert-manager 的证书签发流程如下：1）用户创建 Certificate CRD，指定域名、Issuer 和 Secret 名称；2）cert-manager Controller 检测到 Certificate 资源，创建对应的 CertificateRequest CR；3）根据 Issuer 类型（ACME/CA/Vault/SelfSigned），Controller 向对应的签发者发起证书签发请求；4）对于 Let's Encrypt ACME：Controller创建 Challenge 资源，通过 HTTP-01 或 DNS-01 验证域名所有权，验证通过后 ACME Server 签发证书；5）Controller 将签发的证书和私钥存储到指定的 Secret 中（tls.crt 和 tls.key）；6）Ingress Controller 自动从 Secret 中加载证书。证书续期：cert-manager 在证书到期前 30 天自动发起续期，整个流程对用户透明。生产环境建议使用 DNS-01 验证方式（支持通配符证书）和 Let's Encrypt Production 环境。

### Q12: 如何实现 Ingress 的灰度发布？（难度：困难）

**答案：** Nginx Ingress Controller 支持通过 Canary 注解实现灰度发布。创建两个 Ingress 资源指向同一个 Host，一个为常规 Ingress，另一个为 Canary Ingress。Canary Ingress 需要添加 `nginx.ingress.kubernetes.io/canary: "true"` 注解，然后通过以下策略控制灰度流量：**基于权重**：`nginx.ingress.kubernetes.io/canary-weight: "10"` 将 10% 的流量路由到 Canary 版本；**基于 Header**：`nginx.ingress.kubernetes.io/canary-by-header: "x-canary"` 匹配特定 Header 值路由到 Canary；**基于 Cookie**：`nginx.ingress.kubernetes.io/canary-by-cookie: "canary"` 基于 Cookie 值路由。注意事项：Canary Ingress 的规则优先级高于常规 Ingress；多个灰度策略不能同时使用（权重和 Header 不能共存）；Canary Ingress 不支持权重为 0 或 100。相比 Istio 的金丝雀发布，Ingress Canary 功能较简单，不支持基于版本标签的路由和流量镜像。

### Q13: Istio 的 AuthorizationPolicy 和 K8s NetworkPolicy 有什么区别？（难度：困难）

**答案：** 两者都是网络访问控制策略，但工作层面和功能不同。**NetworkPolicy** 工作在 L3/L4 层面（IP 和端口），由 kubelet 和 CNI 插件（如 Calico、Cilium）执行，控制 Pod 间的网络连通性，不支持 HTTP 层面的控制（如路径、方法、Header）。**AuthorizationPolicy** 工作在 L7 层面，由 Envoy Sidecar 执行，支持基于 HTTP 方法、路径、Header、JWT claims 等细粒度访问控制。关键区别：执行位置不同（CNI vs Envoy Sidecar）；控制粒度不同（IP/Port vs HTTP 属性）；NetworkPolicy 适用于所有 Pod（包括未注入 Sidecar 的），AuthorizationPolicy 仅适用于注入了 Sidecar 的 Pod；NetworkPolicy 是 K8s 原生资源，AuthorizationPolicy 是 Istio CRD。生产环境推荐两者配合使用：NetworkPolicy 作为基础网络隔离，AuthorizationPolicy 作为应用层精细访问控制。

### Q14: 如何监控 Ingress Controller 和 Istio 的性能？（难度：中等）

**答案：** Ingress Controller 监控：Nginx Ingress Controller 内置 Prometheus metrics 端点，关键指标包括 `nginx_ingress_controller_requests`（请求总数）、`nginx_ingress_controller_request_duration_seconds`（请求延迟）、`nginx_ingress_controller_upstream_connect_time`（上游连接时间）。Istio 监控：Envoy Sidecar 暴露丰富的 metrics，关键指标包括 `istio_requests_total`（请求总数）、`istio_request_duration_seconds`（请求延迟）、`istio_tcp_connections_opened`（TCP 连接数）。监控方案：部署 Prometheus + Grafana；使用 Nginx Ingress Controller 官方 Dashboard；使用 Istio 官方 Grafana Dashboards（包含 Mesh、Service、Workload 三个维度）；配置告警规则（错误率 > 1%、P99 延迟 > 500ms、Upstream 连接失败）。日志收集：Ingress Controller 的 access log 默认输出到 stdout，可通过 Filebeat/Fluentd 收集到 ELK；Istio 的 access log 需要在 Envoy 中配置 `accessLog` 或使用 Telemetry API。

### Q15: 生产环境中 Ingress 和 Istio 的协同方案是什么？（难度：困难）

**答案：** 生产环境推荐 Ingress + Istio 协同架构。**方案一：Ingress 作为外部入口，Istio Gateway 作为内部网关**。外部流量通过 Nginx Ingress Controller 进入集群，Ingress 负责 TLS 终止、WAF、DDoS 防护、限流等边缘功能；流量到达 Istio Gateway 后进入服务网格，享受 mTLS、流量管理、可观测性等网格能力。这种方案的优势是充分利用了 Ingress Controller 的成熟生态（如 ModSecurity WAF）和 Istio 的服务网格能力。**方案二：Istio Gateway 替代 Ingress Controller**。直接使用 Istio Ingress Gateway 作为集群入口，简化架构但需要自行实现 WAF 等安全功能。**方案三：多 Ingress Controller**。外部使用 Nginx Ingress（公网流量），内部使用 Istio Gateway（内部服务间通信）。推荐方案一，因为它在安全性和功能性之间取得了最佳平衡，且 Ingress Controller 可以独立于 Istio 进行升级和维护。

---

## 9. 故障排查案例

### 案例 1：Ingress 返回 502 Bad Gateway

**现象：**
```
curl http://192.168.1.54:30080/api/health -H "Host: api.demo.local"
<html>
<head><title>502 Bad Gateway</title></head>
<body><center>502 Bad Gateway</center></body>
</html>
```

**排查步骤：**
```bash
# 1. 检查后端 Pod 状态
kubectl get pods -n demo -l app=api-server
# 发现：api-server-xxx 0/1 Running（Readiness 探针失败）

# 2. 查看 Pod 事件
kubectl describe pod -l app=api-server -n demo | tail -20
# 发现：Readiness probe failed: Get "http://10.244.x.x:8080/": connection refused

# 3. 查看 Pod 日志
kubectl logs deploy/api-server -n demo --previous
# 发现：Caused by: java.net.BindException: Address already in use

# 4. 检查 Service Endpoints
kubectl get endpoints api-server -n demo
# 发现：无可用 Endpoints

# 5. 检查 Ingress Controller 日志
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=20 | grep 502
# 发现：upstream prematurely closed connection
```

**解决方案：**
应用启动失败导致端口未监听。修复应用配置后重启 Pod：
```bash
kubectl rollout restart deployment api-server -n demo
kubectl rollout status deployment api-server -n demo --timeout=120s
```

### 案例 2：Ingress 规则不生效，返回默认 404

**现象：**
```
curl http://192.168.1.54:30080/api/health -H "Host: api.demo.local"
default backend - 404
```

**排查步骤：**
```bash
# 1. 检查 Ingress 资源
kubectl get ingress -n demo
# 发现：demo-ingress 存在

# 2. 检查 IngressClass
kubectl describe ingress demo-ingress -n demo | grep -A 5 "Spec:"
# 发现：ingressClassName 字段为空

# 3. 检查 IngressClass 列表
kubectl get ingressclass
# 发现：存在 nginx IngressClass

# 4. 检查 Ingress Controller 日志
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
# 发现：no IngressClass matched, ignoring
```

**解决方案：**
Ingress 资源缺少 ingressClassName 字段，导致 Controller 忽略该规则：
```bash
kubectl patch ingress demo-ingress -n demo --type merge -p '{"spec":{"ingressClassName":"nginx"}}'
```

### 案例 3：cert-manager 证书签发失败

**现象：**
```bash
kubectl get certificate -n demo
# demo-tls   False   10m
kubectl describe certificate demo-tls -n demo
# Conditions: Ready: False, Reason: Issuing, Message: Waiting for CertificateRequest to complete
```

**排查步骤：**
```bash
# 1. 检查 CertificateRequest
kubectl get certificaterequest -n demo
# 发现：demo-tls-xxx Pending

# 2. 查看 cert-manager 日志
kubectl logs -n cert-manager deploy/cert-manager --tail=50
# 发现：Failed to create Order: 429 urn:ietf:params:acme:error:rateLimited

# 3. 检查 Challenge 状态
kubectl get challenges -n demo
# 发现：challenge 处于 pending 状态

# 4. 检查 Ingress 是否正确配置
kubectl get ingress -n demo
# 发现：Ingress 中未引用 cert-manager 管理的 Secret
```

**解决方案：**
Let's Encrypt 触发了速率限制。解决方案：
```bash
# 方案一：使用 Staging 环境测试
# 方案二：使用自签名 Issuer
kubectl get clusterissuer selfsigned-issuer -o yaml
# 确认 Issuer 存在且 Ready

# 方案三：等待速率限制重置（通常1小时）
# 修改 Certificate 使用自签名 Issuer
kubectl patch certificate demo-tls -n demo --type merge \
  -p '{"spec":{"issuerRef":{"name":"selfsigned-issuer","kind":"ClusterIssuer"}}}'
```

### 案例 4：Istio Sidecar 注入失败

**现象：**
```bash
kubectl get pods -n demo
# api-server-xxx  1/1 Running  （只有1个容器，Sidecar 未注入）
```

**排查步骤：**
```bash
# 1. 检查命名空间标签
kubectl get namespace demo --show-labels
# 发现：缺少 istio-injection=enabled 标签

# 2. 检查 webhook 配置
kubectl get mutatingwebhookconfigurations | grep istio
# 发现：istio-sidecar-injector 存在

# 3. 检查 webhook 服务
kubectl get svc -n istio-system | grep sidecar-injector
# 发现：服务存在且 Endpoints 正常

# 4. 手动检查注入结果
kubectl get pod api-server-xxx -n demo -o yaml | grep -c "istio-proxy"
# 发现：0（未注入）
```

**解决方案：**
```bash
# 添加命名空间标签
kubectl label namespace demo istio-injection=enabled --overwrite

# 重启 Pod 触发注入
kubectl rollout restart deployment api-server -n demo

# 验证注入
kubectl get pods -n demo
# 预期：api-server-xxx  2/2 Running
```

### 案例 5：Istio mTLS 导致服务间通信失败

**现象：**
```bash
kubectl logs deploy/web-frontend -n demo --tail=20
# Error: upstream connect error or disconnect/reset before headers. reset reason: connection failure
```

**排查步骤：**
```bash
# 1. 检查 PeerAuthentication 策略
kubectl get peerauthentication -n demo -o yaml
# 发现：api-server 设置了 STRICT mTLS

# 2. 检查调用方是否注入 Sidecar
kubectl get pod -l app=web-frontend -n demo -o jsonpath='{.spec.containers[*].name}'
# 发现：只有 web-frontend（缺少 istio-proxy）

# 3. 检查 DestinationRule
kubectl get destinationrule -n demo
# 发现：缺少 api-server 的 DestinationRule

# 4. 查看 Envoy 日志
kubectl logs deploy/web-frontend -n demo -c istio-proxy --tail=20
# 发现：TLS error: 268435456:SSL error
```

**解决方案：**
调用方未注入 Sidecar，无法完成 mTLS 握手：
```bash
# 确保调用方也注入了 Sidecar
kubectl label namespace demo istio-injection=enabled --overwrite
kubectl rollout restart deployment web-frontend -n demo

# 或者临时将 mTLS 设为 PERMISSIVE 模式
kubectl patch peerauthentication api-server-mtls -n demo --type merge \
  -p '{"spec":{"mtls":{"mode":"PERMISSIVE"}}}'
```

### 案例 6：Istio VirtualService 规则不生效

**现象：**
```bash
# 设置了金丝雀 90/10，但所有流量都到了 v1
for i in $(seq 1 20); do
  curl -s http://192.168.1.54:31080/api/health -H "Host: api.demo.local"
done
# 全部返回 v1 响应
```

**排查步骤：**
```bash
# 1. 检查 VirtualService 配置
kubectl get virtualservice api-server-vs -n demo -o yaml
# 发现：配置看起来正确

# 2. 检查 DestinationRule
kubectl get destinationrule api-server-dr -n demo -o yaml
# 发现：subsets 中 v2 的 labels 为 version: v2

# 3. 检查 v2 Pod 的 labels
kubectl get pod -l app=api-server -n demo --show-labels
# 发现：v2 Pod 的 version 标签为 "v2.0" 而非 "v2"

# 4. 使用 istioctl 分析
istioctl analyze -n demo
# 发现：Warning: No matching subset for v2 in DestinationRule
```

**解决方案：**
DestinationRule 的 subset labels 与 Pod labels 不匹配：
```bash
# 修正 v2 Pod 的标签
kubectl label pod -l app=api-server,version=v2.0 version=v2 --overwrite -n demo

# 或者修正 DestinationRule
kubectl patch destinationrule api-server-dr -n demo --type json \
  -p='[{"op":"replace","path":"/spec/subsets/1/labels/version","value":"v2.0"}]'
```

### 案例 7：Kiali 无法显示服务拓扑图

**现象：**
```
访问 Kiali 控制台，服务拓扑图为空，无任何节点和连线。
```

**排查步骤：**
```bash
# 1. 检查 Kiali Pod 状态
kubectl get pods -n istio-system -l app=kiali
# 发现：kiali Running

# 2. 检查 Kiali 配置
kubectl get configmap kiali -n istio-system -o yaml | grep -A 5 "prometheus"
# 发现：prometheus.url 配置错误

# 3. 检查 Prometheus 连通性
kubectl exec -it deploy/kiali-server -n istio-system -- curl -s http://prometheus-server.monitoring.svc:9090/api/v1/status/config
# 发现：Connection refused

# 4. 检查 Prometheus 实际地址
kubectl get svc -A | grep prometheus
# 发现：Prometheus 在 monitoring 命名空间，但 Service 名称不同
```

**解决方案：**
```bash
# 更新 Kiali 配置指向正确的 Prometheus 地址（使用离线 Chart）
helm upgrade kiali-server /root/charts/kiali-server-1.80.0.tgz \
  --namespace istio-system \
  --reuse-values \
  --set external_services.prometheus.url="http://prometheus-operated.monitoring.svc:9090"

# 等待几分钟后刷新 Kiali 控制台
```

### 案例 8：Ingress Controller Pod 频繁 OOMKilled

**现象：**
```bash
kubectl get pods -n ingress-nginx
# ingress-nginx-controller-xxx  0/1 CrashLoopBackOff
kubectl describe pod -n ingress-nginx -l app.kubernetes.io/component=controller
# Last State: Terminated, Reason: OOMKilled
```

**排查步骤：**
```bash
# 1. 检查当前资源限制
kubectl get deploy ingress-nginx-controller -n ingress-nginx -o yaml | grep -A 10 "resources:"
# 发现：limits.memory=256Mi

# 2. 检查 Ingress 规则数量
kubectl get ingress --all-namespaces | wc -l
# 发现：200+ Ingress 规则

# 3. 检查节点内存使用
kubectl top nodes
# 发现：Worker 节点内存使用率 85%

# 4. 检查历史 OOM 事件
kubectl get events -n ingress-nginx --field-selector type=Warning | grep OOMKilled
```

**解决方案：**
```bash
# 增大 Ingress Controller 内存限制（使用离线 Chart）
helm upgrade ingress-nginx /root/charts/ingress-nginx-4.10.1.tgz \
  --namespace ingress-nginx \
  --reuse-values \
  --set controller.resources.limits.memory=1Gi \
  --set controller.resources.requests.memory=512Mi

# 优化：减少不必要的 Ingress 规则，合并相似路由
# 优化：启用 keep-alive 减少连接开销
```

---

## 10. ExternalDNS自动DNS管理（进阶）

> ExternalDNS自动将Ingress/Service的DNS记录同步到DNS提供商。
> 
> **适用场景**: Ingress自动配置DNS、TLS证书自动化
> **支持DNS提供商**: CoreDNS、PowerDNS、Route53、Cloudflare、阿里云DNS等

### 10.1 ExternalDNS架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes                               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Ingress   │    │  Service    │    │  Gateway    │     │
│  │ (host: a.b) │    │(type:LB)    │    │  (HTTPRoute)│     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            │                                │
│                            ▼                                │
│              ┌─────────────────────────┐                   │
│              │     ExternalDNS         │                   │
│              │  (监控Ingress/Service)  │                   │
│              └───────────┬─────────────┘                   │
└──────────────────────────┼──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    DNS提供商                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   CoreDNS   │    │  Cloudflare │    │   Route53   │     │
│  │   (内网)    │    │   (公网)    │    │   (AWS)     │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### 10.2 离线部署ExternalDNS

#### 10.2.1 镜像清单

```bash
# ExternalDNS镜像
registry.k8s.io/external-dns/external-dns:v0.14.0

# 推送到Harbor
HARBOR="192.168.1.61:80"
docker pull registry.k8s.io/external-dns/external-dns:v0.14.0
docker tag registry.k8s.io/external-dns/external-dns:v0.14.0 \
  ${HARBOR}/library/external-dns:v0.14.0
docker push ${HARBOR}/library/external-dns:v0.14.0
```

#### 10.2.2 部署到CoreDNS（内网DNS）

```yaml
# external-dns-coredns.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "pods"]
    verbs: ["get", "watch", "list"]
  - apiGroups: ["extensions", "networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "watch", "list"]
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["httproutes"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
  - kind: ServiceAccount
    name: external-dns
    namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: 192.168.1.61:80/library/external-dns:v0.14.0
          args:
            - --source=ingress
            - --source=service
            - --provider=coredns
            - --coredns-endpoint=http://coredns:8080
            - --domain-filter=cluster.local
            - --policy=sync  # 同步模式，删除不在K8s中的记录
            - --registry=txt  # 使用TXT记录跟踪
            - --txt-owner-id=k8s
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
```

### 10.3 Ingress自动DNS示例

```yaml
# 创建Ingress，ExternalDNS自动创建DNS记录
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    # ExternalDNS会自动创建 myapp.example.com 的DNS记录
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
    # 可选：指定TTL
    external-dns.alpha.kubernetes.io/ttl: "60"
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

### 10.4 与cert-manager集成

```yaml
# Ingress + ExternalDNS + cert-manager 自动TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-tls-ingress
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

**自动化流程**:
```
1. 创建Ingress
2. ExternalDNS自动创建DNS记录 (myapp.example.com -> Ingress IP)
3. cert-manager自动申请TLS证书
4. Ingress Controller使用证书提供HTTPS服务
```

---

## 11. API Gateway技术选型（进阶）

> API Gateway是南北流量的第三种方案，独立于Ingress和Service Mesh。
> 
> **适用场景**: API管理、认证授权、限流熔断、插件扩展
> **主流方案**: APISIX、Kong、Envoy Gateway

### 11.1 三种南北流量方案对比

| 方案 | 定位 | 优势 | 劣势 | 适用场景 |
|------|------|------|------|----------|
| **Ingress** | K8s原生 | 简单、标准化 | 功能有限 | 基础路由 |
| **Service Mesh Gateway** | Mesh扩展 | 统一东西/南北 | 复杂度高 | 已有Mesh环境 |
| **API Gateway** | 独立产品 | 功能丰富、插件多 | 额外运维 | API管理、限流 |

### 11.2 APISIX简介

**Apache APISIX** 是云原生API Gateway，特性：
- 动态路由、负载均衡
- 限流、熔断、重试
- 认证（JWT、KeyAuth、OIDC）
- 可观测性（Prometheus、SkyWalking）
- 插件热加载

```yaml
# APISIX部署示例（简要）
apiVersion: gateway.apisix.apache.org/v2
kind: ApisixRoute
metadata:
  name: myapp-route
spec:
  http:
    - name: myapp
      match:
        paths:
          - /api/*
        methods:
          - GET
          - POST
      backends:
        - serviceName: myapp
          servicePort: 80
      plugins:
        - name: limit-req
          enable: true
          config:
            rate: 100
            burst: 200
        - name: jwt-auth
          enable: true
```

### 11.3 Kong简介

**Kong** 是成熟的API Gateway，特性：
- 企业级支持（Kong Enterprise）
- 丰富的插件生态
- Konnect云托管
- Ingress Controller支持

```yaml
# Kong Ingress示例
apiVersion: configuration.konghq.com/v1
kind: KongIngress
metadata:
  name: myapp-kong
proxy:
  path: /api
  retries: 3
route:
  strip_path: true
  plugins:
    - name: rate-limiting
      config:
        minute: 100
        policy: local
    - name: jwt
      config:
        secret_is_base64: false
```

### 11.4 选型决策树

```
需要API管理功能（限流、认证、文档）？
├── 是 → API Gateway
│   ├── 开源优先 → APISIX
│   └── 企业支持 → Kong
└── 否 → 已有Service Mesh？
    ├── 是 → Istio Gateway / Gateway API
    └── 否 → Ingress-Nginx
```

---

## 12. 生产环境建议

### 12.1 Ingress 生产配置清单

```yaml
# 生产级 Ingress Controller Helm Values
controller:
  replicaCount: 3                          # 高可用，至少 3 副本
  minAvailable: 2                          # PDB 保障
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
  config:
    proxy-body-size: "100m"                # 根据业务调整
    proxy-connect-timeout: "10"
    proxy-read-timeout: "300"
    proxy-send-timeout: "300"
    keep-alive: "75"                       # Keep-alive 超时
    upstream-keepalive-connections: "100"  # 上游 keep-alive 连接数
    upstream-keepalive-requests: "10000"   # 每个 keep-alive 连接的最大请求数
    use-forwarded-headers: "true"          # 传递真实客户端 IP
    compute-full-forwarded-for: "true"
    forwarded-for-header: "X-Forwarded-For"
    enable-opentracing: "true"             # 链路追踪
    zipkin-collector-host: "tempo.monitoring.svc"
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/component
              operator: In
              values:
              - controller
          topologyKey: kubernetes.io/hostname
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/component: controller
```

### 12.2 Istio 生产配置清单

```yaml
# 生产级 Istio 配置建议
spec:
  profile: minimal
  values:
    global:
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        accessLogFile: /dev/stdout           # 开启访问日志
        accessLogEncoding: JSON               # JSON 格式便于日志收集
        logLevel: warning
        tracer: zipkin                        # 链路追踪
      proxyInit:
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
  components:
    pilot:
      k8s:
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi
        replicas: 3                          # istiod 高可用
        hpaSpec:
          minReplicas: 3
          maxReplicas: 10
    ingressGateways:
    - name: istio-ingressgateway
      k8s:
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        replicas: 2
        hpaSpec:
          minReplicas: 2
          maxReplicas: 5
```

### 12.3 生产最佳实践总结

| 领域 | 建议 |
|------|------|
| **高可用** | Ingress Controller 至少 3 副本 + PDB；istiod 至少 3 副本 |
| **资源规划** | Envoy Sidecar 每个 Pod 额外 100-200m CPU + 128-256Mi 内存 |
| **TLS 管理** | 使用 cert-manager + Let's Encrypt Production；证书自动续期 |
| **安全加固** | 启用 mTLS STRICT 模式；配置 AuthorizationPolicy 最小权限原则 |
| **监控告警** | Ingress Controller metrics + Istio metrics 接入 Prometheus |
| **日志收集** | Envoy access log（JSON 格式）-> Fluentd -> Elasticsearch |
| **金丝雀发布** | 使用 Istio VirtualService weight 逐步切换，配合自动化指标分析 |
| **故障注入** | 仅在测试环境使用，生产环境禁止配置 fault 注入 |
| **网络策略** | NetworkPolicy（L3/L4）+ AuthorizationPolicy（L7）双层防护 |
| **升级策略** | Istio 升级使用 canary 升级模式，先升级控制面再逐步升级数据面 |
| **性能优化** | 合理设置连接池（maxConnections、http2MaxRequests）；启用 keep-alive |
| **灾备** | Ingress Controller 跨可用区部署；istiod 跨可用区部署 |

---

## 13. 2026技术趋势 — Sidecarless服务网格

> 📌 **2026技术趋势** — Sidecarless 服务网格代表了服务网格架构的下一代演进方向，旨在解决传统 Sidecar 模式的资源开销和运维复杂性问题。

### 11.1 趋势概述

📌 **2026技术趋势**

在模块 4.5 中我们学习了传统 Istio Sidecar 模式（参见 [4.5.2 安装 Istio](#452-安装-istiominimal-配置适配-master-2c4g-节点) 和 [4.5.3 为命名空间启用 Istio Sidecar 自动注入](#453-为命名空间启用-istio-sidecar-自动注入)），每个 Pod 都需要注入一个 Envoy Sidecar 代理。这种模式虽然功能强大，但在大规模场景下面临显著的资源挑战：

**Sidecar 模式的资源痛点（量化分析）：**

| 指标 | 数值 | 说明 |
|------|------|------|
| 单个 Envoy Sidecar 内存 | 50-200MB | 取决于配置复杂度和连接数 |
| 单个 Envoy Sidecar CPU | 100-500m | 正常负载下 |
| 1000 Pod 总内存开销 | **~100GB** | 仅 Sidecar 部分 |
| 1000 Pod 总 CPU 开销 | **~200 核** | 仅 Sidecar 部分 |
| Pod 启动延迟增加 | 2-5 秒 | init container + Envoy 启动 |
| 证书数量 | 1000+ | 每个 Pod 独立证书 |
| 配置分发开销 | 1000 x xDS | 每个 Envoy 独立接收配置 |

**KubeCon EU 2026 信号：** Ambient Mesh 和 Kmesh 已成为社区共识方向。Istio Ambient Mesh 在 1.22 版本达到 GA（General Availability），Kmesh（华为开源）已进入 CNCF Landscape。两者均采用 eBPF + Rust 技术栈，将代理从 Pod 级别提升到节点级别，大幅降低资源消耗。

### 11.2 Sidecar vs Sidecarless 对比表

📌 **2026技术趋势**

| 维度 | Sidecar (当前课程) | Sidecarless (2026趋势) |
|------|-------------------|----------------------|
| 代理位置 | 每个 Pod 内注入 | 节点级 DaemonSet |
| 内存/Pod | 50-200MB | 0（共享节点级） |
| 1000Pod 总开销 | ~100GB | ~20GB（降80%） |
| L4 加密 | mTLS per Pod（Envoy） | ztunnel（eBPF 内核态） |
| L7 策略 | Envoy Sidecar（全量） | Waypoint Proxy（按需） |
| 升级影响 | 滚动重启所有 Pod | 仅升级 DaemonSet |
| 配置分发 | 1000 x xDS 推送 | 节点级增量更新 |
| 代表方案 | Istio 传统模式 | Istio Ambient Mesh / Kmesh |
| 核心技术 | Envoy（C++） | eBPF + Rust |
| 生产成熟度 | 高（多年生产验证） | GA（Istio 1.22+） |
| 适用规模 | 中小规模（<500 Pod） | 大规模（1000+ Pod） |
| 调试复杂度 | 需进入每个 Pod 查看 | 节点级统一查看 |

> **与课程内容的关联：** 当前课程 [4.5.2 节](#452-安装-istiominimal-配置适配-master-2c4g-节点) 部署的 Istio 使用的是传统 Sidecar 模式。在生产环境规模扩大后，建议评估向 Ambient Mesh 迁移的可行性。

### 11.3 Istio Ambient Mesh 架构

📌 **2026技术趋势**

Ambient Mesh 将服务网格的数据面分为两层：**节点级 L4（ztunnel）** 和 **按需 L7（Waypoint Proxy）**，取代了每个 Pod 中的 Envoy Sidecar。

#### 核心组件

| 组件 | 功能 | 技术栈 | 部署方式 |
|------|------|--------|----------|
| **ztunnel** | 节点级 L4 代理，负责 mTLS、流量转发、可观测性 | Rust + eBPF | DaemonSet（每个节点一个） |
| **Waypoint Proxy** | 按需 L7 代理，负责高级路由、重试、故障注入等 | Envoy | 按命名空间/服务按需部署 |
| **istiod** | 控制面（与 Sidecar 模式共用） | Go | Deployment |

#### 架构对比图

**传统 Sidecar 模式（参见 [1.3 节](#13-istio-数据面与控制面)）：**

```
+================================================+
|                Istio Control Plane             |
|               (istiod)                         |
+================================================+
        |  xDS (gRPC)  |  xDS (gRPC)  |
        v               v               v
+-------------+ +-------------+ +-------------+
| Pod A       | | Pod B       | | Pod C       |
| +---------+ | | +---------+ | | +---------+ |
| | App     | | | | App     | | | | App     | |
| +---------+ | | +---------+ | | +---------+ |
| | Envoy   | | | | Envoy   | | | | Envoy   | |  <-- 每个 Pod 独立 Envoy
| | Sidecar | | | | Sidecar | | | | Sidecar | |      内存: 50-200MB x N
| +---------+ | | +---------+ | | +---------+ |
+-------------+ +-------------+ +-------------+
```

**Ambient Mesh 模式：**

```
+================================================+
|                Istio Control Plane             |
|               (istiod)                         |
+================================================+
        |  xDS (gRPC)  |  xDS (gRPC)
        v               v
+-------------+ +-------------+
| Node 1      | | Node 2      |
| +---------+ | | +---------+ |
| |ztunnel  | | | |ztunnel  | |  <-- 节点级 L4 代理 (eBPF+Rust)
| |(DaemonSet| | | |(DaemonSet| |      内存: ~500MB/节点 (共享)
| +---------+ | | +---------+ |
|  +-------+  | |  +-------+  |
|  |Pod A  |  | |  |Pod B  |  |
|  | App   |  | |  | App   |  |  <-- 应用 Pod 无 Sidecar
|  +-------+  | |  +-------+  |      内存: 0 额外开销
+-------------+ +-------------+

        按需 L7 (Waypoint Proxy)
+------------------+
| Waypoint Proxy   |  <-- 仅在需要 L7 策略时部署
| (Envoy)          |      如: 金丝雀发布、故障注入
+------------------+
```

#### 流量路径对比

**Sidecar 模式流量路径（参见 [2.4 节 mTLS](#24-mtls双向tls)）：**

```
Pod A (App) → Pod A (Envoy Sidecar) → [网络] → Pod B (Envoy Sidecar) → Pod B (App)
                ↑ iptables 劫持                                    ↑ iptables 劫持
```

**Ambient Mesh 流量路径（L4 场景）：**

```
Pod A (App) → Node A (ztunnel, eBPF) → [网络, mTLS] → Node B (ztunnel, eBPF) → Pod B (App)
                ↑ 内核态重定向                                        ↑ 内核态重定向
```

**Ambient Mesh 流量路径（L7 场景，需要高级路由）：**

```
Pod A (App) → Node A (ztunnel) → [网络] → Node B (ztunnel) → Waypoint Proxy → Pod B (App)
                                                                ↑ Envoy L7 策略
```

### 11.4 Kmesh 架构（华为开源）

📌 **2026技术趋势**

**Kmesh** 是华为开源的基于 eBPF 的服务网格数据面方案，已于 2024 年进入 CNCF Landscape。与 Istio Ambient Mesh 类似，Kmesh 也采用 Sidecarless 架构，但实现路径有所不同。

| 维度 | Istio Ambient Mesh | Kmesh |
|------|-------------------|-------|
| 开发者 | Google/Google Cloud | 华为 |
| CNCF 状态 | Sandbox 项目 | Landscape |
| L4 代理 | ztunnel（Rust 用户态 + eBPF） | kmesh-cni（纯 eBPF 内核态） |
| L7 代理 | Waypoint（Envoy） | Waypoint（Envoy） |
| 控制面兼容 | istiod 原生 | istiod 兼容（xDS 协议） |
| 内核要求 | Linux 5.7+ | Linux 5.10+ |
| 性能特点 | L4 内核态，L7 用户态 | L4/L7 均可内核态（部分场景） |
| 适用场景 | 通用服务网格 | 对性能要求极高的场景 |

**Kmesh 核心优势：**
- **纯 eBPF 实现**：L4 流量处理完全在内核态完成，零拷贝，延迟更低
- **与 Istio 生态兼容**：可直接对接 istiod，使用现有的 Istio CRD（VirtualService、DestinationRule 等）
- **渐进式采纳**：支持与 Sidecar 模式共存，可按节点逐步切换

> **离线环境注意：** Kmesh 需要 Linux 5.10+ 内核和 eBPF 支持。请先确认集群节点内核版本（`uname -r`）。本课程 VMware 裸金属环境需验证内核版本是否满足要求。

### 11.5 Ambient Mesh 启用指南

📌 **2026技术趋势**

> **前置条件：** Istio 1.22+（Ambient Mesh GA 版本），Kubernetes 1.26+，Linux 内核 5.7+。

#### 步骤 1：安装 Ambient Mesh Profile

```bash
# 离线环境：提前下载 istioctl 1.22+ 并推送相关镜像到 Harbor
# 镜像清单（需提前推送）：
# gcr.io/istio-release/istio/pilot:1.22.0
# gcr.io/istio-release/istio/proxyv2:1.22.0
# gcr.io/istio-release/istio/ztunnel:1.22.0
# gcr.io/istio-release/istio/install-cni:1.22.0

# 使用 ambient profile 安装（替代课程 4.5.2 节的 minimal profile）
istioctl install --set profile=ambient \
  --set hub=192.168.1.61/istio \
  --set tag=1.22.0

# 验证安装
kubectl get pods -n istio-system
# 预期输出：
# NAME                                    READY   STATUS
# istiod-xxx                              1/1     Running
# ztunnel-xxx                             1/1     Running   <-- 节点级 DaemonSet
```

#### 步骤 2：ztunnel 部署验证

```bash
# 确认 ztunnel DaemonSet 已在每个节点运行
kubectl get ds -n istio-system ztunnel
# NAME      DESIRED   CURRENT   READY
# ztunnel   6         6         6

# 查看 ztunnel 日志
kubectl logs -n istio-system -l app=ztunnel --tail=20

# 验证节点级 mTLS（无需 Sidecar 注入）
kubectl get pod -n demo -o yaml | grep -A5 "istio"
# Ambient 模式下，Pod 无需注入 Sidecar 容器
```

#### 步骤 3：为命名空间启用 Ambient（替代 Sidecar 注入）

```bash
# 传统 Sidecar 模式（课程 4.5.3 节）：
# kubectl label namespace demo istio-injection=enabled

# Ambient Mesh 模式（新方式）：
kubectl label namespace demo istio.io/dataplane-mode=ambient

# 验证：Pod 不应包含 istio-proxy Sidecar 容器
kubectl get pods -n demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'
# 预期输出（无 istio-proxy）：
# api-server-xxx    api-server
# frontend-xxx      frontend
```

#### 步骤 4：Waypoint 按需配置（L7 策略）

```bash
# 当需要 L7 功能（如 VirtualService 路由、故障注入）时，
# 为命名空间创建 Waypoint Proxy
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: Gateway
metadata:
  name: waypoint
  namespace: demo
  annotations:
    istio.io/for-gateway: "waypoint"
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - port: 15008
    protocol: HBONE
    hostname: demo.svc.cluster.local
EOF

# 验证 Waypoint Proxy 已创建
kubectl get gateway -n demo
# NAME      CLASS
# waypoint  istio-waypoint

# 为服务绑定 Waypoint
kubectl label service frontend demo/waypoint -n demo
```

#### 步骤 5：资源节省验证

```bash
# 对比 Sidecar 模式 vs Ambient 模式的资源消耗
echo "=== Sidecar 模式（参考值）==="
echo "1000 Pod x 128MB = ~128GB 内存"

echo "=== Ambient 模式（实测）==="
# ztunnel DaemonSet 资源（6 节点集群）
kubectl top pods -n istio-system -l app=ztunnel
# 每个节点 ztunnel 约 200-500MB

# 应用 Pod 资源（无 Sidecar）
kubectl top pods -n demo
# 应用 Pod 内存仅包含业务容器

# 计算节省量
echo "Ambient 模式: 6节点 x 500MB = ~3GB (ztunnel)"
echo "Sidecar 模式: 1000 Pod x 128MB = ~128GB"
echo "节省: ~97% 内存"
```

#### 与现有课程 Istio 配置的兼容性

| 课程配置项 | Sidecar 模式 | Ambient 模式 | 兼容性 |
|-----------|-------------|-------------|--------|
| VirtualService | 支持 | 支持（需 Waypoint） | 兼容 |
| DestinationRule | 支持 | 支持（需 Waypoint） | 兼容 |
| PeerAuthentication | 支持 | 支持（ztunnel 自动处理） | 兼容 |
| AuthorizationPolicy | 支持 | 支持（L4 由 ztunnel，L7 需 Waypoint） | 部分兼容 |
| Gateway | 支持 | 支持 | 兼容 |
| ServiceEntry | 支持 | 支持 | 兼容 |
| Kiali 可视化 | 完整支持 | 基础支持（L4 拓扑） | 部分兼容 |
| 故障注入 | 支持 | 支持（需 Waypoint） | 兼容 |
| 金丝雀发布 | 支持 | 支持（需 Waypoint） | 兼容 |

> **关键提示：** Ambient 模式下，L4 功能（mTLS、基本路由）由 ztunnel 自动提供，无需额外配置。L7 功能（VirtualService 路由、故障注入等）需要部署 Waypoint Proxy，且仅对需要 L7 策略的服务生效，未配置 Waypoint 的服务仅享受 L4 能力。

### 11.6 迁移策略

📌 **2026技术趋势**

#### 渐进式迁移路线

```
阶段1: 评估验证 (1-2周)
├── 内核版本检查 (>= 5.7)
├── Istio 升级到 1.22+
├── 测试集群部署 Ambient Mesh
└── 功能验证（mTLS、基本路由、可观测性）

阶段2: 非核心服务迁移 (2-4周)
├── 选择低风险命名空间（如开发/测试环境）
├── 切换到 Ambient 模式
├── 验证资源节省效果
└── 收集性能基线数据

阶段3: 核心服务迁移 (4-8周)
├── 逐个命名空间切换
├── 配置 Waypoint（按需 L7）
├── 全链路压测
└── 监控告警调整

阶段4: 全面切换 (2-4周)
├── 移除所有 Sidecar 注入
├── 清理 Sidecar 相关配置
├── 更新运维文档
└── 团队培训
```

#### 双模式共存

Ambient Mesh 支持在同一集群内与 Sidecar 模式共存：

```bash
# 命名空间 A 使用 Ambient 模式（无 Sidecar）
kubectl label namespace team-a istio.io/dataplane-mode=ambient

# 命名空间 B 保持 Sidecar 模式（传统注入）
kubectl label namespace team-b istio-injection=enabled

# 两个命名空间之间的流量仍然可以正常通信
# istiod 会自动处理两种模式之间的 mTLS 通信
```

#### 回滚方案

```bash
# 如果 Ambient 模式出现问题，快速回滚到 Sidecar 模式：

# 1. 将命名空间切换回 Sidecar 模式
kubectl label namespace demo istio.io/dataplane-mode-  # 移除 Ambient 标签
kubectl label namespace demo istio-injection=enabled    # 启用 Sidecar 注入

# 2. 重启命名空间中的所有 Pod（触发 Sidecar 注入）
kubectl rollout restart deployment --all -n demo

# 3. 验证 Sidecar 已注入
kubectl get pods -n demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'
# 确认每个 Pod 包含 istio-proxy 容器

# 4. 删除 Waypoint（如有）
kubectl delete gateway waypoint -n demo
```

> **离线环境迁移注意：** 在离线环境中迁移前，务必提前将 Ambient Mesh 所需镜像（ztunnel、Waypoint Proxy）推送到 Harbor，并在测试环境完成全流程验证后再在生产环境执行。

---

## 14. 2026技术趋势 — Gateway API

> 📌 **2026技术趋势** — Gateway API 是 Kubernetes 官方推出的下一代入口流量 API 标准，旨在替代 Ingress API，提供更强大的路由能力和更好的多团队协作模型。

### 12.1 趋势概述

📌 **2026技术趋势**

在模块 2.1 中我们学习了 Ingress 核心概念（参见 [2.1 Ingress 核心概念](#21-ingress-核心概念)），Ingress 作为 K8s 原生的南北流量入口标准，虽然简单易用，但在生产环境中面临诸多局限：

**Ingress API 的局限性：**

| 局限 | 说明 | 影响 |
|------|------|------|
| 单一角色模型 | Ingress 资源由一个团队管理，无法区分基础设施团队和业务团队 | 大型组织协作困难 |
| 扩展性差 | 高级功能依赖 Annotations，不同 Controller 注解不兼容 | 厂商锁定 |
| 协议支持有限 | 仅原生支持 HTTP/HTTPS，TCP/UDP 需要自定义扩展 | 无法统一管理所有协议 |
| 灰度发布 | 不原生支持，需要额外工具或 Controller 特定注解 | 参见 [Q12 灰度发布](#q12-如何实现-ingress-的灰度发布难度困难) |
| 缺乏状态反馈 | Ingress 资源没有 Status 字段反映实际路由状态 | 排障困难 |
| 路由表达能力弱 | 不支持流量拆分、权重路由、请求头匹配等高级功能 | 功能受限 |

**Gateway API GA 状态：**

- **Gateway API v1.0** 已于 2024 年达到 GA（General Availability）
- **Kubernetes 官方推荐**新项目采用 Gateway API 替代 Ingress
- **主流实现**：Istio、Nginx、Envoy Gateway、Cilium、Traefik 等均已支持
- **SIG-Network** 维护，社区活跃度高

### 12.2 Ingress vs Gateway API 对比表

📌 **2026技术趋势**

| 维度 | Ingress (当前课程) | Gateway API (2026趋势) |
|------|-------------------|----------------------|
| 角色模型 | 单一 Ingress 资源 | GatewayClass → Gateway → Route → Service |
| 扩展性 | Annotations（厂商锁定） | CRD 原生（标准化） |
| 多团队 | 困难（单一 Owner） | 原生支持（不同团队管理不同 Route） |
| 协议支持 | HTTP/HTTPS | HTTP/HTTPS/TCP/UDP/gRPC/TLS |
| 灰度发布 | 需要额外工具/注解 | 原生支持（HTTPRoute weight） |
| 流量拆分 | 不支持 | 原生支持（基于权重/请求头/Cookie） |
| 状态反馈 | 无 Status 字段 | 有 Status 字段（条件、地址、监听器） |
| TLS 配置 | 基础 | 丰富（TLSRoute、证书引用） |
| 后端引用 | 仅 Service | Service、Pod、自定义引用 |
| 扩展点 | 无 | HTTPFilters（可插拔过滤器） |
| API 版本 | networking.k8s.io/v1 | gateway.networking.k8s.io/v1 |
| 状态 | 稳定但功能有限 | GA 稳定，持续增强 |
| 课程参考 | [2.1 节](#21-ingress-核心概念)、[4.3 节](#43-创建-ingress-路由规则) | 本节 |

### 12.3 Gateway API 核心概念

📌 **2026技术趋势**

Gateway API 采用**角色分离模型**，将入口流量的管理职责划分为三个层级：

#### 角色模型

| 角色 | 资源 | 作用域 | 负责团队 | 类比 |
|------|------|--------|----------|------|
| **基础设施管理员** | GatewayClass | 集群级 | 基础设施/平台团队 | 定义"使用什么类型的网关" |
| **集群管理员** | Gateway | 命名空间级 | 平台/SRE 团队 | 定义"网关部署在哪里、监听什么" |
| **应用开发者** | HTTPRoute 等 | 命名空间级 | 业务开发团队 | 定义"流量如何路由到我的服务" |

#### 核心资源类型

| 资源 | 作用 | 类比 Ingress |
|------|------|-------------|
| **GatewayClass** | 定义网关控制器类型（如 Istio、Nginx） | IngressClass |
| **Gateway** | 定义网关实例（监听端口、协议、TLS） | Ingress Controller 配置 |
| **HTTPRoute** | HTTP/HTTPS 路由规则 | Ingress Resource |
| **GRPCRoute** | gRPC 路由规则 | 无对应 |
| **TCPRoute** | TCP 路由规则 | Ingress TCP 注解 |
| **UDPRoute** | UDP 路由规则 | Ingress UDP 注解 |
| **TLSRoute** | TLS 路由（SNI 路由） | 无对应 |
| **ReferenceGrant** | 跨命名空间引用授权 | 无对应 |
| **HTTPRouteFilter** | 请求/响应过滤器 | Ingress 注解 |

#### 架构图

```
                    Internet
                       |
                       v
+--------------------------------------------------+
|              GatewayClass (集群级)                 |
|   定义: 使用 Istio 作为 Gateway Controller        |
|   负责人: 基础设施团队                             |
+--------------------------------------------------+
                       |
                       v
+--------------------------------------------------+
|              Gateway (命名空间级)                   |
|   定义: 监听 80/443, TLS 配置                     |
|   负责人: 平台团队                                 |
|   namespace: infra                                |
+--------------------------------------------------+
                  /          \
                 /            \
+----------------------------+  +----------------------------+
| HTTPRoute (team-a 命名空间)  |  | HTTPRoute (team-b 命名空间) |
| 负责人: Team A 开发团队      |  | 负责人: Team B 开发团队      |
| api.example.com → svc-a     |  | web.example.com → svc-b     |
| 灰度: 90% v1 + 10% v2      |  | 重写: /app → /              |
+----------------------------+  +----------------------------+
          |                              |
    +-----------+                  +-----------+
    | Service A |                  | Service B |
    +-----------+                  +-----------+

对比 Ingress 模型（所有配置在一个 Ingress 资源中）：
+--------------------------------------------------+
|              Ingress (命名空间级)                   |
|   所有配置混在一起，无法区分团队职责                 |
|   api.example.com → svc-a                         |
|   web.example.com → svc-b                         |
+--------------------------------------------------+
```

### 12.4 Gateway API 实战配置

📌 **2026技术趋势**

> **离线环境注意：** 使用 Gateway API 需要安装 CRD（`kubectl apply -f gateway-crds.yaml`）和支持 Gateway API 的 Controller。以下以 Istio 作为 Gateway Controller 实现为例。

#### 步骤 1：安装 Gateway API CRD

```bash
# 离线环境：提前下载 Gateway API CRD YAML
# 下载地址：https://github.com/kubernetes-sigs/gateway-api/releases
# 推送到集群：
kubectl apply -f gateway-api-standard-v1.0.0.yaml

# 验证 CRD 已安装
kubectl get crd | grep gateway.networking.k8s.io
# 预期输出：
# gatewayclasses.gateway.networking.k8s.io
# gateways.gateway.networking.k8s.io
# httproutes.gateway.networking.k8s.io
# grpcroutes.gateway.networking.k8s.io
# tcproutes.gateway.networking.k8s.io
# udproutes.gateway.networking.k8s.io
# referencegrants.gateway.networking.k8s.io
```

#### 步骤 2：GatewayClass 配置（使用 Istio 作为实现）

```yaml
# gatewayclass-istio.yaml
# 基础设施团队管理 - 定义使用 Istio 作为 Gateway Controller
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
  # Istio 会自动识别并管理此 GatewayClass
```

```bash
kubectl apply -f gatewayclass-istio.yaml

# 验证
kubectl get gatewayclass
# NAME    CONTROLLER                     AGE
# istio   istio.io/gateway-controller   10s
```

#### 步骤 3：Gateway 配置

```yaml
# gateway-demo.yaml
# 平台团队管理 - 定义网关实例
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: infra          # 平台团队管理的命名空间
spec:
  gatewayClassName: istio   # 引用上面创建的 GatewayClass
  addresses:
  - type: Hostname
    value: demo.local
  listeners:
  - name: http
    hostname: "*.demo.local"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Selector       # 允许特定命名空间的 Route 关联
        selector:
          matchLabels:
            gateway-access: "true"
  - name: https
    hostname: "*.demo.local"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: demo-tls-secret
        namespace: infra
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            gateway-access: "true"
```

```bash
kubectl apply -f gateway-demo.yaml

# 验证 Gateway 状态
kubectl get gateway -n infra
# NAME           CLASS   ADDRESS          READY
# demo-gateway   istio   192.168.1.54     True

# 查看 Gateway 详细状态（Gateway API 的优势：有 Status 反馈）
kubectl describe gateway demo-gateway -n infra
# Conditions:
#   Ready: True
#   Accepted: True
```

#### 步骤 4：HTTPRoute 配置（应用团队）

```yaml
# httproute-api.yaml
# Team A 应用团队管理 - API 路由
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: demo            # 应用团队管理的命名空间
  labels:
    gateway-access: "true"   # 匹配 Gateway 的 allowedRoutes 选择器
spec:
  parentRefs:
  - name: demo-gateway
    namespace: infra         # 跨命名空间引用 Gateway
    sectionName: http
  hostnames:
  - "api.demo.local"
  rules:
  # 基础路由
  - matches:
    - path:
        type: PathPrefix
        value: /api
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Request-Source
          value: gateway-api
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
    backendRefs:
    - name: api-server
      port: 8080
      weight: 90
    - name: api-server-v2
      port: 8080
      weight: 10

  # 超时配置
  - matches:
    - path:
        type: Exact
        value: /api/health
    timeouts:
      request: 5s
    backendRefs:
    - name: api-server
      port: 8080

  # 重写规则
  - matches:
    - path:
        type: PathPrefix
        value: /api/v2
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /v2/api
    backendRefs:
    - name: api-server-v2
      port: 8080
```

```bash
kubectl apply -f httproute-api.yaml

# 验证 HTTPRoute 状态
kubectl get httproute -n demo
# NAME        HOSTNAMES           AGE
# api-route   api.demo.local      10s

# 查看 HTTPRoute 详细状态
kubectl describe httproute api-route -n demo
# Parents:
#   Gateway: infra/demo-gateway
#   Section Name: http
#   Conditions:
#     Accepted: True
#     ResolvedRefs: True
```

#### 步骤 5：多团队场景（不同命名空间的 Route）

```yaml
# referencegrant.yaml
# 允许 demo 命名空间的 HTTPRoute 引用 infra 命名空间的 Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: allow-demo-routes
  namespace: infra
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: demo
  to:
  - group: gateway.networking.k8s.io
    kind: Gateway
```

```yaml
# httproute-web.yaml
# Team B 应用团队管理 - Web 前端路由
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: demo
  labels:
    gateway-access: "true"
spec:
  parentRefs:
  - name: demo-gateway
    namespace: infra
    sectionName: http
  hostnames:
  - "web.demo.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: frontend
      port: 80
```

#### 与 Istio 集成

```bash
# Istio 1.22+ 原生支持 Gateway API
# 安装 Istio 时确保启用了 Gateway API 转换器
istioctl install --set profile=ambient \
  --set values.pilot.env.PILOT_ENABLE_GATEWAY_API=true \
  --set hub=192.168.1.61/istio \
  --set tag=1.22.0

# Istio 会自动：
# 1. 监听 GatewayClass/Gateway/HTTPRoute 资源
# 2. 将 Gateway API 资源转换为 Istio 内部配置
# 3. 通过 istiod 下发给数据面执行

# 验证 Istio Gateway API 集成状态
istioctl proxy-status
```

### 12.5 迁移路径

📌 **2026技术趋势**

#### Ingress → Gateway API 迁移工具

```bash
# 官方迁移工具：ingress2gateway
# 项目地址：https://github.com/kubernetes-sigs/ingress2gateway

# 离线环境：提前下载二进制文件
# wget https://github.com/kubernetes-sigs/ingress2gateway/releases/download/v0.4.0/ingress2gateway_linux_amd64

# 将现有 Ingress 资源打印为 Gateway API 格式（预览，不执行）
./ingress2gateway print --providers ingress-nginx

# 将现有 Ingress 资源直接转换为 Gateway API 资源并应用
./ingress2gateway print --providers ingress-nginx --providers-flags ingress-nginx.v1 | kubectl apply -f -

# 仅输出到文件（推荐先审查再应用）
./ingress2gateway print --providers ingress-nginx > gateway-api-resources.yaml
```

#### 渐进式迁移策略

```
阶段1: 共存运行 (1-2周)
├── 保留现有 Ingress 资源不变
├── 部署 Gateway API CRD
├── 安装支持 Gateway API 的 Controller
└── 新服务使用 Gateway API，旧服务保持 Ingress

阶段2: 逐步迁移 (2-4周)
├── 使用 ingress2gateway 工具转换非核心服务
├── 验证路由行为一致性
├── 监控错误率和延迟变化
└── 修复转换差异（注解 → Filter）

阶段3: 全面切换 (2-4周)
├── 迁移核心服务
├── 删除旧 Ingress 资源
├── 更新 CI/CD 流水线
└── 更新运维文档和培训材料
```

#### 兼容性说明

| 迁移项 | Ingress 写法 | Gateway API 写法 | 注意事项 |
|--------|-------------|-----------------|----------|
| Host 路由 | `spec.rules[].host` | `spec.hostnames[]` | Gateway API 支持通配符 |
| Path 路由 | `spec.rules[].http.paths[]` | `spec.rules[].matches[]` | pathType 保持一致 |
| TLS | `spec.tls[]` | `spec.listeners[].tls` | 证书引用方式不同 |
| 注解限流 | `nginx.ingress.../rate-limit` | HTTPRouteFilter | 需要自定义 Filter |
| Canary | `nginx.ingress.../canary` | HTTPRoute weight | 原生支持，更标准 |
| 后端 | `serviceName:port` | `backendRefs[]` | Gateway API 支持多后端 |

> **与课程内容的关联：** 课程 [4.3 节](#43-创建-ingress-路由规则) 中创建的 Ingress 资源可以使用 `ingress2gateway` 工具自动转换为 HTTPRoute。课程 [4.6 节](#46-istio-gateway-with-virtualservice) 中的 Istio Gateway + VirtualService 在 Istio 1.22+ 中可以与 Gateway API 共存。

### 12.6 面试题补充

📌 **2026技术趋势**

以下面试题补充到 [第8节 高频面试题](#8-高频面试题) 中：

---

### Q16: 什么是 Sidecarless 服务网格？与传统 Sidecar 模式相比有什么优势？（难度：困难）

**答案：** Sidecarless 服务网格是一种将代理从 Pod 级别提升到节点级别的新型服务网格架构，代表方案是 Istio Ambient Mesh 和 Kmesh。**核心优势**：**资源节省**：传统 Sidecar 模式每个 Pod 注入 Envoy（50-200MB 内存），1000 个 Pod 约消耗 100GB 内存；Sidecarless 模式使用节点级 DaemonSet（如 ztunnel），1000 个 Pod 仅需约 20GB（降低 80%）；**运维简化**：升级代理只需升级 DaemonSet，无需滚动重启所有应用 Pod；Sidecar 模式升级需要逐个 Pod 重启，影响业务连续性。**架构分层**：Ambient Mesh 将数据面分为 L4（ztunnel，eBPF 内核态处理 mTLS 和基本转发）和 L7（Waypoint Proxy，按需部署处理高级路由），未配置 Waypoint 的服务仅享受 L4 能力，避免不必要的资源消耗。**渐进式采纳**：支持 Sidecar 和 Ambient 在同一集群共存，可以按命名空间逐步迁移。**技术栈**：ztunnel 使用 Rust + eBPF，相比 Envoy（C++）内存占用更低，且 eBPF 在内核态处理流量延迟更低。**局限**：L7 功能需要 Waypoint Proxy，增加了架构复杂度；eBPF 对内核版本有要求（Linux 5.7+）；生态成熟度仍在提升中。

### Q17: Gateway API 和 Ingress 有什么区别？为什么 K8s 官方推荐 Gateway API？（难度：中等）

**答案：** Gateway API 是 Kubernetes SIG-Network 推出的下一代入口流量 API 标准，设计目标是替代 Ingress API。**核心区别**：**角色分离**：Ingress 是单一资源，所有配置混在一起，无法区分基础设施团队和业务团队的职责；Gateway API 通过 GatewayClass（基础设施团队）、Gateway（平台团队）、HTTPRoute（应用团队）三层角色模型实现职责分离，支持多团队协作。**扩展性**：Ingress 的高级功能依赖 Annotations，不同 Controller 的注解不兼容导致厂商锁定；Gateway API 使用 CRD 原生定义，HTTPFilters 提供标准化的扩展点。**协议支持**：Ingress 仅原生支持 HTTP/HTTPS；Gateway API 原生支持 HTTP/HTTPS/TCP/UDP/gRPC/TLS。**灰度发布**：Ingress 不原生支持灰度（参见 Q12），需要 Controller 特定注解；Gateway API 通过 HTTPRoute 的 weight 字段原生支持流量拆分。**状态反馈**：Ingress 没有 Status 字段反映路由是否生效；Gateway API 有完整的 Status 字段，可以查看 Gateway 是否 Ready、Route 是否被接受。**K8s 官方推荐原因**：Gateway API 已于 2024 年达到 GA，SIG-Network 明确表示新功能将优先在 Gateway API 中实现，Ingress 仅做维护。

### Q18: 如何在现有 Istio 集群中从 Sidecar 模式迁移到 Ambient Mesh？（难度：困难）

**答案：** 迁移到 Ambient Mesh 需要分阶段进行。**前置条件**：Istio 升级到 1.22+；Kubernetes 1.26+；Linux 内核 5.7+（`uname -r` 确认）。**迁移步骤**：1）安装 Ambient Mesh profile（`istioctl install --set profile=ambient`），此时 ztunnel DaemonSet 会部署到所有节点；2）选择非核心命名空间试点，将标签从 `istio-injection=enabled` 改为 `istio.io/dataplane-mode=ambient`；3）重启该命名空间的 Pod，确认不再注入 Sidecar 容器；4）验证 mTLS 通信正常（`istioctl analyze`）；5）如果该命名空间需要 L7 功能（如 VirtualService 路由），创建 Waypoint Gateway 并绑定到服务；6）逐步将更多命名空间切换到 Ambient 模式。**双模式共存**：同一集群内可以同时存在 Sidecar 和 Ambient 命名空间，istiod 会自动处理两种模式之间的 mTLS 通信，这为渐进式迁移提供了保障。**回滚方案**：移除 Ambient 标签，恢复 Sidecar 注入标签，重启 Pod 即可回滚。**注意事项**：Ambient 模式下 Kiali 的 L7 拓扑视图可能受限；AuthorizationPolicy 的 L7 规则需要 Waypoint 支持；建议在测试环境完成全流程验证后再在生产环境执行。
