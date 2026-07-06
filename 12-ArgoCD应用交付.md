# 模块12：ArgoCD应用交付

---

## 1. 概述与架构图

### 1.1 GitOps（Git 驱动运维） 工作流

```
+================================================================+
|                    GitOps 工作流 (ArgoCD)                       |
+================================================================+
|                                                                 |
|  开发者                    Git 仓库                   ArgoCD     |
|  (Developer)              (Single Source of Truth)   (K8s)      |
|                                                                 |
|  +----------+           +-----------+           +-----------+  |
|  | 1.编写   |  git push | Git Repo  |  watch    | ArgoCD    |  |
|  | K8s YAML | --------> | (GitHub/  | <-------- | App       |  |
|  | Helm    |           |  GitLab)  |           | Controller|  |
|  +----------+           +-----------+           +-----+-----+  |
|                                                    |          |
|                                                    | sync     |
|                                                    v          |
|                                              +-----------+    |
|                                              |  K8s      |    |
|                                              |  Cluster  |    |
|                                              | (Desired  |    |
|                                              |  State == |    |
|                                              |  Actual)  |    |
|                                              +-----------+    |
+================================================================+
```

### 1.2 ArgoCD 架构

```
+================================================================+
|                    ArgoCD 架构                                  |
+================================================================+
|                                                                 |
|  +------------------+                                           |
|  | ArgoCD Server    |  <-- Web UI + gRPC API + CLI              |
|  | (NodePort/Ingress)|                                          |
|  +--------+---------+                                           |
|           |                                                      |
|  +--------+---------+                                           |
|  | ArgoCD           |                                           |
|  | Application      |  <-- 核心控制器，Watch Git + Sync K8s     |
|  | Controller       |                                           |
|  +--------+---------+                                           |
|           |                                                      |
|     +-----+-----+                                               |
|     |           |                                               |
|     v           v                                               |
| +-------+  +--------+  +----------+  +----------+               |
| | Git   |  | Helm   |  | K8s API  |  | Repo    |               |
| | Repo  |  | Charts |  | Server   |  | Server  |               |
| | (Git  |  | (Helm  |  | (Apply   |  | (Chart  |               |
| |  Ops) |  |  Repo) |  |  Diff)   |  |  Cache) |               |
| +-------+  +--------+  +----------+  +----------+               |
+================================================================+
```

### 1.3 App of Apps（应用嵌套模式） 模式

```
ArgoCD (Root App)
  |
  +-- App: infra (基础设施)
  |     +-- Prometheus Stack
  |     +-- Loki
  |     +-- Tempo
  |     +-- Ingress NGINX
  |
  +-- App: middleware (中间件)
  |     +-- Nacos
  |     +-- Kafka (Strimzi)
  |     +-- Redis
  |
  +-- App: demo-apps (业务应用)
  |     +-- user-service
  |     +-- order-service
  |     +-- inventory-service
  |     +-- payment-service
  |
  +-- App: monitoring (监控)
        +-- Grafana Dashboards
        +-- Alert Rules
        +-- OTel Collector
```

---

## 2. 理论基础

### 2.1 GitOps 核心原则

| 原则 | 说明 |
|------|------|
| 声明式 | 整个系统的期望状态用声明式配置描述（YAML/Helm（K8s 包管理器）） |
| 版本化 | 所有配置存储在 Git 中，享受版本控制的所有优势 |
| 自动化 | 自动将 Git 中的期望状态应用到 K8s 集群 |
| 持续协调 | 持续比较期望状态与实际状态，自动纠正偏差 |

### 2.2 ArgoCD 核心概念

| 概念 | 说明 |
|------|------|
| Application | ArgoCD 的核心 CRD（自定义资源定义），定义 Git 仓库到 K8s 集群的同步关系 |
| ApplicationSet | 应用集，支持模板化批量创建 Application |
| App of Apps | 应用模式，用一个父 Application 管理多个子 Application |
| Sync | 同步操作，将 Git 中的配置应用到 K8s 集群 |
| Auto-Sync（自动同步） | 自动同步，Git 变更后自动触发 Sync |
| Self-Heal（自动修复） | 自愈，K8s 中手动修改被自动回滚到 Git 中的状态 |
| Sync Hook | 同步钩子，在 Sync 过程中执行自定义操作（PreSync（同步前钩子）/PostSync（同步后钩子）/SyncFail） |
| Sync Window（同步时间窗口） | 同步窗口，限制 Sync 操作的时间段 |
| Rollback | 回滚，通过 Git revert 回滚到历史版本 |

### 2.3 ArgoCD vs Flux vs Jenkins

| 特性 | ArgoCD | Flux | Jenkins |
|------|--------|------|---------|
| 模式 | Pull（Agent 在集群内） | Pull（Agent 在集群内） | Push（从外部推送） |
| UI | 功能丰富的 Web UI | 简洁 UI | 功能丰富但复杂 |
| 多集群 | 原生支持 | 原生支持 | 需要配置 |
| RBAC（基于角色的访问控制） | SSO（单点登录）/SSO/RBAC | RBAC | 插件 |
| K8s 原生 | CRD + Operator | CRD + Operator | 外部系统 |
| 学习曲线 | 中等 | 低 | 高 |
| Helm 支持 | 完整 | 完整 | 通过插件 |
| 多环境 | ApplicationSet（应用集） | Kustomize（配置定制工具） | Pipeline（流水线） |
| 社区 | CNCF（云原生计算基金会） 毕业项目 | CNCF 毕业项目 | 广泛 |

---

## 3. 离线前置准备

> 以下操作需要在**有外网访问的机器**（如美国服务器）上完成，然后将产物传输到离线集群。

### 3.0.1 ArgoCD 镜像清单

| 镜像 | 用途 | Harbor 目标路径 |
|------|------|----------------|
| `quay.io/argoproj/argocd:v2.10.9` | ArgoCD Server / Controller / Repo Server 等核心组件 | `192.168.1.61:80/argoproj/argocd:v2.10.9` |
| `ghcr.io/dexidp/dex:v2.38.0` | Dex（身份认证服务） SSO 服务 | `192.168.1.61:80/dexidp/dex:v2.38.0` |
| `docker.io/library/redis:7.2.4-alpine` | Redis 缓存 | `192.168.1.61:80/library/redis:7.2.4-alpine` |
| `curlimages/curl:8.0` | Hook 镜像（Sync Hook 中使用） | `192.168.1.61:80/curlimages/curl:8.0` |
| `busybox:1.36` | Hook 镜像（健康检查等） | `192.168.1.61:80/library/busybox:1.36` |

### 3.0.2 在有网机器上下载并推送镜像到 Harbor

```bash
# 在有外网访问的机器上执行
HARBOR_ADDR="192.168.1.61:80"

# 登录 Harbor
docker login ${HARBOR_ADDR} -u admin -p Harbor12345

# 下载并推送 ArgoCD 核心镜像
for img in \
  quay.io/argoproj/argocd:v2.10.9 \
  ghcr.io/dexidp/dex:v2.38.0 \
  docker.io/library/redis:7.2.4-alpine \
  curlimages/curl:8.0 \
  busybox:1.36; do

  target_img="${HARBOR_ADDR}/$(echo ${img} | sed 's|quay.io/||;s|ghcr.io/||;s|docker.io/||')"
  echo ">>> Processing: ${img} -> ${target_img}"
  docker pull ${img}
  docker tag ${img} ${target_img}
  docker push ${target_img}
done
```

### 3.0.3 下载 install.yaml 并修改镜像地址

```bash
# 在有外网访问的机器上下载 ArgoCD 安装清单
curl -o argocd-install.yaml https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.9/manifests/install.yaml

# 批量替换镜像地址为 Harbor 地址
sed -i 's|quay.io/argoproj/argocd:|192.168.1.61:80/argoproj/argocd:|g' argocd-install.yaml
sed -i 's|ghcr.io/dexidp/dex:|192.168.1.61:80/dexidp/dex:|g' argocd-install.yaml
sed -i 's|docker.io/library/redis:|192.168.1.61:80/library/redis:|g' argocd-install.yaml

# 将修改后的文件传输到 Master 节点
scp argocd-install.yaml root@192.168.1.54:/root/
```

### 3.0.4 同步外部 Helm Chart 到 Harbor

```bash
# 在有外网访问的机器上，将外部 Helm 仓库的 Chart 同步到 Harbor Helm 仓库

# 添加外部 Helm 仓库
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 下载 Chart 包
helm pull bitnami/redis --version 18.0.0
helm pull prometheus-community/kube-prometheus-stack --version 56.0.0
helm pull ingress-nginx/ingress-nginx --version 4.9.0

# 推送到 Harbor Helm 仓库
for chart in *.tgz; do
  curl -u admin:Harbor12345 --upload-file ${chart} \
    "http://192.168.1.61:80/api/chartrepo/demo/charts"
done

# 后续 ArgoCD 中使用 Harbor Helm 仓库地址：
# http://192.168.1.61:80/chartrepo/demo
```

---

## 4. 部署实战

### 4.1 安装 ArgoCD

```bash
# 创建命名空间
kubectl create namespace argocd

# 安装 ArgoCD（离线方式 - 使用已修改镜像地址的本地文件）
# 该文件已在前置准备中下载并修改了所有镜像地址为 Harbor 地址
# 如果文件在 Master 节点上：
kubectl apply -n argocd -f /root/argocd-install.yaml

# 验证安装
kubectl get pods -n argocd
# 预期：argocd-application-controller-xxx, argocd-server-xxx, argocd-repo-server-xxx, argocd-dex-server-xxx, redis-xxx Running

# 降低资源需求（适配 Master 2C4G / Worker 4C8G 环境）
# 将 ArgoCD Server 副本数设为 1
kubectl scale deployment argocd-server -n argocd --replicas=1
# 将 Repo Server 副本数设为 1
kubectl scale deployment argocd-repo-server -n argocd --replicas=1

# 暴露 ArgoCD Server（NodePort）
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc argocd-server -n argocd -p '{"spec":{"ports":[{"port":80,"targetPort":8080,"nodePort":32080},{"port":443,"targetPort":8443,"nodePort":32443}]}}'

# 获取初始管理员密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

# 访问 ArgoCD UI
# https://192.168.1.54:32443
# 用户名：admin
# 密码：上面的输出

# --- ArgoCD CLI 离线安装 ---
# 在有外网访问的机器上下载 CLI 二进制文件
# curl -sLO https://github.com/argoproj/argo-cd/releases/download/v2.10.9/argocd-linux-amd64
# chmod +x argocd-linux-amd64
# scp argocd-linux-amd64 root@192.168.1.54:/usr/local/bin/argocd

# 在 Master 节点上验证 CLI
argocd version

# 修改默认密码
argocd login 192.168.1.54:32443 --insecure
argocd account update-password
```

### 4.2 配置 ArgoCD 连接私有 Git 仓库

```bash
# 配置 Git 仓库访问（SSH 方式）
argocd repo add git@192.168.1.61:demo/demo-manifests.git \
  --ssh-private-key-path ~/.ssh/id_rsa \
  --insecure-ignore-host-key

# 配置 Git 仓库访问（HTTPS 方式）
argocd repo add http://192.168.1.61:3000/demo/demo-manifests.git \
  --username admin \
  --password gitea-token-example

# 配置 Harbor Helm 仓库
argocd repo add http://192.168.1.61:80/chartrepo/demo \
  --type helm \
  --username admin \
  --password Harbor12345 \
  --insecure-skip-server-verification

# 验证仓库配置
argocd repo list
```

### 4.3 创建第一个 Application

```bash
# 方式一：使用 CLI 创建 Application
argocd app create demo-app \
  --repo http://192.168.1.61:3000/demo/demo-manifests.git \
  --path k8s/demo-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace demo \
  --sync-policy automated \
  --self-heal \
  --auto-prune \
  --revision HEAD

# 方式二：使用 YAML 创建 Application
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: demo-app
  namespace: argocd
  labels:
    team: demo
    env: production
spec:
  project: default  # 所属项目
  source:
    repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
    targetRevision: main  # Git 分支
    path: k8s/demo-app
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: demo  # 目标命名空间
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true  # 自动创建命名空间
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    - ServerSideApply=true  # 使用服务端应用
    retry:
      limit: 3  # 最大重试次数
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

# 同步应用
argocd app sync demo-app

# 查看应用状态
argocd app get demo-app

# 查看 Sync 状态
argocd app sync demo-app --watch
```

### 4.4 Helm 集成

```bash
# 创建 Helm 类型 Application
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: demo-app-helm
  namespace: argocd
spec:
  project: default  # 所属项目
  source:
    repoURL: http://192.168.1.61:3000/demo/demo-charts.git
    targetRevision: main  # Git 分支
    path: charts/demo-app
    helm:
      valueFiles:
      - values.yaml
      - values-production.yaml
      parameters:
      - name: image.repository  # 镜像仓库地址
        value: 192.168.1.61:80/demo/api-server
      - name: image.tag  # 镜像标签
        value: v1.0.0
      - name: replicaCount  # 副本数量
        value: 2
      - name: resources.requests.cpu
        value: 200m
      - name: resources.requests.memory
        value: 512Mi
      - name: ingress.enabled  # 启用 Ingress
        value: "true"
      - name: ingress.hosts[0].host
        value: api.demo.local
      releaseName: demo-app
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: demo  # 目标命名空间
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
    syncOptions:
    - CreateNamespace=true  # 自动创建命名空间
EOF

# 使用 Harbor Helm 仓库中的 Chart（离线环境）
# 前置条件：Chart 已同步到 Harbor Helm 仓库（参见 3.0.4 节）
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: redis-helm
  namespace: argocd
spec:
  project: default  # 所属项目
  source:
    chart: redis  # Redis Helm Chart
    repoURL: http://192.168.1.61:80/chartrepo/demo
    targetRevision: 18.0.0
    helm:
      parameters:
      - name: auth.password  # Redis 密码
        value: Redis12345
      - name: master.persistence.enabled  # 主节点持久化
        value: "false"
      - name: replica.persistence.enabled  # 从节点持久化
        value: "false"
      - name: architecture  # 部署架构
        value: standalone
      - name: resources.requests.cpu
        value: 100m
      - name: resources.requests.memory
        value: 256Mi
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: middleware
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
    syncOptions:
    - CreateNamespace=true  # 自动创建命名空间
EOF
```

### 4.5 App of Apps 模式

```bash
# 创建根 Application（管理所有子应用）
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default  # 所属项目
  source:
    repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
    targetRevision: main  # Git 分支
    path: argocd/root
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: argocd
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
EOF

# Git 仓库结构
# argocd/root/
#   ├── apps/
#   │   ├── infra-apps.yaml        (基础设施应用)
#   │   ├── middleware-apps.yaml   (中间件应用)
#   │   └── demo-apps.yaml        (业务应用)
#   └── projects/
#       ├── demo-project.yaml
#       └── infra-project.yaml

# 子应用：基础设施
cat <<'EOF' > argocd/root/apps/infra-apps.yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationList  # ArgoCD 应用列表
items:
- metadata:
    name: prometheus-stack
  spec:
    project: infra
    source:
      chart: kube-prometheus-stack  # Prometheus 监控栈
      repoURL: http://192.168.1.61:80/chartrepo/demo
      targetRevision: 56.0.0
      helm:
        values: |
          prometheus:
            prometheusSpec:
              retention: 7d
          grafana:
            service:
              type: NodePort
              nodePort: 32000  # NodePort 端口
    destination:
      server: https://kubernetes.default.svc  # 目标 K8s 集群
      namespace: monitoring
    syncPolicy:  # 同步策略
      automated:  # 启用自动同步
        prune: true  # 自动清理多余资源
        selfHeal: true  # 启用自动修复
      syncOptions:
      - CreateNamespace=true  # 自动创建命名空间
- metadata:
    name: ingress-nginx
  spec:
    project: infra
    source:
      chart: ingress-nginx  # Nginx Ingress 控制器
      repoURL: http://192.168.1.61:80/chartrepo/demo
      targetRevision: 4.9.0
      helm:
        values: |
          controller:
            service:
              type: NodePort
              nodePorts:
                http: 30080
                https: 30443
    destination:
      server: https://kubernetes.default.svc  # 目标 K8s 集群
      namespace: ingress-nginx
    syncPolicy:  # 同步策略
      automated:  # 启用自动同步
        prune: true  # 自动清理多余资源
        selfHeal: true  # 启用自动修复
      syncOptions:
      - CreateNamespace=true  # 自动创建命名空间
EOF

# 子应用：业务应用
cat <<'EOF' > argocd/root/apps/demo-apps.yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationList  # ArgoCD 应用列表
items:
- metadata:
    name: user-service
  spec:
    project: demo
    source:
      repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
      targetRevision: main  # Git 分支
      path: k8s/user-service
      helm:
        valueFiles:
        - values.yaml
        - values-production.yaml
    destination:
      server: https://kubernetes.default.svc  # 目标 K8s 集群
      namespace: demo  # 目标命名空间
    syncPolicy:  # 同步策略
      automated:  # 启用自动同步
        prune: true  # 自动清理多余资源
        selfHeal: true  # 启用自动修复
      syncOptions:
      - CreateNamespace=true  # 自动创建命名空间
- metadata:
    name: order-service
  spec:
    project: demo
    source:
      repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
      targetRevision: main  # Git 分支
      path: k8s/order-service
      helm:
        valueFiles:
        - values.yaml
        - values-production.yaml
    destination:
      server: https://kubernetes.default.svc  # 目标 K8s 集群
      namespace: demo  # 目标命名空间
    syncPolicy:  # 同步策略
      automated:  # 启用自动同步
        prune: true  # 自动清理多余资源
        selfHeal: true  # 启用自动修复
      syncOptions:
      - CreateNamespace=true  # 自动创建命名空间
EOF
```

### 4.6 ApplicationSet 多环境管理

```bash
# 使用 ApplicationSet 自动生成多环境 Application
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: demo-appset
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: in-cluster
        env: dev
        valuesFile: values-dev.yaml
        namespace: demo-dev
      - cluster: in-cluster
        env: staging
        valuesFile: values-staging.yaml
        namespace: demo-staging
      - cluster: in-cluster
        env: production
        valuesFile: values-production.yaml
        namespace: demo
  template:
    metadata:
      name: demo-app-{{env}}
      labels:
        env: "{{env}}"
    spec:
      project: default  # 所属项目
      source:
        repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
        targetRevision: main  # Git 分支
        path: charts/demo-app
        helm:
          valueFiles:
          - values.yaml
          - "{{valuesFile}}"
          parameters:
          - name: image.tag  # 镜像标签
            value: v1.0.0
      destination:
        server: https://kubernetes.default.svc  # 目标 K8s 集群
        namespace: "{{namespace}}"
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: true  # 启用自动修复
        syncOptions:
        - CreateNamespace=true  # 自动创建命名空间
EOF

# 使用 Git Directory 生成器（基于目录结构自动生成）
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: cluster-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
      revision: main
      directories:
      - path: k8s/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default  # 所属项目
      source:
        repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
        targetRevision: main  # Git 分支
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc  # 目标 K8s 集群
        namespace: demo  # 目标命名空间
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: true  # 启用自动修复
        syncOptions:
        - CreateNamespace=true  # 自动创建命名空间
EOF
```

### 4.7 回滚（Git Revert 自动回滚）

```bash
# 方式一：通过 ArgoCD UI 回滚
# 1. 进入 ArgoCD UI -> Application -> History
# 2. 选择需要回滚的版本
# 3. 点击 "Rollback"

# 方式二：通过 CLI 回滚
argocd app rollback demo-app 3  # 回滚到第 3 个 revision

# 方式三：通过 Git revert 回滚（推荐）
# 1. 在 Git 仓库中 revert 有问题的提交
git log --oneline -5
# a1b2c3d Fix: update image to v1.0.1
# e4f5g6h Feat: add new feature
# i7j8k9l Fix: update config

# 2. Revert 有问题的提交
git revert e4f5g6h --no-edit
git push origin main

# 3. ArgoCD 自动检测到 Git 变更，自动 Sync 回滚后的配置

# 方式四：使用 Sync Hook 实现回滚前通知
cat <<'EOF' > k8s/demo-app/pre-sync-hook.yaml
apiVersion: batch/v1  # API 版本
kind: Job  # K8s 任务
metadata:
  name: pre-sync-notify
  annotations:
    argocd.argoproj.io/hook: PreSync  # 同步前执行
    argocd.argoproj.io/hook-delete-policy: HookSucceeded  # 成功后自动删除
spec:
  template:
    spec:
      containers:
      - name: notify
        image: 192.168.1.61:80/curlimages/curl:8.0  # 镜像地址(Harbor)
        command:
        - sh
        - -c
        - |
          curl -X POST "http://192.168.1.61:3000/demo/webhook" \
            -H "Content-Type: application/json" \
            -d '{"text":"ArgoCD Sync: demo-app is about to be synced"}'
      restartPolicy: Never
  backoffLimit: 1
EOF
```

### 4.8 RBAC 配置

```bash
# 创建 ArgoCD Project
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AppProject  # ArgoCD 项目
metadata:
  name: demo
  namespace: argocd
spec:
  description: Demo project for business applications
  sourceRepos:  # 允许的 Git 仓库
  - http://192.168.1.61:3000/demo/demo-manifests.git
  - http://192.168.1.61:80/chartrepo/demo
  destinations:  # 允许的部署目标
  - namespace: demo
    server: https://kubernetes.default.svc  # 目标 K8s 集群
  - namespace: demo-dev
    server: https://kubernetes.default.svc  # 目标 K8s 集群
  - namespace: demo-staging
    server: https://kubernetes.default.svc  # 目标 K8s 集群
  clusterResourceWhitelist:  # 允许的集群级资源
  - group: ""
    kind: Namespace
  - group: "networking.k8s.io"
    kind: Ingress  # K8s 入口路由
  namespaceResourceWhitelist:  # 允许的命名空间级资源
  - group: "apps"
    kind: Deployment  # K8s 部署
  - group: "apps"
    kind: StatefulSet
  - group: ""
    kind: Service  # K8s 服务
  - group: ""
    kind: ConfigMap  # K8s 配置映射
  - group: ""
    kind: Secret
  orphanedResources:
    warn: true
  roles:
  - name: developer
    policies:
    - p, proj:demo:developer, applications, get, demo/*, allow
    - p, proj:demo:developer, applications, sync, demo/*, allow
    - p, proj:demo:developer, applications, override, demo/*, allow
    groups:
    - demo-developers
  - name: readonly
    policies:
    - p, proj:demo:readonly, applications, get, demo/*, allow
    groups:
    - demo-readonly
EOF

# 创建 ArgoCD RBAC ConfigMap
cat <<'EOF' | kubectl apply -f -
apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, get, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:admin, projects, *, *, allow
    p, role:admin, accounts, *, *, allow
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, clusters, get, *, allow
    p, role:readonly, projects, get, *, allow
    g, demo-developers, role:readonly
    g, argocd-admins, role:admin
  policy.default: role:readonly  # 默认只读权限
EOF

# 创建 ArgoCD 用户（通过 SSO/SSO）
# 注意：离线环境无法使用 GitHub SSO（Dex 的 GitHub connector 需要访问 github.com）
# 推荐方案一：使用 Gitea OAuth（Gitea 已部署在 192.168.1.61:3000）
# 推荐方案二：使用 ArgoCD 本地认证（admin 用户 + RBAC）
cat <<'EOF' | kubectl apply -f -
apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.demo.local
  # 离线环境 SSO 配置（使用 Gitea OAuth 替代 GitHub SSO）
  # 前置条件：在 Gitea (192.168.1.61:3000) 中创建 OAuth2 应用
  #   回调地址：https://argocd.demo.local/api/dex/callback
  dex.config: |
    connectors:  # SSO 连接器配置
    - type: gitea  # Gitea OAuth 认证
      id: gitea
      name: Gitea
      config:
        clientID: $dex.gitea.clientID
        clientSecret: $dex.gitea.clientSecret
        baseURL: http://192.168.1.61:3000
        redirectURI: https://argocd.demo.local/api/dex/callback
        # Gitea 组映射（可选）
        # groups:
        # - name: demo-developers
        #   orgs:
        #   - demo
EOF

# 如果不配置 SSO，也可以直接使用 ArgoCD 本地 admin 账号 + RBAC 进行权限管理
# 创建只读用户示例：
# argocd account list
# 通过 RBAC ConfigMap (argocd-rbac-cm) 中的 policy.csv 管理本地用户权限
```

---

## 4.9 Secrets管理方案

### 4.9.1 GitOps场景下的Secret管理挑战

在GitOps工作流中，将敏感信息（如数据库密码、API密钥、TLS证书）直接存储在Git仓库中存在严重的安全风险：

| 挑战 | 说明 |
|------|------|
| 明文存储风险 | Secret以base64编码存储在Git中，容易被泄露 |
| 权限扩散 | 所有能访问Git仓库的人员都能看到敏感信息 |
| 审计困难 | 难以追踪谁访问了哪些Secret |
| 轮换复杂 | Secret轮换需要修改Git并重新部署 |
| 多环境同步 | 不同环境需要不同的Secret值，管理复杂 |

**解决方案对比：**

| 方案 | 原理 | 优点 | 缺点 | 适用场景 |
|------|------|------|------|----------|
| Sealed Secrets | 客户端加密，集群内解密 | 纯离线、无外部依赖 | 密钥管理复杂 | 离线/隔离环境 |
| External Secrets | 从外部KMS同步Secret | 集中管理、自动轮换 | 需要网络连通 | 云环境/有Vault（密钥管理服务） |
| ArgoCD Vault Plugin | ArgoCD渲染时从Vault读取 | 与ArgoCD深度集成 | 需要Vault | 已有Vault基础设施 |
| SOPS（密钥加密工具） + Helm Secrets | 使用PGP加密values文件 | 灵活、支持多密钥 | 需要密钥分发 | 小型团队 |

### 4.9.2 Sealed Secrets（加密 Secret 方案）部署与使用(离线)

Sealed Secrets是Bitnami开源的解决方案，使用非对称加密保护Secret，适合完全离线的环境。

**架构图：**

```
+================================================================+
|                    Sealed Secrets 架构                          |
+================================================================+
|                                                                 |
|  开发者机器                    Git仓库            K8s集群       |
|  (有kubeseal)                                                  |
|                                                                 |
|  +----------+               +-----------+      +-------------+ |
|  | 原始Secret|  kubeseal    | Git Repo  |      | Sealed      | |
|  | (敏感)   | ---------->  | (加密存储) | ---> | Secrets     | |
|  +----------+   加密        +-----------+      | Controller  | |
|       |                                        +------+------+ |
|       |                                               |        |
|       |  公钥加密                                      | 私钥解密|
|       |                                               v        |
|  +----+----+                                     +----------+  |
|  | 公钥    |                                     | 原始Secret|  |
|  | (cert)  |                                     | (K8s中)   |  |
|  +---------+                                     +----------+  |
|                                                                 |
+================================================================+
```

**离线镜像准备：**

```bash
# 在有外网访问的机器上下载镜像
HARBOR_ADDR="192.168.1.61:80"
docker pull docker.io/bitnami/sealed-secrets-controller:0.26.0
docker pull docker.io/bitnami/kubeseal:0.26.0

# 推送到Harbor
docker tag docker.io/bitnami/sealed-secrets-controller:0.26.0 \
  ${HARBOR_ADDR}/bitnami/sealed-secrets-controller:0.26.0
docker tag docker.io/bitnami/kubeseal:0.26.0 \
  ${HARBOR_ADDR}/bitnami/kubeseal:0.26.0

docker push ${HARBOR_ADDR}/bitnami/sealed-secrets-controller:0.26.0
docker push ${HARBOR_ADDR}/bitnami/kubeseal:0.26.0
```

**部署Sealed Secrets Controller：**

```bash
# 在有外网机器下载安装清单
curl -o sealed-secrets-controller.yaml \
  https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml

# 修改镜像地址
sed -i 's|docker.io/bitnami/sealed-secrets-controller:|192.168.1.61:80/bitnami/sealed-secrets-controller:|g' \
  sealed-secrets-controller.yaml

# 传输到离线集群并安装
kubectl apply -f sealed-secrets-controller.yaml

# 验证安装
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

**使用kubeseal加密Secret：**

```bash
# 在开发者机器上安装kubeseal（离线方式）
# 下载二进制文件: https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
# 解压后移动到/usr/local/bin/kubeseal

# 获取集群公钥（用于离线加密）
kubeseal --fetch-cert > sealed-secrets-cert.pem

# 创建原始Secret
cat > db-secret.yaml <<'EOF'
apiVersion: v1  # API 版本
kind: Secret
metadata:
  name: db-credentials
  namespace: demo
type: Opaque  # 通用 Secret 类型
stringData:
  username: admin
  password: MySecurePassword123!
  host: mysql.demo.svc.cluster.local
  port: "3306"
EOF

# 加密为SealedSecret
kubeseal --cert sealed-secrets-cert.pem --format yaml < db-secret.yaml > db-sealedsecret.yaml

# 查看加密后的内容
cat db-sealedsecret.yaml
```

**SealedSecret YAML示例：**

```yaml
apiVersion: bitnami.com/v1alpha1  # Sealed Secrets API 版本
kind: SealedSecret  # 加密 Secret
metadata:
  name: db-credentials
  namespace: demo
spec:
  encryptedData:
    host: AgA123...（加密内容）
    password: AgB456...（加密内容）
    port: AgC789...（加密内容）
    username: AgD012...（加密内容）
  template:
    type: Opaque  # 通用 Secret 类型
    metadata:
      name: db-credentials
      namespace: demo
```

**在ArgoCD中管理SealedSecret：**

```bash
# 将SealedSecret提交到Git仓库
git add db-sealedsecret.yaml
git commit -m "Add encrypted database credentials"
git push origin main

# ArgoCD会自动同步SealedSecret到集群
# Controller会自动解密为普通Secret

# 验证Secret已创建
kubectl get secret db-credentials -n demo -o yaml
```

**ArgoCD Application配置：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: demo-app-with-secrets
  namespace: argocd
spec:
  project: default  # 所属项目
  source:
    repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
    targetRevision: main  # Git 分支
    path: k8s/demo-app
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: demo  # 目标命名空间
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
    syncOptions:
    - CreateNamespace=true  # 自动创建命名空间
---
# 确保Sealed Secrets Controller先部署
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: sealed-secrets
  namespace: argocd
spec:
  project: default  # 所属项目
  source:
    repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
    targetRevision: main  # Git 分支
    path: infra/sealed-secrets
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: kube-system
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
```

### 4.9.3 External Secrets Operator从Vault同步

External Secrets Operator (ESO) 从外部密钥管理系统（如HashiCorp Vault、AWS Secrets Manager）同步Secret到K8s集群。

**架构图：**

```
+================================================================+
|                External Secrets Operator 架构                   |
+================================================================+
|                                                                 |
|  +------------------+        +------------------+              |
|  | HashiCorp Vault  |        | ESO Controller   |              |
|  | (密钥管理中心)    |<------>| (运行在K8s中)    |              |
|  +------------------+  拉取   +--------+---------+              |
|           ^                           |                        |
|           | 写入                      | 创建/更新               |
|           |                           v                        |
|  +--------+--------+          +------------------+             |
|  | 运维人员/CI/CD  |          | K8s Secret       |             |
|  +-----------------+          | (应用消费)       |             |
|                               +------------------+             |
+================================================================+
```

**离线镜像准备：**

```bash
HARBOR_ADDR="192.168.1.61:80"

# ESO镜像
docker pull ghcr.io/external-secrets/external-secrets:v0.9.9
docker tag ghcr.io/external-secrets/external-secrets:v0.9.9 \
  ${HARBOR_ADDR}/external-secrets/external-secrets:v0.9.9
docker push ${HARBOR_ADDR}/external-secrets/external-secrets:v0.9.9
```

**部署External Secrets Operator：**

```bash
# 下载安装清单
curl -o external-secrets.yaml \
  https://raw.githubusercontent.com/external-secrets/external-secrets/v0.9.9/deploy/crds/bundle.yaml

# 修改镜像地址后部署
sed -i 's|ghcr.io/external-secrets/external-secrets:|192.168.1.61:80/external-secrets/external-secrets:|g' \
  external-secrets.yaml
kubectl apply -f external-secrets.yaml
```

**配置Vault连接：**

```yaml
# SecretStore: 定义Vault连接配置
apiVersion: external-secrets.io/v1beta1  # API 版本
kind: SecretStore
metadata:
  name: vault-backend
  namespace: demo
spec:
  provider:
    vault:
      server: "http://vault.demo.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
---
# 存储Vault访问Token
apiVersion: v1  # API 版本
kind: Secret
metadata:
  name: vault-token
  namespace: demo
type: Opaque  # 通用 Secret 类型
stringData:
  token: "s.xxxxxx"  # Vault访问Token
```

**创建ExternalSecret同步规则：**

```yaml
apiVersion: external-secrets.io/v1beta1  # API 版本
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: demo
spec:
  refreshInterval: 1h  # 每小时同步一次
  secretStoreRef:
    kind: SecretStore
    name: vault-backend
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: secret/data/demo/db
      property: username
  - secretKey: password
    remoteRef:
      key: secret/data/demo/db
      property: password
  - secretKey: host
    remoteRef:
      key: secret/data/demo/db
      property: host
```

**Vault中准备Secret：**

```bash
# 在Vault中写入Secret
vault kv put secret/demo/db username=admin password=SecurePass123 host=mysql.demo.svc.cluster.local

# 验证
vault kv get secret/demo/db
```

### 4.9.4 ArgoCD Vault Plugin解密

ArgoCD Vault Plugin (AVP) 允许在ArgoCD渲染manifest时从Vault动态获取Secret值。

**架构图：**

```
+================================================================+
|               ArgoCD Vault Plugin 架构                          |
+================================================================+
|                                                                 |
|  Git仓库                        ArgoCD Repo Server             |
|  (含占位符)                                                     |
|                                                                 |
|  +-----------+                 +----------------------+        |
|  | deployment|                 | ArgoCD Vault Plugin  |        |
|  | yaml      | --------------> | (Sidecar/Init)       |        |
|  | <vault:..>|                 +----------+-----------+        |
|  +-----------+                            |                    |
|                                           | 查询               |
|                                           v                    |
|                                    +-------------+             |
|                                    | HashiCorp   |             |
|                                    | Vault       |             |
|                                    +-------------+             |
|                                           |                    |
|                                           | 返回真实值          |
|                                           v                    |
|                                    +----------------------+    |
|                                    | 渲染后的manifest      |    |
|                                    | (真实Secret值)       |    |
|                                    +----------------------+    |
+================================================================+
```

**部署AVP Sidecar（边车代理）：**

```bash
# 下载AVP镜像
HARBOR_ADDR="192.168.1.61:80"
docker pull ghcr.io/argoproj-labs/argocd-vault-plugin:v1.17.0
docker tag ghcr.io/argoproj-labs/argocd-vault-plugin:v1.17.0 \
  ${HARBOR_ADDR}/argoproj-labs/argocd-vault-plugin:v1.17.0
docker push ${HARBOR_ADDR}/argoproj-labs/argocd-vault-plugin:v1.17.0
```

**配置Repo Server使用AVP：**

```yaml
# 修改argocd-repo-server Deployment
apiVersion: apps/v1  # API 版本
kind: Deployment  # K8s 部署
metadata:
  name: argocd-repo-server
  namespace: argocd
spec:
  template:
    spec:
      containers:
      - name: argocd-repo-server
        volumeMounts:
        - name: custom-tools
          mountPath: /usr/local/bin/argocd-vault-plugin
          subPath: argocd-vault-plugin
        env:
        - name: AVP_TYPE
          value: vault
        - name: VAULT_ADDR
          value: http://vault.demo.svc.cluster.local:8200
        - name: VAULT_TOKEN
          valueFrom:
            secretKeyRef:
              name: vault-token
              key: token
      initContainers:
      - name: download-tools
        image: 192.168.1.61:80/library/busybox:1.36  # 镜像地址(Harbor)
        command:
        - sh
        - -c
        - |
          wget -O /custom-tools/argocd-vault-plugin \
            https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.17.0/argocd-vault-plugin_1.17.0_linux_amd64
          chmod +x /custom-tools/argocd-vault-plugin
        volumeMounts:
        - name: custom-tools
          mountPath: /custom-tools
      volumes:
      - name: custom-tools
        emptyDir: {}
```

**在manifest中使用占位符：**

```yaml
apiVersion: v1  # API 版本
kind: Secret
metadata:
  name: db-credentials
  namespace: demo
  annotations:
    avp.kubernetes.io/path: "secret/data/demo/db"
type: Opaque  # 通用 Secret 类型
stringData:
  username: <username>
  password: <password>
  host: <host>
---
apiVersion: apps/v1  # API 版本
kind: Deployment  # K8s 部署
metadata:
  name: demo-app
  namespace: demo
spec:
  replicas: 1  # 副本数: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: app
        image: 192.168.1.61:80/demo/app:v1.0.0  # 镜像地址(Harbor)
        env:
        - name: DB_USERNAME
          value: <path:secret/data/demo/db#username>
        - name: DB_PASSWORD
          value: <path:secret/data/demo/db#password>
```

**配置ArgoCD ConfigMap（配置映射）启用AVP：**

```yaml
apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: argocd-cm
  namespace: argocd
data:
  configManagementPlugins: |
    - name: argocd-vault-plugin
      generate:
        command: [argocd-vault-plugin]
        args: [generate, ./]
```

### 4.9.5 敏感数据加密最佳实践

| 实践 | 说明 |
|------|------|
| **密钥分离** | 加密密钥与加密数据分开存储，密钥存K8s Secret，加密数据存Git |
| **定期轮换** | 定期轮换Sealed Secrets密钥和Vault Token |
| **最小权限** | 为ArgoCD/Vault配置最小权限的ServiceAccount（服务账户） |
| **审计日志** | 启用Vault和ArgoCD的审计日志，记录Secret访问 |
| **网络隔离** | Vault和ESO Controller部署在独立命名空间，配置NetworkPolicy（网络策略） |
| **备份策略** | 定期备份Sealed Secrets私钥（用于灾难恢复） |
| **环境隔离** | 不同环境使用不同的加密密钥，避免密钥泄露影响所有环境 |

**Sealed Secrets私钥备份与恢复：**

```bash
# 备份私钥（重要！）
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml

# 恢复私钥（新集群）
kubectl apply -f sealed-secrets-key-backup.yaml

# 重启Controller以加载私钥
kubectl rollout restart deployment sealed-secrets-controller -n kube-system
```

---

## 5. 配置详解 / 高级功能

### 5.1 Sync 策略详解

```
Sync Policy 选项：

automated:  # 启用自动同步
  prune: true          # 自动删除 Git 中不存在的资源
  selfHeal: true       # 自动修复手动修改（Self-Heal）
  allowEmpty: false    # 不允许空目录

syncOptions:
  CreateNamespace=true     # 自动创建目标命名空间
  PrunePropagationPolicy=foreground  # 前台级联删除
  PruneLast=true           # 最后执行 prune（避免依赖问题）
  ServerSideApply=true     # 使用 SSA 替代 Client-side Apply
  RespectIgnoreDifferences=true  # 尊重忽略差异配置

retry:
  limit: 3                 # 最大重试次数
  backoff:
    duration: 5s           # 初始退避时间
    factor: 2              # 退避因子
    maxDuration: 3m        # 最大退避时间
```

### 5.2 Sync Hooks

```bash
# Sync Hook 类型
# PreSync:    Sync 之前执行（如数据库迁移、通知）
# PostSync:   Sync 成功后执行（如健康检查、通知）
# SyncFail:   Sync 失败后执行（如告警、回滚）
# PreDelete:  删除资源之前执行（如数据备份）

# PostSync Hook 示例（健康检查）
cat <<'EOF' > post-sync-healthcheck.yaml
apiVersion: batch/v1  # API 版本
kind: Job  # K8s 任务
metadata:
  name: post-sync-healthcheck
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded  # 成功后自动删除
    argocd.argoproj.io/hook-weight: "10"
spec:
  template:
    spec:
      containers:
      - name: healthcheck
        image: 192.168.1.61:80/library/busybox:1.36  # 镜像地址(Harbor)
        command:
        - sh
        - -c
        - |
          echo "Waiting for deployment to be ready..."
          sleep 10
          wget -qO- http://demo-app.demo.svc.cluster.local/actuator/health || exit 1
          echo "Health check passed!"
      restartPolicy: Never
  backoffLimit: 2
EOF

# SyncFail Hook 示例（告警通知）
cat <<'EOF' > sync-fail-alert.yaml
apiVersion: batch/v1  # API 版本
kind: Job  # K8s 任务
metadata:
  name: sync-fail-alert
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: HookSucceeded  # 成功后自动删除
spec:
  template:
    spec:
      containers:
      - name: alert
        image: 192.168.1.61:80/curlimages/curl:8.0  # 镜像地址(Harbor)
        command:
        - sh
        - -c
        - |
          curl -X POST "http://192.168.1.61:3000/demo/webhook" \
            -H "Content-Type: application/json" \
            -d '{"text":"ArgoCD Sync FAILED for demo-app"}'
      restartPolicy: Never
  backoffLimit: 1
EOF
```

### 5.3 Sync Window（同步窗口）

```bash
# 配置 Sync Window（限制 Sync 时间段）
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AppProject  # ArgoCD 项目
metadata:
  name: demo
  namespace: argocd
spec:
  syncWindows:
  - kind: allow
    schedule: "0 10 * * 1-5"    # 工作日 10:00
    duration: 8h                 # 持续 8 小时
    applications:
    - "*"
    manualSync: true             # 窗口外允许手动 Sync
  - kind: deny
    schedule: "0 0 1 1 *"       # 1 月 1 日禁止 Sync
    duration: 24h
    applications:
    - "*"
EOF
```

### 5.4 Ignore Differences（忽略差异）

```bash
# 配置资源差异忽略（避免 Self-Heal 误回滚）
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: demo-app
  namespace: argocd
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment  # K8s 部署
    jsonPointers:
    - /spec/replicas           # 忽略副本数差异（HPA 管理）
  - group: ""
    kind: Service  # K8s 服务
    jsonPointers:
    - /spec/clusterIP          # 忽略自动分配的 ClusterIP
  - group: ""
    kind: ConfigMap  # K8s 配置映射
    jqPathExpressions:
    - .data.lastUpdated        # 忽略动态更新的字段
  source:
    repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
    targetRevision: main  # Git 分支
    path: k8s/demo-app
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: demo  # 目标命名空间
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
EOF
```

---

## 5.5 Argo Rollouts渐进式交付

### 5.5.1 Argo Rollouts架构与安装

Argo Rollouts是ArgoCD的姊妹项目，专门用于实现渐进式交付（Progressive Delivery），支持金丝雀发布、蓝绿部署、A/B测试等高级部署策略。

**架构图：**

```
+================================================================+
|                   Argo Rollouts 架构                            |
+================================================================+
|                                                                 |
|  +------------------+                                          |
|  | Argo Rollouts    |                                          |
|  | Controller       |                                          |
|  | (管理Rollout CRD)|                                          |
|  +--------+---------+                                          |
|           |                                                     |
|     +-----+-----+                                               |
|     |           |                                               |
|     v           v                                               |
| +--------+  +--------+  +----------+                           |
| | Analysis|  | Rollout |  | Ingress  |                           |
| | Service |  | CRD     |  | Controller|                           |
| | (Prom.  |  | (替换   |  | (Istio/   |                           |
| |  Datadog)|  |  Deployment)|  |  Nginx)   |                           |
| +--------+  +--------+  +----------+                           |
|                                                                 |
+================================================================+
```

**离线镜像准备：**

```bash
HARBOR_ADDR="192.168.1.61:80"

# Argo Rollouts镜像
docker pull quay.io/argoproj/argo-rollouts:v1.6.6
docker tag quay.io/argoproj/argo-rollouts:v1.6.6 \
  ${HARBOR_ADDR}/argoproj/argo-rollouts:v1.6.6
docker push ${HARBOR_ADDR}/argoproj/argo-rollouts:v1.6.6

# kubectl-argo-rollouts插件（CLI工具）
# 下载: https://github.com/argoproj/argo-rollouts/releases/download/v1.6.6/kubectl-argo-rollouts-linux-amd64
```

**安装Argo Rollouts：**

```bash
# 下载安装清单
curl -o argo-rollouts-install.yaml \
  https://github.com/argoproj/argo-rollouts/releases/download/v1.6.6/install.yaml

# 修改镜像地址
sed -i 's|quay.io/argoproj/argo-rollouts:|192.168.1.61:80/argoproj/argo-rollouts:|g' \
  argo-rollouts-install.yaml

# 安装
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f argo-rollouts-install.yaml

# 验证安装
kubectl get pods -n argo-rollouts
kubectl get crd | grep rollout
```

**安装kubectl插件：**

```bash
# 离线安装kubectl-argo-rollouts
curl -LO https://github.com/argoproj/argo-rollouts/releases/download/v1.6.6/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# 验证
kubectl argo rollouts version
```

### 5.5.2 金丝雀发布(Canary)配置

金丝雀发布逐步将流量从旧版本迁移到新版本，通过监控指标决定是否继续推进或回滚。

**金丝雀发布流程图：**

```
+================================================================+
|                    金丝雀发布流程                               |
+================================================================+
|                                                                 |
|  100%流量        90%流量         50%流量         0%流量        |
|  +------+      +------+       +------+       +------+         |
|  | 旧版 |      | 旧版 |       | 旧版 |       | 新版 |         |
|  | v1   |  ->  | v1   |   ->  | v1   |  ->   | v2   |         |
|  +------+      +--+---+       +--+---+       +------+         |
|                 |  ^           |  ^                            |
|                 |  |           |  |                            |
|                 v  |           v  |                            |
|               +------+       +------+                         |
|               | 新版 |       | 新版 |                         |
|               | v2   |       | v2   |                         |
|               | 10%  |       | 50%  |                         |
|               +------+       +------+                         |
|                                                                 |
|  步骤1: 启动   步骤2: 10%流量  步骤3: 50%流量  步骤4: 100%     |
|         新版    分析通过       分析通过        删除旧版        |
|                                                                 |
+================================================================+
```

**Canary Rollout配置示例：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Rollout
metadata:
  name: demo-app
  namespace: demo
spec:
  replicas: 5  # 副本数: 5
  strategy:
    canary:
      # 金丝雀步骤配置
      steps:
      # 步骤1: 部署新版本，但不切换流量（仅验证启动）
      - setWeight: 0
      - pause: {duration: 2m}
      
      # 步骤2: 切换10%流量到新版本
      - setWeight: 10
      - pause: {duration: 5m}
      
      # 步骤3: 执行自动分析（基于Prometheus指标）
      - analysis:
          templates:
          - templateName: success-rate
      
      # 步骤4: 切换50%流量
      - setWeight: 50
      - pause: {duration: 5m}
      
      # 步骤5: 再次分析
      - analysis:
          templates:
          - templateName: success-rate
      
      # 步骤6: 切换100%流量
      - setWeight: 100
      
      # 自动回滚配置
      autoPromotionEnabled: false  # 需要手动确认才能全量
      
      # 服务配置
      canaryService: demo-app-canary
      stableService: demo-app-stable
      trafficRouting:
        nginx:
          stableIngress: demo-app-ingress
          annotationPrefix: nginx.ingress.kubernetes.io
  
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: demo-app
        image: 192.168.1.61:80/demo/app:v2.0.0  # 镜像地址(Harbor)
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m  # CPU 100m
            memory: 128Mi  # 内存 128Mi
---
# 稳定版Service
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: demo-app-stable
  namespace: demo
spec:
  selector:
    app: demo-app
  ports:
  - port: 80
    targetPort: 8080
---
# 金丝雀版Service
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: demo-app-canary
  namespace: demo
spec:
  selector:
    app: demo-app
  ports:
  - port: 80
    targetPort: 8080
```

**AnalysisTemplate配置（自动分析）：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AnalysisTemplate
metadata:
  name: success-rate
  namespace: demo
spec:
  metrics:
  - name: success-rate
    interval: 1m
    count: 3
    successCondition: result[0] >= 0.95
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          sum(rate(http_requests_total{service="demo-app-canary",status=~"2.."}[1m]))
          /
          sum(rate(http_requests_total{service="demo-app-canary"}[1m]))
  - name: latency
    interval: 1m
    count: 3
    successCondition: result[0] <= 200
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          histogram_quantile(0.99, 
            sum(rate(http_request_duration_seconds_bucket{service="demo-app-canary"}[1m])) by (le)
          ) * 1000
```

**执行金丝雀发布：**

```bash
# 应用Rollout配置
kubectl apply -f canary-rollout.yaml

# 查看发布状态
kubectl argo rollouts get rollout demo-app -n demo --watch

# 手动推进到下一步
kubectl argo rollouts promote demo-app -n demo

# 中止发布（回滚）
kubectl argo rollouts abort demo-app -n demo

# 查看发布历史
kubectl argo rollouts history demo-app -n demo
```

### 5.5.3 蓝绿部署(Blue/Green)配置

蓝绿部署同时运行两个版本，通过切换Service流量实现即时回滚。

**蓝绿部署架构图：**

```
+================================================================+
|                    蓝绿部署架构                                 |
+================================================================+
|                                                                 |
|  阶段1: 部署绿版                 阶段2: 切换流量                |
|                                                                 |
|  +----------+                   +----------+                   |
|  | Ingress  |                   | Ingress  |                   |
|  | (蓝版)   |                   | (绿版)   |                   |
|  +----+-----+                   +----+-----+                   |
|       |                              |                         |
|       v                              v                         |
|  +----------+                   +----------+                   |
|  | Service  |                   | Service  |                   |
|  | demo-app |                   | demo-app |                   |
|  +----+-----+                   +----+-----+                   |
|       |                              |                         |
|       v                              v                         |
|  +----------+  +----------+     +----------+  +----------+     |
|  | Blue     |  | Green    |     | Blue     |  | Green    |     |
|  | (Active) |  | (Preview)|     | (Standby)|  | (Active) |     |
|  | v1.0.0   |  | v2.0.0   |     | v1.0.0   |  | v2.0.0   |     |
|  | 100%     |  | 0%       |     | 0%       |  | 100%     |     |
|  +----------+  +----------+     +----------+  +----------+     |
|                                                                 |
+================================================================+
```

**Blue/Green Rollout配置：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Rollout
metadata:
  name: demo-app-bg
  namespace: demo
spec:
  replicas: 3  # 副本数: 3
  strategy:
    blueGreen:
      # 活跃版Service（接收生产流量）
      activeService: demo-app-active
      
      # 预览版Service（用于验证新版本）
      previewService: demo-app-preview
      
      # 自动切换流量前暂停（手动确认）
      autoPromotionEnabled: false
      
      # 自动切换前的等待时间（如果启用autoPromotion）
      autoPromotionSeconds: 300
      
      # 最大不可用Pod数
      maxUnavailable: 0
      
      # 切换前执行的Analysis
      prePromotionAnalysis:
        templates:
        - templateName: smoke-tests
        args:
        - name: service-url
          value: http://demo-app-preview.demo.svc.cluster.local
      
      # 切换后执行的Analysis
      postPromotionAnalysis:
        templates:
        - templateName: success-rate
  
  selector:
    matchLabels:
      app: demo-app-bg
  template:
    metadata:
      labels:
        app: demo-app-bg
    spec:
      containers:
      - name: demo-app
        image: 192.168.1.61:80/demo/app:v2.0.0  # 镜像地址(Harbor)
        ports:
        - containerPort: 8080
---
# 活跃版Service（生产流量）
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: demo-app-active
  namespace: demo
spec:
  selector:
    app: demo-app-bg
    # Rollout会自动添加blue-green相关标签
  ports:
  - port: 80
    targetPort: 8080
---
# 预览版Service（验证用）
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: demo-app-preview
  namespace: demo
spec:
  selector:
    app: demo-app-bg
  ports:
  - port: 80
    targetPort: 8080
```

**Smoke Test Analysis配置：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AnalysisTemplate
metadata:
  name: smoke-tests
  namespace: demo
spec:
  args:
  - name: service-url
  metrics:
  - name: smoke-test
    provider:
      job:
        spec:
          template:
            spec:
              containers:
              - name: test
                image: 192.168.1.61:80/library/busybox:1.36  # 镜像地址(Harbor)
                command:
                - sh
                - -c
                - |
                  # 健康检查
                  wget -qO- {{args.service-url}}/actuator/health || exit 1
                  # API测试
                  wget -qO- {{args.service-url}}/api/v1/status || exit 1
                  echo "Smoke tests passed!"
              restartPolicy: Never
```

**执行蓝绿部署：**

```bash
# 应用配置
kubectl apply -f bluegreen-rollout.yaml

# 查看状态
kubectl argo rollouts get rollout demo-app-bg -n demo --watch

# 预览新版本（通过preview service）
# 验证通过后，手动切换流量
kubectl argo rollouts promote demo-app-bg -n demo

# 如果发现问题，立即回滚到蓝版
kubectl argo rollouts abort demo-app-bg -n demo
```

### 5.5.4 自动分析(Analysis)与回滚

Analysis是Argo Rollouts的核心功能，支持多种指标源和复杂的判断逻辑。

**支持的指标源：**

| 源 | 用途 | 示例 |
|----|------|------|
| Prometheus | 应用指标 | 成功率、延迟、错误率 |
| Datadog | APM指标 | 服务性能指标 |
| CloudWatch | AWS指标 | 基础设施指标 |
| New Relic | APM指标 | 应用性能 |
| Web | HTTP测试 | 健康检查、功能测试 |
| Job | K8s Job | 自定义测试脚本 |

**高级AnalysisTemplate示例：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AnalysisTemplate
metadata:
  name: comprehensive-analysis
  namespace: demo
spec:
  args:
  - name: service-name
  - name: namespace
  metrics:
  # 成功率检查
  - name: success-rate
    interval: 30s
    count: 5
    successCondition: result[0] >= 0.99
    failureCondition: result[0] < 0.90
    failureLimit: 2
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          sum(rate(http_requests_total{service="{{args.service-name}}",status=~"2.."}[2m]))
          /
          sum(rate(http_requests_total{service="{{args.service-name}}"}[2m]))
  
  # P99延迟检查
  - name: p99-latency
    interval: 30s
    count: 5
    successCondition: result[0] <= 500
    failureCondition: result[0] > 1000
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket{service="{{args.service-name}}"}[2m])) by (le)
          ) * 1000
  
  # 错误率检查
  - name: error-rate
    interval: 30s
    count: 5
    successCondition: result[0] <= 0.01
    failureCondition: result[0] > 0.05
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          sum(rate(http_requests_total{service="{{args.service-name}}",status=~"5.."}[2m]))
          /
          sum(rate(http_requests_total{service="{{args.service-name}}"}[2m]))
  
  # 自定义Job测试
  - name: integration-test
    provider:
      job:
        spec:
          template:
            spec:
              containers:
              - name: test
                image: 192.168.1.61:80/demo/test-runner:v1.0  # 镜像地址(Harbor)
                env:
                - name: SERVICE_URL
                  value: "http://{{args.service-name}}.{{args.namespace}}.svc.cluster.local"
                command:
                - /run-tests.sh
              restartPolicy: Never
```

**自动回滚配置：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Rollout
metadata:
  name: demo-app-auto
  namespace: demo
spec:
  replicas: 5  # 副本数: 5
  strategy:
    canary:
      steps:
      - setWeight: 20
      - analysis:
          templates:
          - templateName: comprehensive-analysis
          args:
          - name: service-name
            value: demo-app-canary
          - name: namespace
            value: demo
      - setWeight: 50
      - analysis:
          templates:
          - templateName: comprehensive-analysis
          args:
          - name: service-name
            value: demo-app-canary
          - name: namespace
            value: demo
      - setWeight: 100
      
      # 自动回滚配置
      abortScaleDownDelaySeconds: 30  # 中止后缩容延迟
      scaleDownDelaySeconds: 600      # 成功后的旧版缩容延迟
      scaleDownDelayRevisionLimit: 2  # 保留的旧版Revision数量
  
  # 回滚窗口（保留历史版本）
  revisionHistoryLimit: 10
```

**监控发布状态：**

```bash
# 实时查看发布进度
kubectl argo rollouts get rollout demo-app-auto -n demo --watch

# 查看Analysis运行状态
kubectl get analysis -n demo
kubectl describe analysis <analysis-name> -n demo

# 查看详细事件
kubectl argo rollouts get rollout demo-app-auto -n demo

# 查看历史版本
kubectl argo rollouts history demo-app-auto -n demo
```

### 5.5.5 与Istio集成实现流量分割

Istio提供更细粒度的流量控制能力，支持基于Header、权重、来源等条件的路由。

**架构图：**

```
+================================================================+
|                Argo Rollouts + Istio 架构                       |
+================================================================+
|                                                                 |
|  +------------------+                                          |
|  | Istio Gateway    |                                          |
|  | (入口流量)        |                                          |
|  +--------+---------+                                          |
|           |                                                     |
|           v                                                     |
|  +------------------+                                          |
|  | VirtualService   |  <-- Argo Rollouts动态修改权重           |
|  | (流量路由规则)    |                                          |
|  +--------+---------+                                          |
|           |                                                     |
|     +-----+-----+                                               |
|     |           |                                               |
|     v           v                                               |
| +--------+  +--------+                                         |
| | Stable |  | Canary |                                         |
| | Pods   |  | Pods   |                                         |
| | (v1)   |  | (v2)   |                                         |
| +--------+  +--------+                                         |
|                                                                 |
+================================================================+
```

**Istio VirtualService（虚拟服务）配置：**

```yaml
apiVersion: networking.istio.io/v1beta1  # Istio 网络 API 版本
kind: VirtualService  # Istio 虚拟服务
metadata:
  name: demo-app-vs
  namespace: demo
spec:
  hosts:
  - demo-app.demo.svc.cluster.local
  - demo-app.example.com
  gateways:
  - demo-app-gateway
  http:
  - match:
    - headers:
        canary:
          exact: "true"
    route:
    - destination:
        host: demo-app-canary
      weight: 100
  - route:
    - destination:
        host: demo-app-stable
      weight: 100
---
apiVersion: networking.istio.io/v1beta1  # Istio 网络 API 版本
kind: Gateway
metadata:
  name: demo-app-gateway
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - demo-app.example.com
```

**Istio集成Rollout配置：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Rollout
metadata:
  name: demo-app-istio
  namespace: demo
spec:
  replicas: 5  # 副本数: 5
  strategy:
    canary:
      canaryService: demo-app-canary
      stableService: demo-app-stable
      trafficRouting:
        istio:
          virtualService:
            name: demo-app-vs
            routes:
            - primary
          destinationRule:
            name: demo-app-dr
            canarySubsetName: canary
            stableSubsetName: stable
      steps:
      - setWeight: 10
      - pause: {duration: 5m}
      - analysis:
          templates:
          - templateName: istio-success-rate
      - setWeight: 25
      - pause: {duration: 5m}
      - analysis:
          templates:
          - templateName: istio-success-rate
      - setWeight: 50
      - pause: {duration: 5m}
      - analysis:
          templates:
          - templateName: istio-success-rate
      - setWeight: 100
  selector:
    matchLabels:
      app: demo-app-istio
  template:
    metadata:
      labels:
        app: demo-app-istio
    spec:
      containers:
      - name: demo-app
        image: 192.168.1.61:80/demo/app:v2.0.0  # 镜像地址(Harbor)
        ports:
        - containerPort: 8080
---
apiVersion: networking.istio.io/v1beta1  # Istio 网络 API 版本
kind: DestinationRule
metadata:
  name: demo-app-dr
  namespace: demo  # 目标命名空间
spec:
  host: demo-app-istio
  subsets:
  - name: stable
    labels:
      app: demo-app-istio
  - name: canary
    labels:
      app: demo-app-istio
```

**Istio指标分析：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AnalysisTemplate
metadata:
  name: istio-success-rate
  namespace: demo
spec:
  metrics:
  - name: istio-success-rate
    interval: 1m
    count: 3
    successCondition: result[0] >= 0.99
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          sum(rate(istio_requests_total{
            reporter="destination",
            destination_service=~"demo-app-canary.demo.svc.cluster.local",
            response_code!~"5.."
          }[1m]))
          /
          sum(rate(istio_requests_total{
            reporter="destination",
            destination_service=~"demo-app-canary.demo.svc.cluster.local"
          }[1m]))
  - name: istio-latency
    interval: 1m
    count: 3
    successCondition: result[0] <= 500
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          histogram_quantile(0.99,
            sum(rate(istio_request_duration_milliseconds_bucket{
              reporter="destination",
              destination_service=~"demo-app-canary.demo.svc.cluster.local"
            }[1m])) by (le)
          )
```

**测试Istio流量分割：**

```bash
# 发送普通流量（到stable版本）
for i in {1..100}; do
  curl -s http://demo-app.example.com/api/status
done

# 发送金丝雀流量（到canary版本）
for i in {1..100}; do
  curl -s -H "canary: true" http://demo-app.example.com/api/status
done

# 查看Istio流量分布
kubectl exec -it deploy/istio-ingressgateway -n istio-system -- \
  curl -s http://localhost:15090/stats/prometheus | grep demo-app
```

---

## 6. 验证与测试

### 6.1 验证 ArgoCD 安装

```bash
# 检查所有组件
kubectl get pods -n argocd
# 预期：所有 Pod Running

# 检查 ArgoCD 版本
argocd version

# 检查集群连接
argocd cluster list

# 检查仓库连接
argocd repo list

# 登录 ArgoCD
argocd login 192.168.1.54:32443 --username admin --password <password> --insecure
```

### 6.2 验证 Application 同步

```bash
# 创建测试 Application
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: test-app
  namespace: argocd
spec:
  project: default  # 所属项目
  source:
    repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
    targetRevision: main  # Git 分支
    path: k8s/test-app
  destination:
    server: https://kubernetes.default.svc  # 目标 K8s 集群
    namespace: demo  # 目标命名空间
  syncPolicy:  # 同步策略
    automated:  # 启用自动同步
      prune: true  # 自动清理多余资源
      selfHeal: true  # 启用自动修复
    syncOptions:
    - CreateNamespace=true  # 自动创建命名空间
EOF

# 手动同步
argocd app sync test-app --watch

# 查看应用状态
argocd app get test-app

# 查看 Sync 状态
argocd app get test-app

# 查看资源树
argocd app manifests test-app | head -50

# 测试 Self-Heal（手动修改资源后自动恢复）
kubectl scale deployment test-app -n demo --replicas=5
# 等待几秒后查看
argocd app get test-app
# 预期：Self-Heal 自动将副本数恢复到 Git 中的值
```

### 6.3 验证 App of Apps

```bash
# 同步根应用
argocd app sync root-app --watch

# 查看所有子应用状态
argocd app list

# 查看根应用树
argocd app tree root-app

# 验证子应用同步
argocd app sync root-app --cascade
```

---

## 6.4 ArgoCD多集群管理

### 6.4.1 使用Cluster Secret注册远程集群

ArgoCD支持管理多个Kubernetes集群，通过Cluster Secret注册远程集群，实现统一的应用交付管理。

**多集群架构图：**

```
+================================================================+
|                   ArgoCD 多集群管理架构                         |
+================================================================+
|                                                                 |
|                    +------------------+                        |
|                    | ArgoCD Server    |                        |
|                    | (管理平面)        |                        |
|                    +--------+---------+                        |
|                             |                                   |
|         +-------------------+-------------------+              |
|         |                   |                   |              |
|         v                   v                   v              |
|  +-------------+     +-------------+     +-------------+      |
|  | Cluster 1   |     | Cluster 2   |     | Cluster N   |      |
|  | (生产环境)   |     | (预发环境)   |     | (开发环境)   |      |
|  | 192.168.1.51|     | 192.168.1.52|     | 192.168.1.53|      |
|  +-------------+     +-------------+     +-------------+      |
|                                                                 |
+================================================================+
```

**添加远程集群：**

```bash
# 方式一：使用CLI添加（推荐）
# 前提：当前kubeconfig中有目标集群的上下文
argocd cluster add <context-name> \
  --name production-cluster \
  --server https://192.168.1.51:6443 \
  --insecure

# 示例：添加生产集群
argocd cluster add prod-cluster \
  --name prod-k8s \
  --upsert

# 查看已注册的集群
argocd cluster list
```

**手动创建Cluster Secret：**

```yaml
apiVersion: v1  # API 版本
kind: Secret
metadata:
  name: prod-cluster-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque  # 通用 Secret 类型
stringData:
  name: prod-cluster
  server: https://192.168.1.51:6443
  config: |
    {
      "bearerToken": "<service-account-token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64-encoded-ca-cert>"
      }
    }
---
# 创建具有必要权限的ServiceAccount（在远程集群执行）
apiVersion: v1  # API 版本
kind: ServiceAccount  # 服务账户
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1  # RBAC API 版本
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
- apiGroups: ['*']
  resources: ['*']
  verbs: ['*']
- nonResourceURLs: ['*']
  verbs: ['*']
---
apiVersion: rbac.authorization.k8s.io/v1  # RBAC API 版本
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-role
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: kube-system
```

**获取远程集群凭证脚本：**

```bash
#!/bin/bash
# get-cluster-creds.sh
# 在远程集群执行，生成ArgoCD Cluster Secret

CLUSTER_NAME="prod-cluster"
SERVER_URL="https://192.168.1.51:6443"
NAMESPACE="kube-system"
SA_NAME="argocd-manager"

# 获取Token
TOKEN=$(kubectl -n ${NAMESPACE} get secret \
  $(kubectl -n ${NAMESPACE} get sa ${SA_NAME} -o jsonpath='{.secrets[0].name}') \
  -o jsonpath='{.data.token}' | base64 -d)

# 获取CA证书
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'$(kubectl config current-context)'")].cluster.certificate-authority-data}')

# 生成Secret YAML
cat <<EOF
apiVersion: v1  # API 版本
kind: Secret
metadata:
  name: ${CLUSTER_NAME}-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque  # 通用 Secret 类型
stringData:
  name: ${CLUSTER_NAME}
  server: ${SERVER_URL}
  config: |
    {
      "bearerToken": "${TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${CA_DATA}"
      }
    }
EOF
```

### 6.4.2 集群分片(Sharding)分散负载

当管理大量集群时，使用Sharding将集群分散到多个ArgoCD Controller实例，提高并发处理能力。

**Sharding架构图：**

```
+================================================================+
|                   ArgoCD Sharding 架构                          |
+================================================================+
|                                                                 |
|  +------------------+                                          |
|  | ArgoCD Server    |                                          |
|  +--------+---------+                                          |
|           |                                                     |
|  +--------+---------+                                          |
|  | Load Balancer    |                                          |
|  +--------+---------+                                          |
|           |                                                     |
|     +-----+-----+                                               |
|     |           |                                               |
|     v           v                                               |
| +-------+   +-------+                                          |
| | Ctrl 0|   | Ctrl 1|                                          |
| |Shard 0|   |Shard 1|                                          |
| +---+---+   +---+---+                                          |
|     |           |                                               |
|  +--+--+     +--+--+                                           |
|  |C1,C2|     |C3,C4|                                           |
|  +-----+     +-----+                                           |
|                                                                 |
+================================================================+
```

**启用Sharding配置：**

```yaml
# argocd-application-controller StatefulSet
apiVersion: apps/v1  # API 版本
kind: StatefulSet
metadata:
  name: argocd-application-controller
  namespace: argocd
spec:
  replicas: 3  # 3个Controller实例
  template:
    spec:
      containers:
      - name: argocd-application-controller
        command:
        - argocd-application-controller
        - --status-processors
        - "20"
        - --operation-processors
        - "10"
        - --repo-server-timeout-seconds
        - "60"
        - --shard-number  # 自动分配shard编号
        env:
        - name: ARGOCD_CONTROLLER_REPLICAS
          value: "3"
```

**手动分配集群到Shard：**

```yaml
apiVersion: v1  # API 版本
kind: Secret
metadata:
  name: prod-cluster-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    # 指定shard编号（0, 1, 2...）
    argocd.argoproj.io/shard: "0"
type: Opaque  # 通用 Secret 类型
stringData:
  name: prod-cluster
  server: https://192.168.1.51:6443
  config: '{...}'
```

**Sharding策略：**

| 策略 | 说明 | 适用场景 |
|------|------|----------|
| 轮询(Round Robin) | 自动平均分配集群 | 集群规模相近 |
| 按环境分片 | 生产、预发、开发分别由不同Controller管理 | 环境隔离需求 |
| 按地域分片 | 不同地域集群由不同Controller管理 | 多地域部署 |
| 手动分配 | 显式指定每个集群的shard编号 | 精细控制 |

### 6.4.3 ApplicationSet按集群生成应用

ApplicationSet的Cluster Generator可以根据注册的集群自动生成Application，实现多集群应用的一键部署。

**Cluster Generator架构：**

```
+================================================================+
|              ApplicationSet Cluster Generator                   |
+================================================================+
|                                                                 |
|  +------------------+                                          |
|  | ApplicationSet   |                                          |
|  | Cluster Generator|                                          |
|  +--------+---------+                                          |
|           |                                                     |
|     +-----+-----+                                               |
|     |           |                                               |
|     v           v                                               |
| +--------+  +--------+                                         |
| | Cluster|  | Cluster|                                         |
| | Prod   |  | Staging|                                         |
| +---+----+  +---+----+                                         |
|     |           |                                               |
|     v           v                                               |
| +--------+  +--------+                                         |
| | App    |  | App    |                                         |
| | Prod   |  | Staging|                                         |
| +--------+  +--------+                                         |
|                                                                 |
+================================================================+
```

**Cluster Generator配置：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: multi-cluster-apps
  namespace: argocd
spec:
  generators:
  # 基于集群列表生成
  - clusters:
      selector:
        matchLabels:
          env: production
      values:
        replicaCount: "5"
        resources: "high"
  - clusters:
      selector:
        matchLabels:
          env: staging
      values:
        replicaCount: "2"
        resources: "medium"
  - clusters:
      selector:
        matchLabels:
          env: development
      values:
        replicaCount: "1"
        resources: "low"
  
  template:
    metadata:
      name: '{{name}}-demo-app'
      labels:
        cluster: '{{name}}'
    spec:
      project: default  # 所属项目
      source:
        repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
        targetRevision: main  # Git 分支
        path: charts/demo-app
        helm:
          parameters:
          - name: replicaCount  # 副本数量
            value: '{{values.replicaCount}}'
          - name: resourcesPreset
            value: '{{values.resources}}'
          valueFiles:
          - values.yaml
          - 'values-{{metadata.labels.env}}.yaml'
      destination:
        server: '{{server}}'
        namespace: demo  # 目标命名空间
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: true  # 启用自动修复
        syncOptions:
        - CreateNamespace=true  # 自动创建命名空间
```

**集群标签配置：**

```yaml
# 为Cluster Secret添加标签
apiVersion: v1  # API 版本
kind: Secret
metadata:
  name: prod-cluster-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    env: production
    region: cn-north
    team: platform
type: Opaque  # 通用 Secret 类型
stringData:
  name: prod-cluster
  server: https://192.168.1.51:6443
  config: '{...}'
```

**Matrix Generator（多维度组合）：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: matrix-apps
  namespace: argocd
spec:
  generators:
  # Matrix Generator：集群 x 应用组合
  - matrix:
      generators:
      # 维度1：集群列表
      - clusters:
          selector:
            matchLabels:
              env: production
      # 维度2：应用列表
      - list:
          elements:
          - app: user-service
            path: services/user-service
            port: "8080"  # 服务端口
          - app: order-service
            path: services/order-service
            port: "8081"  # 服务端口
          - app: payment-service
            path: services/payment-service
            port: "8082"  # 服务端口
  
  template:
    metadata:
      name: '{{name}}-{{app}}'
    spec:
      project: default  # 所属项目
      source:
        repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
        targetRevision: main  # Git 分支
        path: '{{path}}'
        helm:
          parameters:
          - name: clusterName
            value: '{{name}}'
          - name: servicePort
            value: '{{port}}'
      destination:
        server: '{{server}}'
        namespace: '{{app}}'
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: true  # 启用自动修复
```

### 6.4.4 跨集群应用同步策略

在多集群场景下，需要制定合理的同步策略，确保应用在各集群的一致性和可靠性。

**同步策略对比：**

| 策略 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| 并行同步 | 所有集群同时同步 | 速度快 | 风险集中 |
| 串行同步 | 按顺序逐个集群同步 | 风险分散 | 速度慢 |
| 金丝雀发布 | 先小集群后大集群 | 风险可控 | 配置复杂 |
| 环境隔离 | 不同环境不同Git分支 | 灵活性高 | 维护成本高 |

**串行同步配置（使用Sync Wave）：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: dev-demo-app
  namespace: argocd
  annotations:
    # 开发环境先同步
    argocd.argoproj.io/sync-wave: "1"
spec:
  destination:
    server: https://192.168.1.53:6443  # dev集群
  # ...
---
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: staging-demo-app
  namespace: argocd
  annotations:
    # 预发环境后同步
    argocd.argoproj.io/sync-wave: "2"
spec:
  destination:
    server: https://192.168.1.52:6443  # staging集群
  # ...
---
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Application  # ArgoCD 应用
metadata:
  name: prod-demo-app
  namespace: argocd
  annotations:
    # 生产环境最后同步
    argocd.argoproj.io/sync-wave: "3"
spec:
  destination:
    server: https://192.168.1.51:6443  # prod集群
  # ...
```

**金丝雀多集群发布：**

```yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: canary-cluster-deployment
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      # 第一波：小集群
      - cluster: small-prod-1
        server: https://192.168.1.61:6443
        wave: "1"
        targetRevision: main  # Git 分支
      - cluster: small-prod-2
        server: https://192.168.1.62:6443
        wave: "1"
        targetRevision: main  # Git 分支
      # 第二波：中等集群
      - cluster: medium-prod-1
        server: https://192.168.1.71:6443
        wave: "2"
        targetRevision: main  # Git 分支
      # 第三波：大集群
      - cluster: large-prod-1
        server: https://192.168.1.81:6443
        wave: "3"
        targetRevision: main  # Git 分支
  
  template:
    metadata:
      name: '{{cluster}}-demo-app'
      annotations:
        argocd.argoproj.io/sync-wave: '{{wave}}'
    spec:
      project: default  # 所属项目
      source:
        repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
        targetRevision: '{{targetRevision}}'
        path: charts/demo-app
      destination:
        server: '{{server}}'
        namespace: demo  # 目标命名空间
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: false  # 生产环境建议手动确认
```

**多集群健康检查：**

```bash
# 查看所有集群状态
argocd cluster list

# 查看特定集群的应用
argocd app list --selector cluster=prod-cluster

# 批量同步特定集群的应用
for app in $(argocd app list -o name --selector cluster=prod-cluster); do
  argocd app sync $app --async
done

# 检查多集群应用健康状态
kubectl get applications -n argocd -o json | jq -r '
  .items[] | 
  select(.spec.destination.server != "https://kubernetes.default.svc") |
  "\(.metadata.name): \(.status.sync.status) - \(.status.health.status)"
'
```

**跨集群Secret管理：**

```yaml
# 使用Sealed Secrets在每个集群独立解密
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: sealed-secrets-multi-cluster
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          argocd.argoproj.io/secret-type: cluster
  template:
    metadata:
      name: '{{name}}-sealed-secrets'
    spec:
      project: default  # 所属项目
      source:
        repoURL: http://192.168.1.61:3000/demo/demo-manifests.git
        targetRevision: main  # Git 分支
        path: infra/sealed-secrets
      destination:
        server: '{{server}}'
        namespace: kube-system
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: true  # 启用自动修复
---
# 每个集群的Secret使用各自的公钥加密
# 加密时指定集群：kubeseal --cert cluster1-cert.pem ...
# 加密时指定集群：kubeseal --cert cluster2-cert.pem ...
```

---

## 7. CKA/CKS 考点融入

### 7.1 CKA 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| CRD | Application CRD 定义和使用 | 4.3 节 |
| RBAC | ArgoCD RBAC、Project 权限 | 4.8 节 |
| Namespace | 多环境命名空间隔离 | 4.6 节 |
| Label/Annotation | Application 标签和注解 | 4.3 节 |
| Helm | ArgoCD Helm 集成 | 4.4 节 |

### 7.2 CKS 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Secret 管理 | Git 凭证、Helm 仓库密码 | 4.2 节 |
| RBAC | 最小权限原则 | 4.8 节 |
| 网络策略 | ArgoCD 命名空间网络隔离 | 4.1 节 |
| 审计日志 | ArgoCD 操作审计 | 4.8 节 |
| 镜像安全 | 镜像签名验证 | 4.4 节 |

---

## 8. 高频面试题

### Q1: 什么是 GitOps？它和传统的 CI/CD 有什么区别？（难度：简单）

**答案：** GitOps 是一种基于 Git 的持续交付方法，核心思想是将 Git 作为系统的"唯一真实来源"（Single Source of Truth（单一事实来源））。所有基础设施和应用配置都以声明式代码形式存储在 Git 中，通过自动化工具（如 ArgoCD）将 Git 中的期望状态持续同步到 K8s 集群。与传统 CI/CD 的区别：1）**Push vs Pull**：传统 CI/CD 是 Push 模式（CI 工具将变更推送到集群），GitOps 是 Pull 模式（集群内的 Agent 从 Git 拉取配置）；2）**安全性**：GitOps 不需要 CI 工具直接访问 K8s 集群的凭证，降低了安全风险；3）**声明式**：GitOps 使用声明式配置（YAML），传统 CI/CD 可能使用命令式脚本；4）**可审计**：所有变更都通过 Git 提交记录，天然具备审计能力；5）**自愈**：GitOps 持续比较期望状态和实际状态，自动纠正偏差（Self-Heal）。GitOps 更适合 K8s 原生的持续交付场景。

### Q2: ArgoCD 的 Application CRD 有哪些关键字段？（难度：中等）

**答案：** Application CRD 的关键字段包括：**source**：定义配置来源，支持 Git 仓库（repoURL、path、targetRevision）、Helm Chart（chart、repoURL）、Kustomize（kustomize.path）等。**destination**：定义部署目标，包括 server（K8s API Server 地址）和 namespace。**syncPolicy**：定义同步策略，包括 automated（自动同步）、prune（自动清理）、selfHeal（自愈）、syncOptions（同步选项如 CreateNamespace）。**project**：定义所属项目，用于 RBAC 和资源隔离。**ignoreDifferences**：定义需要忽略的资源差异（如 HPA 管理的副本数）。**revisionHistoryLimit**：定义保留的历史版本数量（默认 10）。**syncOptions**：如 ServerSideApply（服务端应用）、PrunePropagationPolicy 等。Application 的状态字段包括：status.sync.status（Synced/OutOfSync）、status.health.status（Healthy/Degraded/Progressing）、status.operationState（当前操作状态）。

### Q3: ArgoCD 的 Auto-Sync 和 Self-Heal 有什么区别？（难度：中等）

**答案：** Auto-Sync 和 Self-Heal 是 ArgoCD 的两个核心自动化功能，但触发条件和行为不同。**Auto-Sync** 在 Git 仓库中的配置发生变更时自动触发 Sync 操作，将新配置应用到 K8s 集群。触发条件是 Git 中的 targetRevision 有新的提交。Auto-Sync 确保集群状态始终与 Git 仓库保持一致。**Self-Heal** 在检测到 K8s 集群中的实际状态与 Git 中的期望状态不一致时（由于手动修改或其他工具修改），自动执行 Sync 操作将集群状态恢复到期望状态。触发条件是集群中资源被手动修改。Self-Heal 确保集群状态不会被意外修改。两者的区别：Auto-Sync 由 Git 变更触发（从 Git 到集群），Self-Heal 由集群变更触发（从集群到 Git 状态恢复）。两者可以同时启用，配合使用实现完全自动化的状态管理。注意：Self-Heal 可能会覆盖运维人员的紧急修改，建议配合 ignoreDifferences 使用。

### Q4: 什么是 App of Apps 模式？有什么优势？（难度：中等）

**答案：** App of Apps 模式是一种 ArgoCD 应用组织模式，通过一个父 Application 管理多个子 Application。父 Application 的 source 指向一个 Git 目录，该目录包含多个子 Application 的 YAML 定义。ArgoCD 会自动发现并管理这些子 Application。优势：1）**统一管理**：通过一个入口管理所有应用，简化操作；2）**原子性**：所有子应用使用相同的 Git revision，确保版本一致性；3）**层级化**：可以按层级组织（根 -> 环境 -> 应用组 -> 应用）；4）**权限控制**：通过 Project 对不同层级的应用进行权限隔离；5）**批量操作**：可以对根应用执行 Sync/Rollback，自动级联到所有子应用。局限性：子应用的 Git 仓库和 revision 必须相同（或使用 ApplicationSet 解决）；子应用的变更需要提交到父应用的 Git 仓库。App of Apps 适合中小规模的应用管理，大规模场景推荐使用 ApplicationSet。

### Q5: ApplicationSet 有哪些 Generator 类型？（难度：困难）

**答案：** ApplicationSet 支持多种 Generator 类型，用于模板化批量生成 Application：1）**List Generator**：直接在 YAML 中定义参数列表，适合固定数量的环境（dev/staging/production）；2）**Cluster Generator**：基于 ArgoCD 管理的多个 K8s 集群自动生成 Application，适合多集群管理；3）**Git Generator**：基于 Git 仓库的目录结构自动生成 Application，每个目录生成一个 Application，适合 monorepo 场景；4）**Git Directory Generator**：Git Generator 的增强版，支持更灵活的目录匹配和路径参数提取；5）**Matrix Generator**：组合多个 Generator 的输出（笛卡尔积），适合多环境 x 多集群的场景；6）**SCM Provider Generator**：基于 GitHub/GitLab 的组织/仓库结构自动生成 Application，适合多团队场景；7）**Pull Request Generator**：为每个 PR 自动创建预览 Application，适合 PR 自动测试。生产环境推荐：固定环境用 List Generator，monorepo 用 Git Directory Generator，多集群用 Cluster Generator。

### Q6: ArgoCD 如何实现回滚？（难度：中等）

**答案：** ArgoCD 支持多种回滚方式：1）**UI 回滚**：在 ArgoCD UI 中查看 Application 的 History（历史版本列表），选择目标版本点击 Rollback，ArgoCD 将集群状态恢复到该版本。2）**CLI 回滚**：`argocd app rollback <app-name> <revision>`，回滚到指定的 revision。3）**Git Revert 回滚**（推荐）：在 Git 仓库中 revert 有问题的提交，ArgoCD 检测到 Git 变更后自动 Sync 回滚后的配置。这是最推荐的回滚方式，因为回滚操作也记录在 Git 历史中，可审计、可追溯。4）**Git Branch 回滚**：将 Git 分支重置到历史提交（`git reset --hard`），强制推送后 ArgoCD 自动同步。注意：此方式会丢失回滚之后的提交历史。推荐使用 Git Revert 方式回滚，因为它保留了完整的提交历史，且符合 GitOps 的声明式理念。配合 Sync Hook 可以在回滚前后执行通知、数据库迁移等操作。

### Q7: 如何在 ArgoCD 中管理多环境配置？（难度：困难）

**答案：** ArgoCD 多环境管理有以下方案：**方案一：多 Git 分支**：每个环境使用独立的 Git 分支（dev/staging/main），每个 Application 的 targetRevision 指向对应分支。缺点是分支间配置差异难以管理。**方案二：Kustomize Overlay**：使用 Kustomize 的 base + overlay 模式，base 定义公共配置，overlay 定义环境差异。ArgoCD 原生支持 Kustomize。**方案三：Helm Values 文件**（推荐）：使用 Helm Chart + 多环境 values 文件（values-dev.yaml、values-staging.yaml、values-production.yaml），通过 ApplicationSet 的 List Generator 为每个环境生成独立的 Application。**方案四：ApplicationSet + Git Generator**：在 Git 仓库中按环境组织目录结构（envs/dev/、envs/staging/、envs/production/），Git Generator 自动为每个目录生成 Application。推荐方案三（Helm Values），因为它最灵活，Helm 的模板能力可以处理复杂的环境差异，且与 CI Pipeline（更新 values 中的镜像 tag）配合良好。

### Q8: ArgoCD 如何保证安全性？（难度：中等）

**答案：** ArgoCD 的安全机制包括多个层面：1）**认证**：支持用户名密码、SSO（Dex 集成 GitHub/GitLab/SAML/OIDC）、单点登录；2）**授权**：RBAC 模型，支持 Project 级别的权限控制，可以定义角色和策略（policy.csv）；3）**Git 凭证安全**：Git 仓库凭证存储在 K8s Secret 中，支持 SSH Key 和 HTTPS Token；4）**网络隔离**：ArgoCD 部署在独立命名空间，通过 NetworkPolicy 限制网络访问；5）**最小权限**：ArgoCD ServiceAccount 只需要应用部署所需的权限，不应赋予 cluster-admin；6）**审计日志**：所有操作记录在 ArgoCD 日志中，可集成到日志收集系统；7）**Sync Window**：限制 Sync 操作的时间段，防止非工作时间误操作；8）**Project 限制**：AppProject 可以限制允许的 Git 仓库、目标命名空间和资源类型，防止越权部署。生产环境建议：启用 SSO、配置严格的 RBAC、使用 Sync Window、启用审计日志。

### Q9: ArgoCD 的 Sync 状态有哪些？如何排查 OutOfSync？（难度：中等）

**答案：** ArgoCD 的 Sync 状态包括：**Synced**：集群状态与 Git 期望状态一致；**OutOfSync**：集群状态与 Git 期望状态不一致（可能是 Git 变更未同步，或集群被手动修改）；**Unknown**：无法确定同步状态（如 Git 仓库不可达）。Health 状态包括：**Healthy**：资源健康；**Degraded**：资源异常（如 Pod CrashLoopBackOff）；**Progressing**：资源正在变更中；**Suspended**：资源被暂停；**Missing**：资源在 Git 中定义但集群中不存在。排查 OutOfSync：1）`argocd app diff <app-name>` 查看具体差异；2）检查 Git 仓库是否有新提交未同步；3）检查是否有人手动修改了集群资源（`kubectl edit`）；4）检查 ignoreDifferences 配置是否遗漏；5）检查 ArgoCD Controller 日志（`kubectl logs -n argocd deploy/argocd-application-controller`）。

### Q10: 如何实现 ArgoCD 与 Tekton 的 CI/CD 集成？（难度：困难）

**答案：** ArgoCD（CD）与 Tekton（CI）的集成方式：1）**标准 GitOps 流程**：Tekton Pipeline 负责 CI（构建镜像、推送 Harbor、更新 Helm values 中的镜像 tag 并提交到 Git）；ArgoCD 负责 CD（Watch Git 变更，自动 Sync 到 K8s）。两者通过 Git 仓库解耦，不直接交互。2）**流程详解**：开发者提交代码 -> Tekton Pipeline 触发（Git Webhook（回调钩子））-> 单元测试 -> 构建镜像 -> 推送到 Harbor -> 更新 Git 仓库中的 values.yaml（修改 image.tag）-> ArgoCD 检测到 Git 变更 -> 自动 Sync 新配置到 K8s。3）**ArgoCD Notification**：ArgoCD 可以在 Sync 成功/失败后发送通知，触发 Tekton Pipeline 执行后续操作（如集成测试、性能测试）。4）**Image Updater**：使用 ArgoCD Image Updater 自动检测 Harbor 中的新镜像版本并更新 Git 中的 image.tag，实现完全自动化的 CI/CD。推荐使用标准 GitOps 流程，CI 和 CD 通过 Git 解耦，各自独立、可替换。

### Q11: ArgoCD 的 Resource Hook 有哪些类型？（难度：中等）

**答案：** ArgoCD 的 Resource Hook 是在 Sync 过程中执行自定义操作的机制，通过 Annotation 标记资源。Hook 类型：**PreSync**：在 Sync 开始之前执行，适用于数据库迁移、缓存清理、前置检查等场景。**PostSync**：在 Sync 成功完成后执行，适用于健康检查、通知、集成测试等场景。**SyncFail**：在 Sync 失败后执行，适用于告警通知、自动回滚等场景。**PreDelete**：在资源被删除之前执行，适用于数据备份、资源清理等场景。Hook 配置注解：`argocd.argoproj.io/hook: <HookType>`；`argocd.argoproj.io/hook-delete-policy: HookSucceeded|HookFailed|BeforeHookCreation`（控制 Hook 资源的清理策略）；`argocd.argoproj.io/hook-weight: <int>`（控制同类型 Hook 的执行顺序，数字越小越先执行）。Hook 资源不会被 ArgoCD 纳入 Application 的资源管理（不会出现在资源树中）。

### Q12: 如何监控 ArgoCD 自身的健康状态？（难度：中等）

**答案：** ArgoCD 自身监控的关键指标：1）**Application 状态**：Synced/OutOfSync/Healthy/Degraded 的数量，通过 ArgoCD API 或 CLI 获取；2）**Controller 性能**：`argocd_app_sync_total`（Sync 总次数）、`argocd_app_sync_duration_seconds`（Sync 耗时）；3）**Repo Server 性能**：`argocd_repo_server_request_total`（请求总数）、`argocd_repo_server_request_duration_seconds`（请求延迟）；4）**Git 操作**：Git 仓库连接状态、Clone/Fetch 耗时；5）**Redis**：Redis 连接状态和内存使用。监控方案：1）部署 ArgoCD Metrics Service（默认已启用）；2）配置 Prometheus ServiceMonitor 采集 ArgoCD metrics；3）创建 Grafana（可视化面板） Dashboard 展示 Application 状态和 Controller 性能；4）配置告警规则：Application OutOfSync > 5 分钟、Application Degraded、Git 仓库连接失败、Controller Pod 重启。ArgoCD 还提供了 `argocd app diff` 和 `argocd app get` 命令用于手动检查。

### Q13: 如何处理 ArgoCD 的 Secret 管理？（难度：困难）

**答案：** ArgoCD 中 Secret 管理的最佳实践：1）**Git 仓库凭证**：使用 SSH Key（推荐）或 HTTPS Token，存储在 ArgoCD 的 Repository Secret 中（`argocd-repo-<hash>`）；2）**Helm Values 中的敏感信息**：不在 Git 中存储明文 Secret，使用以下方案：a) **Sealed Secrets**：使用 Bitnami Sealed Secrets 加密 Secret 后存储在 Git 中，ArgoCD 原生支持；b) **External Secrets Operator**：从外部密钥管理系统（Vault/AWS SM）同步 Secret 到 K8s；c) **Helm Secrets**：使用 helm-secrets + SOPS 加密 values 文件；d) **ArgoCD Vault Plugin**：ArgoCD 原生支持从 HashiCorp Vault 读取 Secret。3）**ArgoCD 自身凭证**：admin 密码存储在 K8s Secret 中，首次登录后应立即修改。推荐方案：使用 Sealed Secrets 或 External Secrets Operator，将加密后的 Secret 存储在 Git 中，ArgoCD 在 Sync 时自动解密。

### Q14: ArgoCD 如何管理多集群部署？（难度：困难）

**答案：** ArgoCD 原生支持多集群部署管理。配置步骤：1）**注册远程集群**：`argocd cluster add <context-name>`，ArgoCD 会在远程集群创建 ServiceAccount 并配置 RBAC；2）**Application 指定目标集群**：在 Application CRD 的 destination.server 中指定远程集群的 API Server 地址；3）**ApplicationSet 多集群**：使用 Cluster Generator 自动为每个注册的集群生成 Application。多集群架构模式：**Hub-Spoke**：一个中心 ArgoCD 管理多个远程集群，适合统一管理场景；**Federated**：每个集群部署独立的 ArgoCD，通过 Git 仓库协调，适合自治场景。注意事项：远程集群的网络连通性（ArgoCD Controller 需要访问远程 API Server）；远程集群的 RBAC 权限（ServiceAccount 需要足够的权限）；多集群的 Secret 管理（Sealed Secrets 需要在每个集群部署）。生产环境推荐 Hub-Spoke 模式，集中管理更简单。

### Q15: 如何优化 ArgoCD 的性能？（难度：中等）

**答案：** ArgoCD 性能优化的关键点：1）**Application 数量**：单个 ArgoCD 实例管理 Application 上限约 1000 个，超过建议使用多实例或 ApplicationSet；2）**Git 仓库优化**：使用浅克隆（`spec.source.gitShallowClone: true`）减少 Clone 时间；使用 Git 子模块替代多个仓库；3）**Repo Server 扩展**：Repo Server 是性能瓶颈（处理 Helm/Kustomize 渲染），建议增加副本数（`repoServer.replicas: 3`）和资源；4）**Controller 调优**：`controller.status.processors: 20`（状态处理并发数）、`controller.selfHeal.timeout.seconds: 5`（自愈检测间隔）；5）**Redis**：ArggoCD 使用 Redis 缓存，确保 Redis 性能（使用 Redis HA 替代单节点）；6）**Manifest 缓存**：启用 Repo Server 的 manifest 缓存（默认启用），避免重复渲染；7）**网络优化**：ArgoCD 与 Git 仓库在同一网络内，减少 Clone 延迟；8）**资源过滤**：使用 `.argocdignore` 文件排除不需要的文件，减少处理量。

---

## 9. 故障排查案例

### 案例 1：Application 一直处于 OutOfSync 状态

**现象：**
```
argocd app get demo-app
# Project:  default
# Cluster:  https://kubernetes.default.svc
# Namespace: demo
# URL:      https://argocd.demo.local/applications/demo-app
# Repo:     http://192.168.1.61:3000/demo/demo-manifests.git
# Path:     k8s/demo-app
# Target:   main
# Sync:     OutOfSync
# Health:   Healthy
```

**排查步骤：**
```bash
# 1. 查看具体差异
argocd app diff demo-app

# 2. 检查 Git 仓库是否有新提交
git log --oneline -5
# 发现：Git 有新提交但 ArgoCD 未检测到

# 3. 检查 ArgoCD Controller 日志
kubectl logs -n argocd deploy/argocd-application-controller --tail=50 | grep -i "demo-app\|error"
# 发现：Failed to connect to git repository

# 4. 检查 Git 仓库连接
argocd repo list
# 发现：仓库状态显示 "Unable to connect"

# 5. 检查网络
kubectl exec -it deploy/argocd-repo-server -n argocd -- curl -I http://192.168.1.61:3000
# 发现：连接超时（网络策略限制）
```

**解决方案：**
```bash
# 方案一：修复网络策略
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1  # API 版本
kind: NetworkPolicy
metadata:
  name: allow-argocd-git
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-repo-server
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: TCP
      port: 443
EOF

# 方案二：手动触发 Refresh
argocd app refresh demo-app --hard
```

### 案例 2：Helm 渲染失败

**现象：**
```
argocd app sync demo-app-helm
# Error: failed to generate manifest for chart: helm template failed: exit status 1
# Error: YAML parse error on k8s/demo-app/templates/deployment.yaml: error converting YAML to JSON
```

**排查步骤：**
```bash
# 1. 查看 ArgoCD Repo Server 日志
kubectl logs -n argocd deploy/argocd-repo-server --tail=100 | grep -A 5 "error"

# 2. 本地验证 Helm Chart
helm template demo-app ./charts/demo-app -f values.yaml -f values-production.yaml
# 发现：values-production.yaml 中有语法错误（缩进不正确）

# 3. 检查 Helm values
cat charts/demo-app/values-production.yaml | head -20
# 发现：缩进使用了 Tab 而非空格
```

**解决方案：**
```bash
# 修复 values 文件的 YAML 语法
# 使用 yamllint 检查
yamllint values-production.yaml

# 修复后提交到 Git
git add values-production.yaml
git commit -m "fix: correct YAML indentation in values-production"
git push origin main

# ArgoCD 自动检测变更并重新 Sync
argocd app sync demo-app-helm --watch
```

### 案例 3：Auto-Sync 未触发

**现象：**
```
Git 仓库有新提交，但 ArgoCD Application 状态仍为 Synced，未自动触发 Sync。
```

**排查步骤：**
```bash
# 1. 检查 Sync Policy
argocd app get demo-app -o yaml | grep -A 10 "syncPolicy"
# 发现：syncPolicy 为空（未配置 automated）

# 2. 检查 Application CRD
kubectl get application demo-app -n argocd -o yaml | grep -A 5 "automated"
# 发现：未设置 automated

# 3. 检查 Controller 状态
kubectl logs -n argocd deploy/argocd-application-controller --tail=20
# 发现：Controller 正常运行
```

**解决方案：**
```bash
# 启用 Auto-Sync
kubectl patch application demo-app -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

# 验证
argocd app get demo-app
# 预期：Automated: Prune:On  SelfHeal:On
```

### 案例 4：ArgoCD Server 无法访问

**现象：**
```
访问 https://192.168.1.54:32443 返回连接超时。
```

**排查步骤：**
```bash
# 1. 检查 ArgoCD Server Pod
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
# 发现：argocd-server Running

# 2. 检查 Service
kubectl get svc -n argocd argocd-server
# 发现：NodePort 32443 已配置

# 3. 检查节点端口监听
ss -tlnp | grep 32443
# 发现：端口未监听

# 4. 检查 ArgoCD Server 日志
kubectl logs -n argocd deploy/argocd-server --tail=30
# 发现：TLS 证书配置错误
```

**解决方案：**
```bash
# 方案一：使用 HTTP 访问（临时）
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":32080}]}}'
# 访问 http://192.168.1.54:32080

# 方案二：重新生成 TLS 证书
kubectl delete secret argocd-server-tls -n argocd
kubectl rollout restart deployment argocd-server -n argocd

# 方案三：使用 Ingress 暴露
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1  # API 版本
kind: Ingress  # K8s 入口路由
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  ingressClassName: nginx  # 使用 Nginx Ingress
  rules:
  - host: argocd.demo.local
    http:
      paths:
      - path: /
        pathType: Prefix  # 前缀匹配
        backend:
          service:
            name: argocd-server
            port:  # 服务端口
              number: 443
  tls:
  - hosts:
    - argocd.demo.local
    secretName: argocd-server-tls
EOF

# DNS 解析说明：由于离线环境没有 DNS 服务器，需要在访问 ArgoCD 的客户端机器上
# 配置 /etc/hosts 文件，将 argocd.demo.local 解析到 Ingress 所在的 Node IP：
# echo "192.168.1.54 argocd.demo.local" >> /etc/hosts
# 配置完成后即可通过 https://argocd.demo.local 访问 ArgoCD UI
```

### 案例 5：Self-Heal 不断触发

**现象：**
```
ArgoCD 不断执行 Sync，但每次 Sync 后立即又检测到 OutOfSync，形成循环。
```

**排查步骤：**
```bash
# 1. 查看差异
argocd app diff demo-app
# 发现：Deployment 的 replicas 字段持续不一致

# 2. 检查是否有 HPA
kubectl get hpa -n demo
# 发现：存在 HPA 管理 demo-app 的副本数

# 3. 检查 ignoreDifferences
argocd app get demo-app -o yaml | grep -A 5 "ignoreDifferences"
# 发现：未配置 ignoreDifferences

# 4. 检查 ArgoCD Controller 日志
kubectl logs -n argocd deploy/argocd-application-controller --tail=50 | grep "self-heal"
# 发现：Self-Heal triggered by replica count change
```

**解决方案：**
```bash
# 配置 ignoreDifferences 忽略 HPA 管理的副本数
kubectl patch application demo-app -n argocd --type merge \
  -p '{"spec":{"ignoreDifferences":[{"group":"apps","kind":"Deployment","jsonPointers":["/spec/replicas"]},{"group":"autoscaling","kind":"HorizontalPodAutoscaler","jsonPointers":["/spec/minReplicas","/spec/maxReplicas"]}]}}'

# 验证
argocd app get demo-app
# 预期：状态变为 Synced
```

### 案例 6：Git 仓库凭证过期

**现象：**
```
argocd app sync demo-app
# Error: repository not accessible: authentication required
```

**排查步骤：**
```bash
# 1. 检查仓库状态
argocd repo list
# 发现：仓库状态显示 "Authentication failed"

# 2. 测试凭证
curl -I http://192.168.1.61:3000/demo/demo-manifests.git -u gitea-token-example:x-oauth-basic
# 发现：401 Unauthorized（Token 过期）

# 3. 检查 ArgoCD Secret
kubectl get secrets -n argocd | grep repo
# 发现：Secret 存在但凭证过期
```

**解决方案：**
```bash
# 更新仓库凭证
argocd repo add http://192.168.1.61:3000/demo/demo-manifests.git \
  --username admin \
  --password gitea-token-example \
  --upsert

# 或者更新 Secret
kubectl edit secret argocd-repo-xxx -n argocd
# 更新 .data 中的凭证

# 刷新 Application
argocd app refresh demo-app --hard
```

### 案例 7：ArgoCD Application Controller OOM

**现象：**
```bash
kubectl get pods -n argocd
# argocd-application-controller-xxx  0/1 OOMKilled
```

**排查步骤：**
```bash
# 1. 检查 Application 数量
argocd app list | wc -l
# 发现：管理了 500+ 个 Application

# 2. 检查 Controller 资源限制
kubectl get deploy argocd-application-controller -n argocd -o yaml | grep -A 5 "resources"
# 发现：memory limits=512Mi

# 3. 检查 Controller 日志
kubectl logs argocd-application-controller-xxx -n argocd --previous | grep -i "oom\|memory"
```

**解决方案：**
```bash
# 增大 Controller 内存限制
kubectl set resources deployment argocd-application-controller -n argocd \
  --limits=memory=2Gi --requests=memory=1Gi

# 优化：减少 Application 数量或使用 ApplicationSet
# 优化：调整 controller.status.processors 参数
```

### 案例 8：ArgoCD 回滚后应用异常

**现象：**
```
执行 ArgoCD 回滚后，应用 Pod 启动失败。
```

**排查步骤：**
```bash
# 1. 检查回滚后的镜像版本
kubectl get deployment demo-app -n demo -o yaml | grep image
# 发现：回滚到了旧版本镜像，但镜像已被清理

# 2. 检查 Harbor 中镜像是否存在
curl -s -u admin:Harbor12345 http://192.168.1.61:80/v2/demo/api-server/tags/list
# 发现：旧版本镜像 tag 不存在

# 3. 检查回滚的 revision
argocd app history demo-app
# 发现：回滚到了 3 个月前的 revision
```

**解决方案：**
```bash
# 方案一：重新构建旧版本镜像并推送到 Harbor
# 方案二：回滚到最近的稳定版本（而非太旧的版本）
argocd app rollback demo-app <recent-stable-revision>

# 方案三：在 Git 中修复（推荐）
# 1. 回滚 Git 提交
git revert HEAD~1 --no-edit
# 2. 修改 values.yaml 中的 image.tag 为可用的版本
# 3. 提交并推送
git push origin main
# ArgoCD 自动 Sync

# 预防措施：配置 Harbor 镜像保留策略，保留最近 N 个版本
```

### 案例 9：Sealed Secret解密失败

**现象：**
```
ArgoCD同步时SealedSecret资源创建成功，但对应的Secret未生成，应用无法启动。
```

**排查步骤：**
```bash
# 1. 检查SealedSecret状态
kubectl get sealedsecret db-credentials -n demo -o yaml
# 发现：status.conditions显示 "No key could decrypt the secret"

# 2. 检查Sealed Secrets Controller日志
kubectl logs -n kube-system deploy/sealed-secrets-controller --tail=50
# 发现："failed to decrypt: no key found for prefix"

# 3. 检查Controller的私钥
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key
# 发现：私钥Secret不存在或被删除

# 4. 验证SealedSecret的加密密钥
kubeseal --cert sealed-secrets-cert.pem --validate < db-sealedsecret.yaml
# 发现：证书不匹配
```

**解决方案：**
```bash
# 方案一：恢复私钥（如果有备份）
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl rollout restart deployment sealed-secrets-controller -n kube-system

# 方案二：重新加密Secret（如果私钥已丢失）
# 警告：这将导致所有已部署的SealedSecret需要重新加密

# 1. 删除旧的Controller
kubectl delete -f sealed-secrets-controller.yaml

# 2. 清理旧私钥
kubectl delete secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key

# 3. 重新部署Controller（会生成新密钥对）
kubectl apply -f sealed-secrets-controller.yaml

# 4. 获取新公钥
kubeseal --fetch-cert > sealed-secrets-cert-new.pem

# 5. 重新加密所有Secret
kubeseal --cert sealed-secrets-cert-new.pem --format yaml < db-secret.yaml > db-sealedsecret-new.yaml

# 6. 更新Git仓库
git add db-sealedsecret-new.yaml
git commit -m "Re-encrypt secrets with new key"
git push origin main

# 预防措施：定期备份私钥
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > \
  /backup/sealed-secrets-key-$(date +%Y%m%d).yaml
```

### 案例 10：Canary分析误判

**现象：**
```
Argo Rollouts金丝雀发布时，Analysis显示成功但新版本实际存在问题，导致故障扩散。
```

**排查步骤：**
```bash
# 1. 查看Analysis运行结果
kubectl get analysis -n demo
kubectl describe analysis demo-app-success-rate-xxx -n demo
# 发现：指标查询返回空值，被判定为成功

# 2. 检查Prometheus查询
kubectl get analysistemplate success-rate -n demo -o yaml
# 发现：查询条件过于严格，没有匹配到数据

# 3. 手动验证查询
curl -G "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query" \
  --data-urlencode 'query=sum(rate(http_requests_total{service="demo-app-canary",status=~"2.."}[1m]))'
# 发现：返回空结果（标签不匹配）

# 4. 检查指标标签
kubectl get pods -n demo -l app=demo-app --show-labels
# 发现：Pod标签为app=demo-app，但查询使用service=demo-app-canary

# 5. 查看Rollout事件
kubectl argo rollouts get rollout demo-app -n demo
kubectl describe rollout demo-app -n demo
```

**解决方案：**
```bash
# 方案一：修正AnalysisTemplate查询条件

# 正确的AnalysisTemplate
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AnalysisTemplate
metadata:
  name: success-rate-fixed
  namespace: demo
spec:
  metrics:
  - name: success-rate
    interval: 1m
    count: 3
    successCondition: result[0] >= 0.95
    failureCondition: result[0] < 0.95  # 添加失败条件
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: |
          sum(rate(http_requests_total{pod=~"demo-app-.*",status=~"2.."}[1m]))
          /
          sum(rate(http_requests_total{pod=~"demo-app-.*"}[1m]))
  - name: request-count  # 确保有流量才判断
    interval: 1m
    count: 1
    successCondition: result[0] > 10  # 至少10个请求
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        query: sum(rate(http_requests_total{pod=~"demo-app-.*"}[1m]))
EOF

# 方案二：添加初始延迟确保指标收集
# 在Rollout中添加初始暂停
kubectl patch rollout demo-app -n demo --type merge -p '
{
  "spec": {
    "strategy": {
      "canary": {
        "steps": [
          {"setWeight": 10},
          {"pause": {"duration": "2m"}},  # 等待指标收集
          {"analysis": {"templates": [{"templateName": "success-rate-fixed"}]}}
        ]
      }
    }
  }
}'

# 方案三：中止当前发布并回滚
kubectl argo rollouts abort demo-app -n demo
kubectl argo rollouts promote demo-app -n demo  # 重新尝试

# 验证修复
kubectl argo rollouts get rollout demo-app -n demo --watch
```

### 案例 11：多集群连接超时

**现象：**
```
ArgoCD管理多个集群时，部分集群显示"Connection refused"或"Timeout"，应用无法同步。
```

**排查步骤：**
```bash
# 1. 查看集群状态
argocd cluster list
# 发现：prod-cluster 状态为 "Failed"

# 2. 检查Cluster Secret
kubectl get secret prod-cluster-secret -n argocd -o yaml
# 发现：Secret存在

# 3. 测试网络连通性
kubectl exec -it deploy/argocd-application-controller -n argocd -- \
  curl -k https://192.168.1.51:6443/healthz
# 发现：连接超时

# 4. 检查目标集群API Server
ssh root@192.168.1.51 "systemctl status kubelet"
# 发现：kubelet正常运行

# 5. 检查防火墙规则
ssh root@192.168.1.51 "iptables -L -n | grep 6443"
# 发现：防火墙阻止了6443端口

# 6. 检查ArgoCD Controller日志
kubectl logs -n argocd deploy/argocd-application-controller --tail=100 | grep prod-cluster
# 发现："Failed to sync cluster: connection refused"
```

**解决方案：**
```bash
# 方案一：修复防火墙规则（在目标集群执行）
# 开放6443端口
iptables -I INPUT -p tcp --dport 6443 -j ACCEPT
# 或者使用firewalld
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --reload

# 方案二：检查NetworkPolicy
# 如果使用了NetworkPolicy，确保允许ArgoCD访问
kubectl get networkpolicies --all-namespaces | grep argocd

# 方案三：验证集群凭证
# 检查Token是否过期
kubectl get secret prod-cluster-secret -n argocd -o jsonpath='{.data.config}' | base64 -d

# 重新生成凭证（在目标集群执行）
# 1. 创建新的ServiceAccount
kubectl create sa argocd-manager-new -n kube-system

# 2. 绑定权限
kubectl create clusterrolebinding argocd-manager-new-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:argocd-manager-new

# 3. 获取新Token
TOKEN=$(kubectl -n kube-system create token argocd-manager-new --duration=8760h)

# 4. 更新ArgoCD Cluster Secret
kubectl patch secret prod-cluster-secret -n argocd --type merge \
  -p "{\"stringData\":{\"config\":\"{\\\"bearerToken\\\":\\\"${TOKEN}\\\",\\\"tlsClientConfig\\\":{\\\"insecure\\\":false,\\\"caData\\\":\\\"<base64-ca>\\\"}}\"}}"

# 方案四：刷新集群连接
argocd cluster rm prod-cluster
argocd cluster add prod-cluster-context --name prod-cluster --upsert

# 验证修复
argocd cluster list
argocd app sync prod-demo-app
```

**预防措施：**

```yaml
# 创建集群健康监控CronJob
apiVersion: batch/v1  # API 版本
kind: CronJob
metadata:
  name: cluster-health-check
  namespace: argocd
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: check
            image: 192.168.1.61:80/curlimages/curl:8.0  # 镜像地址(Harbor)
            command:
            - sh
            - -c
            - |
              for cluster in $(kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster -o name); do
                server=$(kubectl get -n argocd ${cluster} -o jsonpath='{.data.server}' | base64 -d)
                if ! curl -k --max-time 5 ${server}/healthz > /dev/null 2>&1; then
                  echo "ALERT: Cluster ${cluster} is unreachable"
                  # 发送告警（集成企业告警系统）
                fi
              done
          restartPolicy: OnFailure
```

---

## 10. GitOps PR晋升工作流（进阶）

### 10.1 环境晋升概述

**环境晋升（Environment Promotion）** 是 GitOps 工作流中的核心概念，指将应用配置从低级环境（dev）逐步推进到高级环境（staging → production）的过程。

**传统 CI/CD vs GitOps 晋升：**

```
+================================================================+
|              传统 CI/CD vs GitOps 晋升对比                        |
+================================================================+
|                                                                 |
|  传统 CI/CD:                                                    |
|  +--------+    +--------+    +--------+    +--------+          |
|  |  Dev   | -> | Stage  | -> |  Prod  | -> |  部署  |          |
|  +--------+    +--------+    +--------+    +--------+          |
|       ^             ^             ^                             |
|       |             |             |                             |
|    手动触发      手动触发      手动触发                           |
|                                                                 |
|  问题：                                                         |
|  - 环境配置漂移                                                  |
|  - 无法追溯部署历史                                              |
|  - 缺乏审批流程                                                  |
|                                                                 |
|  GitOps 晋升:                                                   |
|  +--------+    +--------+    +--------+    +--------+          |
|  | dev/   | -> |staging/| -> |prod/   | -> | ArgoCD |          |
|  | PR #1  |    | PR #2  |    | PR #3  |    | Sync   |          |
|  +--------+    +--------+    +--------+    +--------+          |
|       ^             ^             ^                             |
|       |             |             |                             |
|    PR Merge      PR Merge      PR Merge                         |
|    自动触发      自动触发      自动触发                           |
|                                                                 |
|  优势：                                                         |
|  - Git 作为唯一事实来源                                          |
|  - 完整审计追踪                                                  |
|  - PR 审批流程                                                   |
|                                                                 |
+================================================================+
```

### 10.2 多环境目录结构

**推荐的 Git 仓库结构：**

```bash
# Git 仓库目录结构
git-repo/
├── apps/
│   └── mall-order/
│       ├── base/                    # 基础配置（Kustomize）
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── configmap.yaml
│       │   └── kustomization.yaml
│       ├── overlays/
│       │   ├── dev/                 # 开发环境
│       │   │   ├── kustomization.yaml
│       │   │   └── patches/
│       │   │       └── deployment-patch.yaml
│       │   ├── staging/             # 预发环境
│       │   │   ├── kustomization.yaml
│       │   │   └── patches/
│       │   └── production/          # 生产环境
│       │       ├── kustomization.yaml
│       │       └── patches/
│       └── Chart.yaml               # 可选：Helm Chart
├── environments/
│   ├── dev/
│   │   └── apps.yaml                # ArgoCD ApplicationSet
│   ├── staging/
│   │   └── apps.yaml
│   └── production/
│       └── apps.yaml
└── .github/
    └── workflows/
        ├── pr-promote-staging.yaml  # PR 晋升到 staging
        └── pr-promote-production.yaml
```

**Kustomize 多环境配置示例：**

```yaml
# apps/mall-order/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1  # API 版本
kind: Kustomization

resources:
- deployment.yaml
- service.yaml
- configmap.yaml

commonLabels:
  app: mall-order
```

```yaml
# apps/mall-order/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1  # API 版本
kind: Kustomization

namespace: mall-dev

resources:
- ../../base

patchesStrategicMerge:
- patches/deployment-patch.yaml

# 开发环境特定配置
configMapGenerator:
- name: order-config
  behavior: merge
  literals:
    - LOG_LEVEL=DEBUG
    - DB_HOST=mysql-dev.mall-dev.svc
```

```yaml
# apps/mall-order/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1  # API 版本
kind: Kustomization

namespace: mall-prod

resources:
- ../../base

patchesStrategicMerge:
- patches/deployment-patch.yaml

# 生产环境特定配置
configMapGenerator:
- name: order-config
  behavior: merge
  literals:
    - LOG_LEVEL=INFO
    - DB_HOST=mysql-prod.mall-prod.svc

# 生产环境副本数
images:
- name: mall-order
  newTag: v1.2.3  # 由 CI 自动更新
```

### 10.3 ApplicationSet PR Generator

**ApplicationSet** 是 ArgoCD 的高级功能，支持动态生成多个 Application。使用 **Pull Request Generator** 可以基于 Git PR 自动创建应用。

**ApplicationSet 配置：**

```yaml
# environments/dev/apps.yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: mall-apps-dev
  namespace: argocd
spec:
  generators:
  # PR Generator：监控 PR 创建
  - pullRequest:
      # Git 仓库配置
      github:
        owner: myorg
        repo: mall-microservices
        labels:
        - promote-to-dev  # 只处理带此标签的 PR
      # PR 过滤条件
      filters:
      - branch: main  # 只处理 main 分支的 PR
      
  template:
    metadata:
      name: 'mall-{{.branch}}-{{.number}}'
      labels:
        environment: dev
        pr-number: '{{.number}}'
    spec:
      project: default  # 所属项目
      source:
        repoURL: https://github.com/myorg/mall-microservices.git
        targetRevision: '{{.head_sha}}'  # PR 的 HEAD commit
        path: apps/{{.app_name}}/overlays/dev
      destination:
        server: https://kubernetes.default.svc  # 目标 K8s 集群
        namespace: mall-dev
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: true  # 启用自动修复
        syncOptions:
        - CreateNamespace=true  # 自动创建命名空间
```

**Git PR 晋升工作流：**

```
+================================================================+
|                   PR 晋升工作流                                  |
+================================================================+
|                                                                 |
|  步骤 1: 开发提交代码                                            |
|  +----------------------------------------------------------+  |
|  |  git checkout -b feature/order-v2                        |  |
|  |  git commit -m "Add order v2 feature"                    |  |
|  |  git push origin feature/order-v2                        |  |
|  +----------------------------------------------------------+  |
|                          |                                      |
|                          v                                      |
|  步骤 2: 创建 PR (dev)                                          |
|  +----------------------------------------------------------+  |
|  |  GitHub PR #123: feature/order-v2 -> main                |  |
|  |  Labels: promote-to-dev                                  |  |
|  |  -> ApplicationSet 自动创建预览环境                        |  |
|  +----------------------------------------------------------+  |
|                          |                                      |
|                          v                                      |
|  步骤 3: PR Review & Merge                                      |
|  +----------------------------------------------------------+  |
|  |  Reviewer 批准 PR                                         |  |
|  |  Merge PR #123 -> main                                   |  |
|  |  -> 自动触发 staging 晋升                                  |  |
|  +----------------------------------------------------------+  |
|                          |                                      |
|                          v                                      |
|  步骤 4: 创建 PR (staging)                                      |
|  +----------------------------------------------------------+  |
|  |  GitHub PR #124: main -> staging                         |  |
|  |  -> 自动部署到 staging 环境                                |  |
|  |  -> 运行集成测试                                           |  |
|  +----------------------------------------------------------+  |
|                          |                                      |
|                          v                                      |
|  步骤 5: 创建 PR (production)                                   |
|  +----------------------------------------------------------+  |
|  |  GitHub PR #125: staging -> production                   |  |
|  |  -> 需要审批（手动 gate）                                  |  |
|  |  -> 部署到 production                                      |  |
|  +----------------------------------------------------------+  |
|                                                                 |
+================================================================+
```

### 10.4 Pre/Post Promotion 分析

**AnalysisTemplate** 用于在晋升前后执行验证分析，确保应用健康。

**Pre-Promotion 分析（部署前检查）：**

```yaml
# analysis/pre-promotion.yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AnalysisTemplate
metadata:
  name: pre-promotion-analysis
  namespace: argocd
spec:
  args:
  - name: service-name
  - name: namespace
  metrics:
  # 检查服务健康
  - name: service-health
    interval: 30s
    count: 3
    successCondition: result.all(result.health == 'Healthy')
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc:9090
        query: |
          sum(kube_service_status{{service="{{args.service-name}}",namespace="{{args.namespace}}"}}) by (health)
  
  # 检查错误率
  - name: error-rate-check
    interval: 1m
    count: 5
    successCondition: result < 0.01  # 错误率 < 1%
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc:9090
        query: |
          sum(rate(http_requests_total{service="{{args.service-name}}",status=~"5.."}[5m]))
          /
          sum(rate(http_requests_total{service="{{args.service-name}}"}[5m]))
```

**Post-Promotion 分析（部署后验证）：**

```yaml
# analysis/post-promotion.yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: AnalysisTemplate
metadata:
  name: post-promotion-analysis
  namespace: argocd
spec:
  args:
  - name: service-name
  - name: namespace
  metrics:
  # P99 延迟检查
  - name: latency-p99
    interval: 30s
    count: 10
    successCondition: result < 500  # P99 < 500ms
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc:9090
        query: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket{service="{{args.service-name}}"}[5m])) by (le)
          ) * 1000
  
  # 成功率检查
  - name: success-rate
    interval: 30s
    count: 10
    successCondition: result > 0.99  # 成功率 > 99%
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc:9090
        query: |
          sum(rate(http_requests_total{service="{{args.service-name}}",status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total{service="{{args.service-name}}"}[5m]))
```

**集成到 Application：**

```yaml
# 使用 Argo Rollouts 进行渐进式交付
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Rollout
metadata:
  name: mall-order
  namespace: mall-prod
spec:
  replicas: 3  # 副本数: 3
  selector:
    matchLabels:
      app: mall-order
  template:
    spec:
      containers:
      - name: order
        image: 192.168.1.61:80/mall/order:v1.2.3  # 镜像地址(Harbor)
  strategy:
    canary:
      # Canary 步骤
      steps:
      # 1. 部署 10% 流量
      - setWeight: 10
      # 2. 运行 Pre-Analysis
      - analysis:
          templates:
          - templateName: pre-promotion-analysis
          args:
          - name: service-name
            value: mall-order
          - name: namespace
            value: mall-prod
      # 3. 暂停等待手动确认
      - pause:
          duration: 5m
      # 4. 增加到 50%
      - setWeight: 50
      # 5. 运行 Post-Analysis
      - analysis:
          templates:
          - templateName: post-promotion-analysis
          args:
          - name: service-name
            value: mall-order
      # 6. 全量发布
      - setWeight: 100
```

### 10.5 手动审批门控

**使用 ArgoCD 通知 + GitHub PR Review 实现手动审批：**

```yaml
# .github/workflows/pr-promote-production.yaml
name: Promote to Production

on:
  pull_request:
    types: [opened, synchronize]
    branches: [production]

jobs:
  # 1. 检查是否来自 staging
  validate-source:
    runs-on: ubuntu-latest
    steps:
    - name: Check source branch
      run: |
        if [[ "${{ github.head_ref }}" != "staging" ]]; then
          echo "Production PR must come from staging branch"
          exit 1
        fi
  
  # 2. 等待审批
  wait-for-approval:
    runs-on: ubuntu-latest
    needs: validate-source
    environment: production  # GitHub Environment 审批
    steps:
    - name: Approval gate
      run: echo "Production deployment approved"
  
  # 3. 部署到生产
  deploy:
    runs-on: ubuntu-latest
    needs: wait-for-approval
    steps:
    - name: Trigger ArgoCD Sync
      run: |
        curl -X POST \
          -H "Authorization: Bearer ${{ secrets.ARGOCD_TOKEN }}" \
          https://argocd.demo.local/api/v1/applications/mall-order-prod/sync
```

**ArgoCD 通知配置（Slack/钉钉）：**

```yaml
# argocd-notifications-cm.yaml
apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # 触发器定义
  trigger.on-sync-status-unknown: |
    - send: [slack]
      when: app.status.sync.status == 'Unknown'
  
  trigger.on-health-degraded: |
    - send: [slack]
      when: app.status.health.status == 'Degraded'
  
  trigger.on-sync-failed: |
    - send: [slack]
      when: app.status.sync.status == 'Failed'
  
  # 模板定义
  template.slack: |
    slack:
      attachments:
        - title: Application {{.app.metadata.name}} sync status
          color: '{{if eq .app.status.sync.status "Succeeded"}}good{{else}}danger{{end}}'
          fields:
            - title: Sync Status
              value: '{{.app.status.sync.status}}'
            - title: Revision
              value: '{{.app.status.sync.revision}}'
            - title: Health
              value: '{{.app.status.health.status}}'
  
  # 服务定义
  service.slack: |
    slack:
      token: $slack-token
      channels:
        - name: argocd-alerts
```

**钉钉通知配置：**

```yaml
# argocd-notifications-cm.yaml (钉钉)
data:
  template.dingtalk: |
    dingtalk:
      msgType: markdown
      title: ArgoCD 通知
      content: |
        ## 应用同步状态
        - **应用名称**: {{.app.metadata.name}}
        - **同步状态**: {{.app.status.sync.status}}
        - **健康状态**: {{.app.status.health.status}}
        - **修订版本**: {{.app.status.sync.revision}}
        - **更新时间**: {{.app.status.operationState.finishedAt}}
  
  service.dingtalk: |
    dingtalk:
      accessToken: $dingtalk-token
      secret: $dingtalk-secret
```

### 10.6 回滚策略

**场景一：自动回滚（基于 Analysis 失败）：**

```yaml
# Rollout 配置自动回滚
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: Rollout
metadata:
  name: mall-order
spec:
  strategy:
    canary:
      analysis:
        templates:
        - templateName: post-promotion-analysis
        startingStep: 2  # 从第 2 步开始分析
        args:
        - name: service-name
          value: mall-order
      # 分析失败自动回滚
      rollback:
        steps:
        - setWeight: 0  # 流量切回旧版本
```

**场景二：手动回滚（ArgoCD）：**

```bash
# 方法 1: 回滚到指定版本
argocd app rollback mall-order-prod <revision>

# 方法 2: 同步到历史 commit
argocd app sync mall-order-prod --revision <commit-sha>

# 方法 3: 通过 Git revert
git revert <commit-sha>
git push origin production
# ArgoCD 自动同步回滚后的配置
```

**场景三：紧急回滚（GitOps）：**

```yaml
# .github/workflows/emergency-rollback.yaml
name: Emergency Rollback

on:
  workflow_dispatch:
    inputs:
      app-name:
        description: 'Application name'
        required: true
      target-revision:
        description: 'Target revision to rollback to'
        required: true

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: Rollback ArgoCD Application
      run: |
        argocd app rollback ${{ inputs.app-name }} \
          --revision ${{ inputs.target-revision }}
    
    - name: Notify Slack
      uses: slackapi/slack-webhook@v1
      with:
        payload: |
          {
            "text": "紧急回滚执行: ${{ inputs.app-name }} -> ${{ inputs.target-revision }}"
          }
```

### 10.7 完整晋升工作流示例

**端到端工作流配置：**

```yaml
# environments/production/apps.yaml
apiVersion: argoproj.io/v1alpha1  # ArgoCD API 版本
kind: ApplicationSet  # ArgoCD 应用集
metadata:
  name: mall-apps-prod
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/myorg/mall-microservices.git
      revision: production
      directories:
      - path: apps/*/overlays/production
  
  template:
    metadata:
      name: '{{path.basename}}-prod'
      annotations:
        # 通知配置
        notifications.argoproj.io/subscribe.on-sync-failed.slack: argocd-alerts
        notifications.argoproj.io/subscribe.on-health-degraded.slack: argocd-alerts
    spec:
      project: production
      source:
        repoURL: https://github.com/myorg/mall-microservices.git
        targetRevision: production
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc  # 目标 K8s 集群
        namespace: mall-prod
      syncPolicy:  # 同步策略
        automated:  # 启用自动同步
          prune: true  # 自动清理多余资源
          selfHeal: true  # 启用自动修复
        syncOptions:
        - CreateNamespace=true  # 自动创建命名空间
        # Pre-Sync Hook：部署前检查
        - ApplyOutOfSyncOnly=true
      # 忽略某些字段的变更
      ignoreDifferences:
      - group: apps
        kind: Deployment  # K8s 部署
        jsonPointers:
        - /spec/replicas  # HPA 管理副本数
```

**工作流状态图：**

```
+================================================================+
|                   完整晋升工作流状态图                           |
+================================================================+
|                                                                 |
|  Dev 环境                                                       |
|  +----------------------------------------------------------+  |
|  |  PR #123 (feature -> main)                               |  |
|  |  [x] 代码审查                                             |  |
|  |  [x] 单元测试                                             |  |
|  |  [x] 合并到 main                                          |  |
|  +----------------------------------------------------------+  |
|                          |                                      |
|                          v                                      |
|  Staging 环境                                                   |
|  +----------------------------------------------------------+  |
|  |  PR #124 (main -> staging)                               |  |
|  |  [x] 自动部署                                             |  |
|  |  [x] 集成测试                                             |  |
|  |  [x] Pre-Analysis (健康检查)                              |  |
|  |  [x] Post-Analysis (性能验证)                             |  |
|  |  [ ] 手动审批 (可选)                                       |  |
|  +----------------------------------------------------------+  |
|                          |                                      |
|                          v                                      |
|  Production 环境                                                |
|  +----------------------------------------------------------+  |
|  |  PR #125 (staging -> production)                         |  |
|  |  [x] 手动审批 (必须)                                       |  |
|  |  [x] Canary 发布 (10% -> 50% -> 100%)                     |  |
|  |  [x] Pre-Analysis                                         |  |
|  |  [x] Post-Analysis                                        |  |
|  |  [x] 监控告警配置                                          |  |
|  |  [ ] 回滚准备 (如失败)                                     |  |
|  +----------------------------------------------------------+  |
|                                                                 |
+================================================================+
```

### 10.8 CKA/CKS 考点关联

| 考点 | 关联内容 |
|------|----------|
| **GitOps 原理** | 理解 Git 作为唯一事实来源 |
| **多环境管理** | Kustomize overlays、Helm values |
| **渐进式交付** | Canary/Blue-Green 策略 |
| **审批流程** | GitHub Environment、ArgoCD Sync Windows |
| **回滚机制** | Git revert、ArgoCD rollback |

**高频面试题：**

1. **Q: GitOps 晋升工作流的优势是什么？**
   - A: GitOps 晋升通过 PR 流程实现环境晋升，具有完整审计追踪、自动验证、手动审批等优势。相比传统 CI/CD，配置漂移风险更低，回滚更简单（git revert）。

2. **Q: ApplicationSet PR Generator 如何工作？**
   - A: PR Generator 监控 Git 仓库的 PR 状态，当 PR 满足条件（如特定标签）时，自动生成 ArgoCD Application。适用于预览环境、临时测试环境等场景。

3. **Q: 如何实现生产环境的手动审批？**
   - A: 可通过 GitHub Environment 的 required reviewers 配置，或使用 ArgoCD Sync Windows 限制同步时间，或在 Rollout 中设置 pause 步骤等待手动确认。

---

## 11. 生产环境建议

### 11.1 生产级 ArgoCD 配置

```yaml
# 生产级 ArgoCD Helm Values（离线环境适配版）
# 注意：当前集群 Master 2C4G / Worker 4C8G，建议先使用以下精简配置
server:
  replicas: 1  # 副本数: 1
  resources:
    requests:
      cpu: 100m  # CPU 100m
      memory: 128Mi  # 内存 128Mi
    limits:
      cpu: 500m  # CPU 500m
      memory: 512Mi  # 内存 512Mi
  service:
    type: NodePort  # 离线环境使用 NodePort 暴露
  ingress:
    enabled: true
    hosts:
    - argocd.demo.local
    tls:
    - secretName: argocd-tls
      hosts:
      - argocd.demo.local

controller:
  replicas: 1  # 副本数: 1
  resources:
    requests:
      cpu: 250m  # CPU 250m
      memory: 512Mi  # 内存 512Mi
    limits:
      cpu: 1000m  # CPU 1000m
      memory: 2Gi  # 内存 2Gi
  statusProcessors: 10
  operationProcessors: 5
  selfHealTimeoutSeconds: 5

repoServer:
  replicas: 1  # 副本数: 1
  resources:
    requests:
      cpu: 100m  # CPU 100m
      memory: 256Mi  # 内存 256Mi
    limits:
      cpu: 500m  # CPU 500m
      memory: 1Gi  # 内存 1Gi

redis:
  resources:
    requests:
      cpu: 50m  # CPU 50m
      memory: 64Mi  # 内存 64Mi
    limits:
      cpu: 200m  # CPU 200m
      memory: 256Mi  # 内存 256Mi
```

### 10.2 生产最佳实践

| 领域 | 建议 |
|------|------|
| **高可用** | Server 1 副本（离线环境资源有限）、Repo Server 1 副本、Redis 单节点 |
| **安全** | 启用 SSO、严格 RBAC、Secret 使用 Sealed Secrets |
| **多环境** | Helm Values + ApplicationSet List Generator |
| **回滚** | 使用 Git Revert 回滚，保留完整历史 |
| **监控** | Prometheus（指标监控系统） 采集 ArgoCD metrics + Grafana Dashboard |
| **告警** | OutOfSync > 5min、Degraded、Git 连接失败 |
| **网络** | ArgoCD 命名空间 NetworkPolicy 限制 Egress |
| **性能** | Repo Server 1 副本（资源有限）、启用 shallow clone |
| **组织** | App of Apps 或 ApplicationSet 管理应用层级 |
| **备份** | 定期备份 ArgoCD 管理的 Git 仓库和 K8s Secret |
| **升级** | ArgoCD 滚动升级，先在预发环境验证 |
| **Sync Window** | 配置工作日 Sync 窗口，防止非工作时间误操作 |

### 10.3 ArgoCD灾难恢复

#### 10.3.1 定期备份ArgoCD etcd数据

ArgoCD自身不直接依赖etcd，但其配置数据（Application、AppProject、Repository等）存储在Kubernetes集群中。需要定期备份这些资源。

**备份架构图：**

```
+================================================================+
|                   ArgoCD 备份架构                               |
+================================================================+
|                                                                 |
|  +------------------+                                          |
|  | ArgoCD Namespace |                                          |
|  |                  |                                          |
|  | +--------------+ |                                          |
|  | | Application  | |                                          |
|  | | AppProject   | |  ------>  备份脚本  ------>  对象存储    |
|  | | Secret       | |                                          |
|  | | ConfigMap    | |          (定时任务)        (MinIO/S3)   |
|  | +--------------+ |                                          |
|  +------------------+                                          |
|                                                                 |
+================================================================+
```

**备份脚本：**

```bash
#!/bin/bash
# argocd-backup.sh - ArgoCD配置备份脚本

BACKUP_DIR="/backup/argocd/$(date +%Y%m%d-%H%M%S)"
RETENTION_DAYS=30
S3_ENDPOINT="http://minio.example.com:9000"
S3_BUCKET="argocd-backups"

mkdir -p ${BACKUP_DIR}

echo "=== 开始备份 ArgoCD 配置 ==="

# 1. 备份所有Application
echo "备份 Applications..."
kubectl get applications -n argocd -o yaml > ${BACKUP_DIR}/applications.yaml

# 2. 备份所有AppProject
echo "备份 AppProjects..."
kubectl get appprojects -n argocd -o yaml > ${BACKUP_DIR}/appprojects.yaml

# 3. 备份Repository配置
echo "备份 Repository Secrets..."
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository -o yaml > ${BACKUP_DIR}/repositories.yaml

# 4. 备份Cluster配置
echo "备份 Cluster Secrets..."
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml > ${BACKUP_DIR}/clusters.yaml

# 5. 备份ArgoCD ConfigMap
echo "备份 ConfigMaps..."
kubectl get configmap argocd-cm -n argocd -o yaml > ${BACKUP_DIR}/argocd-cm.yaml
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > ${BACKUP_DIR}/argocd-rbac-cm.yaml
kubectl get configmap argocd-ssh-known-hosts-cm -n argocd -o yaml > ${BACKUP_DIR}/argocd-ssh-known-hosts-cm.yaml

# 6. 备份TLS证书
echo "备份 TLS Secrets..."
kubectl get secret argocd-server-tls -n argocd -o yaml > ${BACKUP_DIR}/tls-secret.yaml 2>/dev/null || echo "TLS secret not found"

# 7. 打包备份
tar -czf ${BACKUP_DIR}.tar.gz -C $(dirname ${BACKUP_DIR}) $(basename ${BACKUP_DIR})

# 8. 上传到对象存储（如果有）
if command -v mc &> /dev/null; then
  echo "上传到 MinIO..."
  mc cp ${BACKUP_DIR}.tar.gz minio/${S3_BUCKET}/
fi

# 9. 清理旧备份
echo "清理 ${RETENTION_DAYS} 天前的备份..."
find /backup/argocd -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete

echo "=== 备份完成: ${BACKUP_DIR}.tar.gz ==="
```

**创建定时备份CronJob：**

```yaml
apiVersion: batch/v1  # API 版本
kind: CronJob
metadata:
  name: argocd-backup
  namespace: argocd
spec:
  schedule: "0 2 * * *"  # 每天凌晨2点执行
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: argocd-backup
          containers:
          - name: backup
            image: 192.168.1.61:80/bitnami/kubectl:latest  # 镜像地址(Harbor)
            command:
            - /bin/bash
            - -c
            - |
              BACKUP_DIR="/backup/$(date +%Y%m%d-%H%M%S)"
              mkdir -p ${BACKUP_DIR}
              
              # 备份所有ArgoCD资源
              kubectl get applications,appprojects -n argocd -o yaml > ${BACKUP_DIR}/argocd-resources.yaml
              kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type -o yaml > ${BACKUP_DIR}/argocd-secrets.yaml
              kubectl get configmaps -n argocd -o yaml > ${BACKUP_DIR}/argocd-configmaps.yaml
              
              # 打包
              tar -czf ${BACKUP_DIR}.tar.gz -C /backup $(basename ${BACKUP_DIR})
              
              # 保留最近30天
              find /backup -name "*.tar.gz" -mtime +30 -delete
              
              echo "Backup completed: ${BACKUP_DIR}.tar.gz"
            volumeMounts:
            - name: backup-volume
              mountPath: /backup
          volumes:
          - name: backup-volume
            persistentVolumeClaim:
              claimName: argocd-backup-pvc
          restartPolicy: OnFailure
---
apiVersion: v1  # API 版本
kind: ServiceAccount  # 服务账户
metadata:
  name: argocd-backup
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1  # RBAC API 版本
kind: ClusterRole
metadata:
  name: argocd-backup
rules:
- apiGroups: ["argoproj.io"]
  resources: ["applications", "appprojects"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1  # RBAC API 版本
kind: ClusterRoleBinding
metadata:
  name: argocd-backup
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-backup
subjects:
- kind: ServiceAccount
  name: argocd-backup
  namespace: argocd
```

#### 10.3.2 Repository和Project配置导出

**导出所有Repository配置：**

```bash
#!/bin/bash
# export-argocd-config.sh

EXPORT_DIR="argocd-export-$(date +%Y%m%d)"
mkdir -p ${EXPORT_DIR}

echo "=== 导出 ArgoCD 配置 ==="

# 导出Repositories
argocd repo list -o yaml > ${EXPORT_DIR}/repositories.yaml 2>/dev/null || \
  kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository -o yaml > ${EXPORT_DIR}/repositories.yaml

# 导出Projects
argocd proj list -o yaml > ${EXPORT_DIR}/projects.yaml 2>/dev/null || \
  kubectl get appprojects -n argocd -o yaml > ${EXPORT_DIR}/projects.yaml

# 导出Applications（按Project分组）
for proj in $(argocd proj list -o name 2>/dev/null | tail -n +2); do
  mkdir -p ${EXPORT_DIR}/applications/${proj}
  argocd app list -p ${proj} -o yaml > ${EXPORT_DIR}/applications/${proj}/apps.yaml 2>/dev/null
done

# 导出Clusters
argocd cluster list -o yaml > ${EXPORT_DIR}/clusters.yaml 2>/dev/null || \
  kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml > ${EXPORT_DIR}/clusters.yaml

# 导出Settings
argocd admin settings export -n argocd > ${EXPORT_DIR}/settings.yaml 2>/dev/null || echo "Admin export requires argocd CLI admin permissions"

tar -czf ${EXPORT_DIR}.tar.gz ${EXPORT_DIR}
echo "=== 导出完成: ${EXPORT_DIR}.tar.gz ==="
```

**导出特定Application的完整配置：**

```bash
#!/bin/bash
# export-app.sh <app-name>

APP_NAME=$1
EXPORT_FILE="${APP_NAME}-export-$(date +%Y%m%d).yaml"

echo "导出 Application: ${APP_NAME}"

# 导出Application定义
kubectl get application ${APP_NAME} -n argocd -o yaml | \
  yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.generation, .metadata.creationTimestamp, .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration", .status)' - > ${EXPORT_FILE}

# 导出关联的Secret（如果有）
APP_PROJECT=$(yq eval '.spec.project' ${EXPORT_FILE})
echo "所属 Project: ${APP_PROJECT}"

kubectl get appproject ${APP_PROJECT} -n argocd -o yaml | \
  yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.generation, .metadata.creationTimestamp, .status)' - > ${APP_NAME}-project.yaml

echo "导出完成: ${EXPORT_FILE}"
```

#### 10.3.3 快速恢复流程

**完整恢复流程：**

```bash
#!/bin/bash
# argocd-restore.sh <backup-file>

BACKUP_FILE=$1
RESTORE_DIR="/tmp/argocd-restore-$(date +%s)"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup-file.tar.gz>"
  exit 1
fi

echo "=== 开始恢复 ArgoCD 配置 ==="

# 1. 解压备份
mkdir -p ${RESTORE_DIR}
tar -xzf ${BACKUP_FILE} -C ${RESTORE_DIR}
BACKUP_DIR=$(find ${RESTORE_DIR} -type d -name "20*" | head -1)

# 2. 检查ArgoCD是否运行
echo "检查 ArgoCD 状态..."
kubectl get pods -n argocd | grep argocd-server || {
  echo "ArgoCD 未运行，请先安装 ArgoCD"
  exit 1
}

# 3. 恢复ConfigMaps
echo "恢复 ConfigMaps..."
for cm in argocd-cm argocd-rbac-cm argocd-ssh-known-hosts-cm; do
  if [ -f "${BACKUP_DIR}/${cm}.yaml" ]; then
    kubectl apply -f "${BACKUP_DIR}/${cm}.yaml"
  fi
done

# 4. 恢复Secrets（Repository和Cluster）
echo "恢复 Secrets..."
if [ -f "${BACKUP_DIR}/repositories.yaml" ]; then
  kubectl apply -f "${BACKUP_DIR}/repositories.yaml"
fi
if [ -f "${BACKUP_DIR}/clusters.yaml" ]; then
  kubectl apply -f "${BACKUP_DIR}/clusters.yaml"
fi

# 5. 恢复AppProjects
echo "恢复 AppProjects..."
if [ -f "${BACKUP_DIR}/appprojects.yaml" ]; then
  kubectl apply -f "${BACKUP_DIR}/appprojects.yaml"
fi

# 6. 恢复Applications
echo "恢复 Applications..."
if [ -f "${BACKUP_DIR}/applications.yaml" ]; then
  # 先创建Application（不触发同步）
  kubectl apply -f "${BACKUP_DIR}/applications.yaml" --validate=false
fi

# 7. 验证恢复
echo "=== 验证恢复结果 ==="
echo "Projects:"
kubectl get appprojects -n argocd
echo ""
echo "Repositories:"
argocd repo list 2>/dev/null || kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository
echo ""
echo "Applications:"
argocd app list 2>/dev/null || kubectl get applications -n argocd
echo ""
echo "=== 恢复完成 ==="
echo "注意：Applications 已恢复但尚未同步，请手动执行 'argocd app sync -l <label>' 进行同步"
```

**选择性恢复特定Application：**

```bash
#!/bin/bash
# restore-app.sh <app-export-file>

APP_FILE=$1

if [ -z "$APP_FILE" ]; then
  echo "Usage: $0 <app-export-file.yaml>"
  exit 1
fi

APP_NAME=$(yq eval '.metadata.name' ${APP_FILE})
APP_PROJECT=$(yq eval '.spec.project' ${APP_FILE})

echo "恢复 Application: ${APP_NAME}"
echo "所属 Project: ${APP_PROJECT}"

# 检查Project是否存在
kubectl get appproject ${APP_PROJECT} -n argocd > /dev/null 2>&1 || {
  echo "Error: Project ${APP_PROJECT} 不存在，请先恢复Project"
  exit 1
}

# 创建Application（暂停自动同步）
cat ${APP_FILE} | yq eval '.spec.syncPolicy.automated.prune = false | .spec.syncPolicy.automated.selfHeal = false' - | \
  kubectl apply -f -

echo "Application ${APP_NAME} 已恢复（自动同步已禁用）"
echo "请检查配置后手动执行: argocd app sync ${APP_NAME}"
```

**灾难恢复检查清单：**

| 步骤 | 检查项 | 命令 |
|------|--------|------|
| 1 | 确认备份文件完整 | `tar -tzf backup.tar.gz` |
| 2 | 确认ArgoCD已安装 | `kubectl get pods -n argocd` |
| 3 | 恢复基础配置 | `kubectl apply -f argocd-cm.yaml` |
| 4 | 恢复仓库凭证 | `kubectl apply -f repositories.yaml` |
| 5 | 恢复集群配置 | `kubectl apply -f clusters.yaml` |
| 6 | 恢复Projects | `kubectl apply -f appprojects.yaml` |
| 7 | 恢复Applications | `kubectl apply -f applications.yaml` |
| 8 | 验证仓库连接 | `argocd repo list` |
| 9 | 验证集群连接 | `argocd cluster list` |
| 10 | 手动触发同步 | `argocd app sync <app-name>` |

**Redis数据备份（可选）：**

ArgoCD使用Redis缓存会话和查询结果，这些数据可以重建，但备份可以加速恢复。

```bash
# 备份Redis数据
kubectl exec -it argocd-redis-0 -n argocd -- redis-cli BGSAVE
kubectl cp argocd-redis-0:/data/dump.rdb ./redis-backup.rdb -n argocd

# 恢复Redis数据（新集群）
kubectl cp ./redis-backup.rdb argocd-redis-0:/data/dump.rdb -n argocd
kubectl exec -it argocd-redis-0 -n argocd -- redis-cli SHUTDOWN SAVE
```
