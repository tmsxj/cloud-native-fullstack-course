# 模块05：网络插件 Calico

---

## 1. 概述与架构图

### 1.1 课程目标

本模块深入讲解 Kubernetes 网络插件（CNI，容器网络接口）的原理和 Calico 的部署与运维。Calico 是目前最流行的 K8s 网络插件之一，支持 BGP（边界网关协议）、IPIP（IP 封装协议）、VXLAN（虚拟扩展局域网）等多种网络模式，以及强大的 NetworkPolicy（网络策略）功能。完成本模块后，你将掌握 Calico 的完整部署流程、网络模式选择、NetworkPolicy 实战以及故障排查能力。

### 1.2 CNI 架构图

```
  +------------------------------------------------------------------+
  |                     Kubernetes Node                               |
  +------------------------------------------------------------------+
       |                    |                    |
  +----+----+         +-----+-----+         +----+----+
  | kubelet |         | kubelet  |         | kubelet |
  +----+----+         +-----+-----+         +----+----+
       |                    |                    |
       +--------------------+--------------------+
                            |
                    +-------+-------+
                    |  CRI Plugin   |
                    +-------+-------+
                            |
                    +-------+-------+
                    |  CNI Plugin   |
                    | (Calico/CNI) |
                    +-------+-------+
                            |
              +-------------+-------------+
              |                           |
     +--------+--------+        +--------+--------+
     |  Calico Node    |        |  Calico Node    |
     |  (BGP Agent)    |        |  (BGP Agent)    |
     |  (Felix Agent)  |        |  (Felix Agent)  |
     +--------+--------+        +--------+--------+
              |                           |
     +--------+--------+        +--------+--------+
     |  veth pair      |        |  veth pair      |
     |  (Pod<->Host)   |        |  (Pod<->Host)   |
     +--------+--------+        +--------+--------+
              |                           |
     +--------+--------+        +--------+--------+
     |  IPIP / VXLAN   |        |  IPIP / VXLAN   |
     |  Tunnel / BGP    |        |  Tunnel / BGP    |
     +-----------------+        +-----------------+
```

### 1.3 Calico 组件架构

```
  +------------------------------------------------------------------+
  |                      Calico 架构                                  |
  +------------------------------------------------------------------+
  |                                                                   |
  |  Data Plane (数据面)                                               |
  |  +---------------------------+  +---------------------------+     |
  |  |      Calico Node          |  |      Calico Node          |     |
  |  |  +-----------+  +------+ |  |  +-----------+  +------+ |     |
  |  |  |   Felix   |  | BIRD  | |  |  |   Felix   |  | BIRD  | |     |
  |  |  |(路由/ACL) |  |(BGP)  | |  |  |(路由/ACL) |  |(BGP)  | |     |
  |  |  +-----------+  +------+ |  |  +-----------+  +------+ |     |
  |  +---------------------------+  +---------------------------+     |
  |                                                                   |
  |  Control Plane (控制面)                                            |
  |  +---------------------------+  +---------------------------+     |
  |  |     calico-node (DaemonSet)|  |  Typha (可选, API 代理)    |     |
  |  |     calico-kube-controllers|  |                           |     |
  |  |     (NetworkPolicy 控制器)  |  |                           |     |
  |  +---------------------------+  +---------------------------+     |
  |                                                                   |
  |  Data Store                                                       |
  |  +-----------------------------------------------------------+   |
  |  |  etcd (默认使用 K8s etcd) 或 独立 etcd                      |   |
  |  +-----------------------------------------------------------+   |
  +------------------------------------------------------------------+
```

### 1.4 三种网络模式对比

```
  IPIP 模式 (Overlay)              VXLAN 模式 (Overlay)         BGP 模式 (Underlay)
  +-----------+  +-----------+     +-----------+  +-----------+  +-----------+  +-----------+
  |  Node-1   |  |  Node-2   |     |  Node-1   |  |  Node-2   |  |  Node-1   |  |  Node-2   |
  | 10.244.1.0|  | 10.244.2.0|     | 10.244.1.0|  | 10.244.2.0|  | 10.244.1.0|  | 10.244.2.0|
  |     |     |  |     |     |     |     |     |  |     |     |  |     |     |  |     |     |
  |  [IPIP    |  |  [IPIP    |     |  [VXLAN   |  |  [VXLAN   |  |  [BGP     |  |  [BGP     |
  |   Tunnel] |  |   Tunnel] |     |   Tunnel] |  |   Tunnel] |     Route]  |  |   Route]  |
  |     |     |  |     |     |     |     |     |  |     |     |  |     |     |  |     |     |
  | 192.168.  |  | 192.168.  |     | 192.168.  |  | 192.168.  |  | 192.168.  |  | 192.168.  |
  | 1.54      |  | 1.55      |     | 1.54      |  | 1.55      |  | 1.54      |  | 1.55      |
  +-----+-----+  +-----+-----+     +-----+-----+  +-----+-----+  +-----+-----+  +-----+-----+
        |               |                 |               |                 |               |
        +-------+-------+                 +-------+-------+                 +-------+-------+
                |                                 |                                 |
          IP-in-IP 封装                       VXLAN 封装                       直接路由
          (IP Protocol 4)                   (UDP Port 4789)                  (需路由器支持)
```

---

## 2. 理论基础

### 2.1 CNI（Container Network Interface）

CNI 是 Kubernetes 定义的网络插件接口标准，包含以下规范：

| 接口 | 说明 |
|------|------|
| `ADD` | 将容器加入网络（分配 IP、设置路由） |
| `DEL` | 将容器从网络移除（释放 IP、清理路由） |
| `CHECK` | 检查容器网络状态 |
| `VERSION` | 查询 CNI 插件版本 |

CNI 工作流程：
```
kubelet 创建 Pod
    |
    v
kubelet 调用 CRI RuntimeService.RunPodSandbox
    |
    v
CRI 调用 CNI 插件 (calico /opt/cni/bin/calico)
    |
    v
CNI 插件执行:
  1. 创建 veth pair（虚拟以太网对，容器端 + 宿主端）
  2. 将容器端 veth 移入容器 Network Namespace（网络命名空间）
  3. 分配 IP 地址 (从 IPAM 获取)
  4. 设置路由规则
  5. 返回结果给 CRI
```

### 2.2 Calico vs Flannel vs Cilium 对比

| 特性 | Calico | Flannel | Cilium |
|------|--------|---------|--------|
| **网络模式** | BGP/IPIP/VXLAN | VXLAN/host-gw | eBPF/VXLAN |
| **NetworkPolicy** | 完整支持 | 不支持 | 完整支持 |
| **性能** | 高（BGP 直连） | 中（VXLAN 封装开销） | 最高（eBPF 绕过 iptables） |
| **复杂度** | 中 | 低 | 高 |
| **数据面** | iptables/IPVS + eBPF | iptables | eBPF（内核态处理） |
| **适用规模** | 大规模 | 中小规模 | 超大规模 |
| **加密** | WireGuard（无线守卫） | IPsec（IP 安全协议） | WireGuard/IPsec |
| **可观测性** | Felix metrics | 有限 | Hubble（完整可观测） |
| **社区** | Tigera/VMware | CNCF 孵化 | CNCF 毕业项目 |
| **推荐场景** | 通用/安全要求高 | 简单部署 | 高性能/可观测性 |

### 2.3 Calico 网络模式详解

| 模式 | 封装 | 性能 | 要求 | 适用场景 |
|------|------|------|------|---------|
| **BGP (Direct Routing)** | 无 | 最高 | 路由器支持 BGP | 数据中心/云环境 |
| **IPIP** | IP-in-IP | 中 | 无特殊要求 | 通用（默认） |
| **VXLAN** | VXLAN | 中 | 无特殊要求 | 不支持 IPIP 的环境 |
| **IPIP-跨子网** | 跨子网用 IPIP | 高 | 同子网直连 | 混合网络环境 |

### 2.4 NetworkPolicy 概述

```
  默认行为 (无 NetworkPolicy):
  +-----------+     +-----------+
  | Pod A     |<--->| Pod B     |
  | (任意访问) |     | (任意访问) |
  +-----------+     +-----------+

  默认拒绝策略:
  +-----------+     +-----------+
  | Pod A     | X   | Pod B     |
  | (拒绝所有) |     | (拒绝所有) |
  +-----------+     +-----------+

  精细控制:
  +-----------+     +-----------+
  | Pod A     |---->| Pod B     |
  | (允许 80) |     | (允许 80) |
  +-----------+     +-----------+
        | X
        +-----> Pod C (拒绝)
```

---

## 3. 离线前置准备

> **环境说明：** 本课程基于 6 节点 K8s v1.28.15 离线集群，Harbor 地址 192.168.1.61（HTTP，密码 Harbor12345），无外网访问，Calico v3.26.4，podSubnet 10.244.0.0/16。

### 3.0.1 离线环境信息确认

```bash
# 确认集群版本
kubectl version --short
# Client Version: v1.28.15
# Server Version: v1.28.15

# 确认 podSubnet（应与 Calico IP Pool 一致）
kubectl get cm kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' | grep podSubnet
# podSubnet: 10.244.0.0/16

# 确认 Harbor 可达
curl -s -u admin:Harbor12345 http://192.168.1.61/api/v2/systeminfo | python3 -m json.tool
# "hostname": "192.168.1.61"
# "status": "healthy"

# 确认所有节点状态
kubectl get nodes
# 6 个节点均应为 Ready（网络插件安装前可能为 NotReady）
```

### 3.0.2 Harbor 项目准备

```bash
# 确保 Harbor 中已创建 calico 项目（用于存放 Calico 镜像）
# 如未创建，通过 Harbor API 或 Web UI 创建
curl -X POST "http://192.168.1.61/api/v2.0/projects" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"project_name": "calico", "public": true}'
```

### 3.0.3 离线资源传输流程

```
  +-------------------+        scp/usb         +-------------------+
  |   美国服务器        |  ==================>  |   Master-1 节点     |
  |   (有外网)         |                        |   (192.168.1.51)   |
  |                   |                        |                   |
  | 1. 下载 calico.yaml                      | 1. 接收 calico.yaml|
  | 2. 替换镜像地址                             | 2. kubectl apply  |
  | 3. 推送镜像到 Harbor                       |                   |
  +-------------------+                        +-------------------+
         |                                                |
         |  docker push                                   |  crictl pull
         v                                                v
  +---------------------------------------------------------------+
  |                    Harbor (192.168.1.61)                       |
  |                    项目: calico/                                |
  |                    - node:v3.26.4                               |
  |                    - kube-controllers:v3.26.4                   |
  |                    - cni:v3.26.4                                 |
  |                    - typha:v3.26.4 (可选)                       |
  +---------------------------------------------------------------+
```

### 3.0.4 containerd 配置确认

```bash
# 确认所有节点的 containerd 已配置 Harbor 为 HTTP 仓库（非 HTTPS）
# 检查 Master-1 的 containerd 配置
cat /etc/containerd/config.toml | grep -A 3 "\[plugins.*registry.*mirrors.*192.168.1.61\]"
# 预期输出：
#   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.1.61"]
#     endpoint = ["http://192.168.1.61"]

# 如果未配置，需要在所有 6 个节点上添加配置
# 参考 01-Containerd 模块的 Harbor 配置步骤
```

---

## 4. 部署实战

### 4.1 下载 Calico Manifest（离线方式）

> **注意：** 离线环境无法直接访问 GitHub，需要在有外网的服务器上下载并预处理。

```bash
# ========== 第一步：在美国服务器（有外网）上执行 ==========
ssh us-server
cd /tmp

# 下载 Calico v3.26.4 官方 YAML
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/calico.yaml

# 提取 YAML 中所有镜像地址
grep -oP 'image: \K.*' calico.yaml | sort -u
# 预期输出（示例）：
#   docker.io/calico/node:v3.26.4
#   docker.io/calico/kube-controllers:v3.26.4
#   docker.io/calico/cni:v3.26.4
#   docker.io/calico/typha:v3.26.4
#   quay.io/calico/cni:v3.26.4
#   quay.io/calico/node:v3.26.4
#   ghcr.io/projectcalico/calico/...  (如有)

# 替换所有镜像源为 Harbor 地址
sed -i 's|docker.io/|192.168.1.61/|g' calico.yaml
sed -i 's|quay.io/|192.168.1.61/|g' calico.yaml
sed -i 's|ghcr.io/|192.168.1.61/|g' calico.yaml

# 验证替换结果：确认无外网镜像地址残留
grep -E 'docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io' calico.yaml
# 预期：无输出（所有外网地址已替换为 Harbor）

grep "image:" calico.yaml | sort -u
# 预期：所有 image 均以 192.168.1.61/ 开头

# ========== 第二步：将 calico.yaml 传输到 Master-1 ==========
scp calico.yaml root@192.168.1.51:/root/
```

### 4.2 Calico 镜像预推送

> **前置条件：** 在安装 Calico 之前，必须将所有所需镜像预先推送到 Harbor。

#### 4.2.1 Calico v3.26.4 镜像清单

| 镜像名称 | 用途 | 必需 |
|----------|------|------|
| `docker.io/calico/node:v3.26.4` | Calico Node（Felix + BIRD），每个节点运行 | 是 |
| `docker.io/calico/kube-controllers:v3.26.4` | NetworkPolicy 控制器，全局 1 副本 | 是 |
| `docker.io/calico/cni:v3.26.4` | CNI 插件二进制，每个节点需要 | 是 |
| `docker.io/calico/typha:v3.26.4` | Typha API 代理（>50节点时推荐） | 可选 |

#### 4.2.2 使用 sync_images.sh 脚本同步镜像

```bash
# ========== 在美国服务器（有外网）上执行 ==========
ssh us-server

# 创建镜像同步脚本
cat > /tmp/sync_calico_images.sh << 'SCRIPT'
#!/bin/bash
# Calico v3.26.4 镜像同步脚本
# 用途：从公网拉取 Calico 镜像并推送到 Harbor

HARBOR_ADDR="192.168.1.61"
HARBOR_USER="admin"
HARBOR_PASS="Harbor12345"
CALICO_VERSION="v3.26.4"

# Calico 镜像列表（含可能的多个镜像源前缀）
IMAGES=(
    "docker.io/calico/node:${CALICO_VERSION}"
    "docker.io/calico/kube-controllers:${CALICO_VERSION}"
    "docker.io/calico/cni:${CALICO_VERSION}"
    "docker.io/calico/typha:${CALICO_VERSION}"
)

# 登录 Harbor
echo "=== 登录 Harbor ${HARBOR_ADDR} ==="
echo "${HARBOR_PASS}" | docker login ${HARBOR_ADDR} -u "${HARBOR_USER}" --password-stdin || {
    echo "错误: Harbor 登录失败"; exit 1
}

# 拉取、打标签、推送
for img in "${IMAGES[@]}"; do
    echo "=== 处理: ${img} ==="

    # 拉取原始镜像
    docker pull "${img}" || {
        echo "警告: 拉取失败 ${img}，尝试其他源..."
        continue
    }

    # 去掉前缀，生成 Harbor 目标路径
    # docker.io/calico/node:v3.26.4 -> calico/node:v3.26.4
    no_prefix="${img#*/}"
    target="${HARBOR_ADDR}/${no_prefix}"

    # 打标签
    docker tag "${img}" "${target}"

    # 推送到 Harbor
    docker push "${target}"

    echo "=== 完成: ${img} -> ${target} ==="
    echo
done

echo "=== 所有镜像同步完成 ==="
echo "验证:"
for img in "${IMAGES[@]}"; do
    no_prefix="${img#*/}"
    target="${HARBOR_ADDR}/${no_prefix}"
    echo "  ${target}"
done
SCRIPT

chmod +x /tmp/sync_calico_images.sh
bash /tmp/sync_calico_images.sh
```

#### 4.2.3 在 Master 节点验证镜像可用

```bash
# 在 Master-1 上验证所有 Calico 镜像已在 Harbor 中
curl -s -u admin:Harbor12345 \
    "http://192.168.1.61/api/v2/projects/calico/repositories?page_size=50" \
    | python3 -m json.tool 2>/dev/null || \
    curl -s -u admin:Harbor12345 \
    "http://192.168.1.61/api/v2/projects/calico/repositories?page_size=50"

# 在每个节点上验证能否拉取镜像（containerd 环境）
crictl pull 192.168.1.61/calico/node:v3.26.4
crictl pull 192.168.1.61/calico/kube-controllers:v3.26.4
crictl pull 192.168.1.61/calico/cni:v3.26.4
# crictl pull 192.168.1.61/calico/typha:v3.26.4  # 如使用 Typha
```

### 4.3 修改 Calico 配置

#### 4.3.1 修改 Pod 子网

```bash
# 设置 CALICO_IPV4POOL_CIDR 为 Pod 子网
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' calico.yaml
sed -i 's|#   value: "192.168.0.0/16"|  value: "10.244.0.0/16"|' calico.yaml
```

#### 4.3.2 修改镜像源为 Harbor

> **注意：** 如果已在 4.1 节的美国服务器上完成了镜像替换，此步骤可跳过。以下命令供在 Master 节点上直接修改时使用。

```bash
# 替换所有已知镜像源为 Harbor 地址
# Calico v3.26.4 的镜像可能来自以下仓库：
sed -i 's|docker.io/|192.168.1.61/|g' calico.yaml
sed -i 's|quay.io/|192.168.1.61/|g' calico.yaml
sed -i 's|ghcr.io/|192.168.1.61/|g' calico.yaml
sed -i 's|gcr.io/|192.168.1.61/|g' calico.yaml
sed -i 's|registry.k8s.io/|192.168.1.61/|g' calico.yaml

# 验证替换结果：确认无外网镜像地址残留
grep -E 'docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io' calico.yaml
# 预期：无输出（所有外网地址已替换为 Harbor）

# 验证所有镜像均指向 Harbor
grep "image:" calico.yaml | sort -u
# 预期输出示例：
#   image: 192.168.1.61/calico/node:v3.26.4
#   image: 192.168.1.61/calico/kube-controllers:v3.26.4
#   image: 192.168.1.61/calico/cni:v3.26.4
#   image: 192.168.1.61/calico/typha:v3.26.4
```

#### 4.3.3 设置网络模式（可选）

```bash
# 默认使用 IPIP 模式，如果需要 VXLAN 模式：
sed -i 's|# - name: CALICO_IPV4POOL_VXLAN|- name: CALICO_IPV4POOL_VXLAN|' calico.yaml
sed -i 's|#   value: "Always"|  value: "Always"|' calico.yaml

# 如果需要 BGP 直接路由模式（不封装）：
sed -i 's|# - name: CALICO_IPV4POOL_IPIP|- name: CALICO_IPV4POOL_IPIP|' calico.yaml
sed -i 's|#   value: "Never"|  value: "Never"|' calico.yaml
```

### 4.4 安装 Calico

```bash
kubectl apply -f calico.yaml
```

### 4.5 验证 Calico 安装

```bash
# 检查 Calico Pod 状态
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide
# 每个节点应有一个 calico-node Pod，状态为 Running

kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers
# 应有 1 个 calico-kube-controllers Pod

# 检查节点状态
kubectl get nodes
# 所有节点应变为 Ready

# 检查 Calico 节点状态
kubectl get ippools -o wide
# NAME                  CIDR             SELECTOR
# default-ipv4-ippool   10.244.0.0/16    all()
```

### 4.6 NetworkPolicy 实战

#### 4.6.1 创建测试命名空间和 Pod

```bash
# 创建测试命名空间
kubectl create namespace policy-demo

# 创建 Nginx Pod
kubectl run nginx --image=192.168.1.61/k8s/nginx:alpine -n policy-demo \
    --labels app=nginx --port=80

# 创建 BusyBox Pod（客户端）
kubectl run client --image=192.168.1.61/k8s/busybox:latest -n policy-demo \
    --labels app=client --command -- sleep 3600

# 创建另一个 BusyBox Pod
kubectl run client2 --image=192.168.1.61/k8s/busybox:latest -n policy-demo \
    --labels app=client2 --command -- sleep 3600

# 验证默认网络互通
kubectl exec -n policy-demo client -- wget -q -O- http://nginx.policy-demo
# 预期: Nginx 欢迎页面
```

#### 4.6.2 默认拒绝所有入站流量

```bash
cat > /root/deny-all-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1  # 网络 API 组
kind: NetworkPolicy  # 网络策略
metadata:
  name: deny-all-ingress
  namespace: policy-demo
spec:
  podSelector: {}  # 选择所有 Pod
  policyTypes:
    - Ingress      # 拒绝所有入站流量
EOF

kubectl apply -f /root/deny-all-ingress.yaml

# 验证：Nginx 不再可访问
kubectl exec -n policy-demo client -- wget -q -O- --timeout=3 http://nginx.policy-demo
# 预期: 连接超时
```

#### 4.6.3 允许特定标签的 Pod 访问 Nginx

```bash
cat > /root/allow-nginx.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-from-client
  namespace: policy-demo
spec:
  podSelector:
    matchLabels:
      app: nginx           # 应用于 Nginx Pod
  policyTypes:
    - Ingress  # 入站策略
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: client   # 只允许 client Pod 访问
      ports:
        - protocol: TCP
          port: 80  # HTTP 端口
EOF

kubectl apply -f /root/allow-nginx.yaml

# 验证：client 可以访问 Nginx
kubectl exec -n policy-demo client -- wget -q -O- http://nginx.policy-demo
# 预期: Nginx 欢迎页面

# 验证：client2 不能访问 Nginx
kubectl exec -n policy-demo client2 -- wget -q -O- --timeout=3 http://nginx.policy-demo
# 预期: 连接超时
```

#### 4.6.4 Namespace 隔离

```bash
# 创建两个命名空间
kubectl create namespace dev
kubectl create namespace prod

# 在每个命名空间中创建 Nginx
kubectl run nginx --image=192.168.1.61/k8s/nginx:alpine -n dev --port=80
kubectl run nginx --image=192.168.1.61/k8s/nginx:alpine -n prod --port=80

# 创建客户端
kubectl run client --image=192.168.1.61/k8s/busybox:latest -n dev --command -- sleep 3600
kubectl run client --image=192.168.1.61/k8s/busybox:latest -n prod --command -- sleep 3600

# 默认情况下，dev 可以访问 prod 的 Nginx
kubectl exec -n dev client -- wget -q -O- http://nginx.prod
# 预期: 成功

# 创建 Namespace 隔离策略：禁止 dev 访问 prod
cat > /root/namespace-isolation.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-dev
  namespace: prod
spec:
  podSelector: {}           # 选择 prod 命名空间的所有 Pod
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              env: prod      # 只允许 prod 命名空间的流量
EOF

# 给命名空间打标签
kubectl label namespace prod env=prod
kubectl label namespace dev env=dev

kubectl apply -f /root/namespace-isolation.yaml

# 验证：dev 不能访问 prod
kubectl exec -n dev client -- wget -q -O- --timeout=3 http://nginx.prod
# 预期: 连接超时

# 验证：prod 内部可以访问
kubectl exec -n prod client -- wget -q -O- http://nginx.prod
# 预期: 成功
```

#### 4.6.5 DNS 放行策略

```bash
# NetworkPolicy 默认会阻止 DNS 请求，需要放行 CoreDNS
# 注意：DNS 放行需要在 Egress 方向放行（Pod 主动发起 DNS 请求）
cat > /root/allow-dns.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: policy-demo
spec:
  podSelector: {}           # 选择所有 Pod
  policyTypes:
    - Egress  # 出站策略
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns  # CoreDNS Pod 的标签
      ports:
        - protocol: UDP
          port: 53  # DNS 端口
        - protocol: TCP
          port: 53
EOF

kubectl apply -f /root/allow-dns.yaml
```

#### 4.6.6 Egress 出站策略

```bash
# 限制 Pod 只能访问特定外部地址
cat > /root/allow-egress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: policy-demo
spec:
  podSelector:
    matchLabels:
      app: client  # 应用于 client Pod
  policyTypes:
    - Egress  # 出站策略
  egress:
    # 允许 DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns  # CoreDNS
      ports:
        - protocol: UDP
          port: 53  # DNS 端口
        - protocol: TCP
          port: 53
    # 允许访问特定 IP
    - to:
        - ipBlock:
            cidr: 192.168.1.0/24  # 目标网段
            except:
              - 192.168.1.61/32  # 排除 Harbor
      ports:
        - protocol: TCP
          port: 80  # HTTP 端口
EOF

kubectl apply -f /root/allow-egress.yaml
```

### 4.7 清理测试资源

```bash
kubectl delete namespace policy-demo dev prod
```

---

## 5. 配置详解

### 5.1 Calico IP Pool 配置

```bash
# 查看默认 IP Pool
kubectl get ippools default-ipv4-ippool -o yaml

# 创建自定义 IP Pool
cat > /root/custom-ippool.yaml << 'EOF'
apiVersion: crd.projectcalico.org/v1  # Calico CRD API
kind: IPPool  # IP 地址池
metadata:
  name: custom-pool
spec:
  cidr: 10.244.0.0/16  # IP 地址范围
  ipipMode: Always        # IPIP 封装模式: Always/Never/CrossSubnet
  vxlanMode: Never        # VXLAN 模式: Always/Never/CrossSubnet
  natOutgoing: true       # 启用 NAT 出站（地址转换）
  blockSize: 26           # 每个 Block 的 IP 数量（默认 26 = 64 个 IP）
  nodeSelector: "all()"   # 节点选择器
EOF

kubectl apply -f /root/custom-ippool.yaml
```

### 5.2 BGP 配置

```bash
# 查看默认 BGP 配置
kubectl get bgpconfig default -o yaml

# 修改 BGP 配置（全局 AS 号）
cat > /root/bgp-config.yaml << 'EOF'
apiVersion: crd.projectcalico.org/v1
kind: BGPConfiguration  # BGP 配置
metadata:
  name: default
spec:
  asNumber: 64512           # 私有 AS 号（自治系统编号）
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: true  # 全互联 BGP（节点数 < 100 时启用）
  listenPort: 179  # BGP 标准端口
EOF

kubectl apply -f /root/bgp-config.yaml
```

### 5.3 Felix 配置

```bash
# Felix 是 Calico 的数据面代理，负责路由和 ACL（访问控制列表）管理
cat > /root/felix-config.yaml << 'EOF'
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration  # Felix 配置
metadata:
  name: default
spec:
  ipipEnabled: true         # 启用 IPIP
  ipipMode: Always          # IPIP 模式
  vxlanEnabled: false       # 禁用 VXLAN
  logSeverityScreen: Info
  chainInsertMode: Append   # iptables 规则插入模式
  defaultEndpointToHostAction: Accept  # 默认端点到宿主机行为
EOF

kubectl apply -f /root/felix-config.yaml
```

### 5.4 Calico 环境变量（Installation Manifest）

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `CALICO_IPV4POOL_CIDR` | 192.168.0.0/16 | IPv4 Pod 子网 |
| `CALICO_IPV4POOL_IPIP` | Always | IPIP 模式 |
| `CALICO_IPV4POOL_VXLAN` | Never | VXLAN 模式 |
| `CALICO_NETWORKING_BACKEND` | bird | 网络后端（bird/bird/vxlan） |
| `FELIX_LOGSEVERITYSCREEN` | info | Felix 日志级别 |
| `CALICO_IPV6POOL_CIDR` | - | IPv6 Pod 子网 |

---

## 6. 验证与测试

### 6.1 验证 Calico 网络连通性

```bash
# 创建跨节点测试
kubectl run test-node1 --image=192.168.1.61/k8s/busybox:latest \
    --overrides='{"spec":{"nodeName":"k8s-worker1"}}' --command -- sleep 3600

kubectl run test-node2 --image=192.168.1.61/k8s/busybox:latest \
    --overrides='{"spec":{"nodeName":"k8s-worker2"}}' --command -- sleep 3600

# 获取 Pod IP
POD1_IP=$(kubectl get pod test-node1 -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl get pod test-node2 -o jsonpath='{.status.podIP}')

# 测试跨节点 Ping
kubectl exec test-node1 -- ping -c 3 ${POD2_IP}
# 预期: 3 packets transmitted, 3 received

# 清理
kubectl delete pod test-node1 test-node2
```

### 6.2 验证 DNS 解析

```bash
kubectl run dns-test --image=192.168.1.61/k8s/busybox:latest --rm -it --restart=Never -- \
    nslookup kubernetes.default
# 预期:
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

# Name:      kubernetes.default
# Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```

### 6.3 验证 Service 访问

```bash
# 创建测试 Service
kubectl create deployment nginx-test --image=192.168.1.61/k8s/nginx:alpine --replicas=2
kubectl expose deployment nginx-test --port=80 --type=ClusterIP

# 测试 Service 访问
kubectl run curl-test --image=192.168.1.61/k8s/busybox:latest --rm -it --restart=Never -- \
    wget -q -O- http://nginx-test.default.svc.cluster.local

# 清理
kubectl delete deployment nginx-test svc nginx-test
```

### 6.4 检查 Calico 状态

```bash
# 检查 Calico 节点
calicoctl node status
# 预期: Calico process is running.
#       IPv4 BGP status: +PEER+ (表示 BGP 邻居已建立)

# 检查 BGP 路由
ip route | grep 10.244
# 预期: 10.244.x.0/26 via 192.168.1.xx dev tunl0 onlink

# 检查 IP Pool
kubectl get ippools -o wide

# 检查 Felix 日志
kubectl logs -n kube-system -l k8s-app=calico-node --tail=20 | grep -i error
```

---

## 7. CKA/CKS 考点融入

### 7.1 CKA 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 网络策略 | 创建和调试 NetworkPolicy | 4.6 节 |
| CNI 理解 | 理解 CNI 插件工作原理 | 2.1 节 |
| Service 网络 | ClusterIP/NodePort/LoadBalancer | 6.3 节 |

### 7.2 CKS 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 网络策略 | 默认拒绝 + 精细控制 | 4.6.2-4.6.6 节 |
| Namespace 隔离 | 命名空间级别的网络隔离 | 4.6.4 节 |
| Egress 控制 | 限制 Pod 出站流量 | 4.6.6 节 |

### 7.3 考试技巧

1. CKA 中 NetworkPolicy 是必考题，记住 `podSelector`、`namespaceSelector`、`ipBlock` 的用法
2. CKS 中默认拒绝策略是高频考点，注意 `policyTypes` 必须包含 `Ingress`
3. DNS 放行容易被忽略，在默认拒绝策略中必须放行 UDP/TCP 53 端口到 CoreDNS

---

## 8. 高频面试题

### Q1: 什么是 CNI？Kubernetes 网络模型的基本要求是什么？ [难度: 中]

**答案：** CNI（Container Network Interface）是 CNCF 定义的一组网络插件接口标准，定义了容器运行时（如 containerd）如何调用网络插件来配置容器的网络。CNI 规范包含 ADD（将容器加入网络）、DEL（将容器移出网络）、CHECK（检查网络状态）和 VERSION（查询版本）四个接口。Kubernetes 网络模型（由 K8s 网络模型定义）有三个基本要求：第一，所有 Pod 之间可以直接通信，不需要 NAT（Network Address Translation）；第二，所有 Node 与所有 Pod 之间可以直接通信，不需要 NAT；第三，Pod 看到的自身 IP 就是其他 Pod 看到它的 IP。这三个要求确保了 K8s 网络的扁平化特性，任何网络插件只要满足这三个要求就可以作为 K8s 的 CNI 插件。常见的 CNI 插件包括 Calico、Flannel、Cilium、Weave Net 等，它们通过不同的技术实现（BGP、VXLAN、eBPF）来满足 K8s 网络模型的要求。

### Q2: Calico 的三种网络模式（BGP/IPIP/VXLAN）有什么区别？如何选择？ [难度: 中]

**答案：** Calico 支持三种网络模式。BGP 模式（Direct Routing）使用标准 BGP 协议在节点之间交换路由信息，Pod 之间直接路由，不使用任何封装，性能最高但要求网络设备支持 BGP 路由（或使用 Node-to-Node Mesh 全互联模式）。IPIP 模式使用 IP-in-IP 封装（IP Protocol 4），将原始 IP 包封装在新的 IP 包中，通过隧道传输，适用于不支持 BGP 的网络环境，性能中等（有封装开销）。VXLAN 模式使用 VXLAN 封装（UDP 端口 4789），与 IPIP 类似但使用 UDP 封装，适用于某些不支持 IPIP 协议的云环境或防火墙环境。选择建议：如果网络设备支持 BGP 且节点数 < 100，优先使用 BGP 模式（性能最优）；如果网络不支持 BGP，使用 IPIP 模式（Calico 默认）；如果在某些云环境中 IPIP 被阻止，使用 VXLAN 模式。Calico 还支持 CrossSubnet 模式，同子网内直接路由，跨子网使用封装，是混合环境的最佳选择。

### Q3: NetworkPolicy 的工作原理是什么？默认行为是什么？ [难度: 中]

**答案：** NetworkPolicy 是 Kubernetes 原生的网络策略 API，用于控制 Pod 之间的网络流量。工作原理：当用户创建 NetworkPolicy 对象后，CNI 插件（如 Calico）通过 Watch API Server 获取 NetworkPolicy 的变化，然后将其转换为具体的数据面规则（iptables 规则或 eBPF 程序），应用到对应的节点上。NetworkPolicy 的核心概念包括：podSelector（选择策略应用的 Pod）、namespaceSelector（选择源/目标命名空间）、policyTypes（Ingress 入站/Egress 出站）、ports（端口和协议）、ipBlock（CIDR 网段）。默认行为：如果没有为任何 Pod 创建 NetworkPolicy，所有 Pod 之间的所有流量都是允许的（全通）；一旦为某个 Pod 创建了 NetworkPolicy，该 Pod 的流量将受到策略控制，未被明确允许的流量将被拒绝。这意味着 NetworkPolicy 是"白名单"模式，需要显式声明允许的流量。需要注意的是，NetworkPolicy 是命名空间级别的资源，只能控制同一集群内的流量，不能控制外部到集群的流量（需要通过 Ingress 或 LoadBalancer 控制）。

### Q4: 如何实现命名空间级别的网络隔离？ [难度: 高]

**答案：** 命名空间级别的网络隔离通过 NetworkPolicy 的 namespaceSelector 实现。实现步骤为：首先给需要隔离的命名空间打上标签（如 `kubectl label namespace prod env=prod`），然后在目标命名空间中创建默认拒绝入站策略（podSelector 为空，匹配所有 Pod），在 ingress 规则中使用 namespaceSelector 限制只允许特定命名空间的流量。关键点：namespaceSelector 选择的是源 Pod 所在的命名空间，而不是策略所在的命名空间；如果同时指定了 podSelector 和 namespaceSelector，两者是 AND 关系（同时满足）；如果只指定 namespaceSelector 不指定 podSelector，则允许目标命名空间的所有 Pod 访问。更精细的控制可以结合 labelSelector 进一步限制源 Pod 的标签。此外，还需要放行 DNS 流量（UDP/TCP 53 端口到 kube-system 命名空间的 CoreDNS Pod），否则 Pod 将无法解析域名。对于 Egress 控制，同样可以创建默认拒绝出站策略，然后只放行必要的出站流量（DNS、特定 Service 等）。

### Q5: Calico 的 Felix 组件的作用是什么？ [难度: 中]

**答案：** Felix 是 Calico 的数据面代理，运行在每个节点上，是 Calico 网络功能的核心执行者。Felix 的主要职责包括：第一，路由管理：Felix 监听 Calico 的数据存储（etcd 或 K8s API Server），当有新的 Pod 创建或删除时，Felix 负责在宿主机上添加或删除对应的路由规则，确保 Pod IP 可达。第二，ACL 管理：Felix 将 NetworkPolicy 转换为宿主机上的 iptables 规则（或 eBPF 程序），实现流量的精细控制。第三，IPIP 隧道管理：如果使用 IPIP 模式，Felix 负责创建和管理 tunl0 隧道设备。第四，接口管理：Felix 监听 veth 设备的变化，确保容器端和宿主端的 veth pair 正确配置。Felix 通过 Watch 机制实时感知集群变化，通常在毫秒级内完成路由和 ACL 的更新。在 Calico 的架构中，Felix 是唯一与 Linux 内核直接交互的组件，其他组件（BIRD、Typha、kube-controllers）都通过数据存储间接影响 Felix 的行为。

### Q6: 为什么 NetworkPolicy 中需要放行 DNS？不放行会有什么问题？ [难度: 低]

**答案：** 在创建默认拒绝入站/出站策略时，必须放行 DNS 流量，因为 Kubernetes 集群中的所有 Pod 都依赖 CoreDNS 进行服务发现和名称解析。如果不放行 DNS，Pod 将无法解析任何域名（包括 Kubernetes Service 名称），导致服务间通信完全中断。具体表现为：`nslookup` 命令超时、Service 域名无法解析、外部域名无法解析。放行 DNS 的 NetworkPolicy 需要允许到 kube-system 命名空间中标签为 `k8s-app=kube-dns` 的 Pod 的 UDP 和 TCP 53 端口流量。注意：DNS 放行策略应该应用于所有 Pod（podSelector 为空），且应该在默认拒绝策略之后立即创建。如果同时有 Ingress 和 Egress 的默认拒绝策略，需要在两个策略中都放行 DNS（Egress 方向放行 DNS 请求，Ingress 方向放行 DNS 响应）。

### Q7: Calico BIRD 组件的作用是什么？Node-to-Node Mesh 和 Route Reflector 有什么区别？ [难度: 高]

**答案：** BIRD（BGP Internet Routing Daemon）是 Calico 使用的 BGP 路由守护进程，运行在每个 Calico 节点上。BIRD 负责与其他节点（或外部路由器）建立 BGP 会话，交换路由信息，将 Pod 的路由信息广播到整个网络。Node-to-Node Mesh（全互联）是 Calico 的默认 BGP 模式，每个 Calico 节点与集群中的所有其他节点建立 BGP 会话。在 N 个节点的集群中，会建立 N*(N-1)/2 个 BGP 会话。这种模式适用于中小规模集群（< 100 节点），配置简单，不需要额外的路由基础设施。Route Reflector（路由反射器）是大规模集群的 BGP 模式，节点不再全互联，而是将所有节点作为 BGP Client，连接到少数几个 Route Reflector 节点。Route Reflector 负责接收和转发路由信息，大幅减少 BGP 会话数量（从 O(N^2) 降到 O(N)）。当集群规模超过 100 节点时，必须使用 Route Reflector 模式。Calico 支持使用内置的 BIRD 作为 Route Reflector，也支持使用外部路由器（如 Juniper、Arista）。

### Q8: 如何排查 Pod 无法跨节点通信的问题？ [难度: 中]

**答案：** Pod 无法跨节点通信的排查步骤为：首先确认 CNI 插件是否正常：`kubectl get pods -n kube-system -l k8s-app=calico-node` 确认所有节点的 calico-node Pod 都在运行。然后检查路由表：在源节点上执行 `ip route | grep <目标Pod-CIDR>`，确认是否有到目标节点 Pod CIDR 的路由；如果没有路由，检查 Calico Felix 日志 `kubectl logs -n kube-system -l k8s-app=calico-node`。接着检查隧道状态：如果使用 IPIP 模式，`ip link show tunl0` 确认隧道设备存在且状态为 UP；`ip addr show tunl0` 确认隧道 IP 正确。然后检查 BGP 状态：`calicoctl node status` 确认 BGP 邻居已建立。接着检查防火墙：确认节点间的 BGP 端口（TCP 179）和 IPIP 协议（IP Protocol 4）或 VXLAN 端口（UDP 4789）未被防火墙阻止。最后检查 kubelet 和 containerd 日志，确认 Pod 的 veth pair 和网络命名空间配置正确。

### Q9: Calico 如何实现数据面的流量控制？iptables 还是 eBPF？ [难度: 高]

**答案：** Calico 支持两种数据面实现：iptables 模式（默认）和 eBPF 模式。在 iptables 模式下，Felix 将 NetworkPolicy 转换为宿主机上的 iptables 规则。Felix 使用 iptables 的 filter 表和 mangle 表，为每个 Pod 创建独立的 iptables 链（如 `cali-<pod-id>`），根据 NetworkPolicy 的规则在这些链中添加 ACCEPT/DROP 规则。当 Pod 发送或接收数据包时，数据包经过对应的 iptables 链，根据规则决定是否放行。iptables 模式的优点是兼容性好（所有 Linux 内核都支持），缺点是性能较低（每个数据包需要遍历多条 iptables 规则，大规模集群下规则数量可达数万条）。在 eBPF 模式下（Calico v3.7+ 支持），Felix 将 NetworkPolicy 编译为 eBPF 程序，挂载到内核的网络钩子点（XDP、tc）。eBPF 程序在内核空间直接处理数据包，不需要将数据包复制到用户空间，性能远高于 iptables。eBPF 模式还绕过了 iptables 的 conntrack，进一步降低了延迟。但 eBPF 模式要求较新的内核版本（>= 5.3）和特定的编译环境。

### Q10: 什么是 IPAM？Calico 如何管理 Pod IP 分配？ [难度: 中]

**答案：** IPAM（IP Address Management，IP 地址管理）是 CNI 规范的一部分，负责为容器分配和管理 IP 地址。Calico 内置了 IPAM 功能，通过 IP Pool 和 Block 机制管理 IP 分配。工作原理：Calico 将 Pod 子网（如 10.244.0.0/16）划分为多个 Block（默认每个 Block 为 /26，包含 64 个 IP），每个 Block 分配给一个节点。当节点上的 Pod 需要分配 IP 时，Calico 从该节点的 Block 中分配一个可用的 IP；当 Block 中的 IP 用完时，Calico 从 IP Pool 中申请新的 Block。IP 分配信息存储在 Calico 的数据存储中（etcd 或 K8s API Server 的 CRD）。当 Pod 被删除时，对应的 IP 被释放回 Block。如果 Block 中的所有 IP 都被释放且空闲超过一定时间（默认 60 分钟），Block 会被回收。Calico IPAM 的优势：自动分配、无需 DHCP、支持 IPv4/IPv6 双栈、Block 机制减少锁竞争（每个节点操作自己的 Block，不需要全局锁）。

### Q11: 如何在 Calico 中实现 Pod 的固定 IP？ [难度: 高]

**答案：** 在 Calico 中可以通过 IP Reservation 功能实现 Pod 的固定 IP。有两种方式：第一种是通过 Annotation，在创建 Pod 时指定 `cni.projectcalico.org/ipAddrs: '["10.244.1.100"]'`，Calico 会为该 Pod 分配指定的 IP。需要注意的是，指定的 IP 必须在 IP Pool 的 CIDR 范围内，且未被其他 Pod 使用。第二种是通过 Calico 的 IPAM Reservation API，预先从 IP Pool 中预留 IP，然后在 Pod 中引用。固定 IP 的使用场景包括：与外部系统集成（如遗留系统的 IP 白名单）、需要固定 IP 的有状态应用。但需要注意：固定 IP 会增加运维复杂度，需要手动管理 IP 分配，容易产生冲突；Pod 重建后 IP 保持不变，但不同 Pod 不能同时使用相同的 IP。在生产环境中，建议优先使用 Service 和 DNS 进行服务发现，避免依赖固定 IP。

### Q12: Calico 与 Cilium 的核心区别是什么？如何选择？ [难度: 高]

**答案：** Calico 和 Cilium 是目前最流行的两个 K8s 网络插件，核心区别在于数据面技术。Calico 使用 iptables + BGP 作为主要数据面，通过 iptables 规则实现 NetworkPolicy，通过 BGP 协议实现 Pod 路由。Cilium 使用 eBPF 作为数据面，通过 eBPF 程序实现 NetworkPolicy 和路由，绕过了 iptables 和 conntrack，性能更高。Cilium 的优势：第一，性能更高（eBPF 在内核空间处理数据包，延迟更低，吞吐更高）；第二，可观测性更强（Hubble 提供网络流量可视化、DNS 查询追踪、服务依赖图）；第三，支持 L7 网络策略（可以基于 HTTP header、gRPC 方法等应用层信息进行流量控制）；第四，透明加密（使用 eBPF 实现 WireGuard 加密，性能优于 iptables IPsec）。Calico 的优势：第一，成熟稳定（生产环境使用更广泛）；第二，BGP 原生支持（与物理网络集成更好）；第三，配置简单（默认配置即可满足大多数需求）；第四，资源占用较低。选择建议：如果需要 L7 策略和可观测性，选择 Cilium；如果需要 BGP 集成和简单部署，选择 Calico。

---

## 9. 故障排查案例

### 案例 1: Calico Pod 一直 Pending

**现象：**
```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
# NAME                READY   STATUS    RESTARTS   AGE
# calico-node-xxxxx   0/1     Pending   0          5m
```

**排查步骤：**
1. 查看事件：`kubectl describe pod calico-node-xxxxx -n kube-system`
2. 检查是否缺少 RBAC 权限
3. 检查节点是否 Ready

**解决方案：**
```bash
# 常见原因: 节点标签不匹配
# Calico DaemonSet 的 nodeSelector 可能不匹配某些节点
kubectl get ds calico-node -n kube-system -o yaml | grep nodeSelector

# 如果节点缺少标签
kubectl label node k8s-worker1 kubernetes.io/os=linux

# 如果是 RBAC 问题，重新应用 Calico manifest
kubectl apply -f calico.yaml
```

### 案例 2: 跨节点 Pod 无法通信

**现象：**
```bash
# Pod-A (Node-1) 无法 Ping Pod-B (Node-2)
kubectl exec pod-a -- ping -c 3 <pod-b-ip>
# PING 10.244.2.5: 100% packet loss
```

**排查步骤：**
1. 检查路由表：`ip route | grep 10.244`
2. 检查隧道设备：`ip link show tunl0`
3. 检查 BGP 状态：`calicoctl node status`
4. 检查 Felix 日志：`kubectl logs -n kube-system -l k8s-app=calico-node --tail=50`

**解决方案：**
```bash
# 原因1: 缺少到目标节点的路由
# 检查 BGP 是否建立
calicoctl node status
# 如果 BGP 未建立，检查防火墙
iptables -L INPUT -n | grep 179

# 原因2: IPIP 隧道未创建
ip link show tunl0
# 如果不存在，重启 calico-node
kubectl delete pod -n kube-system -l k8s-app=calico-node

# 原因3: IP Pool 配置错误
kubectl get ippools -o yaml
# 确认 CIDR 与 kubeadm-config.yaml 中的 podSubnet 一致
```

### 案例 3: NetworkPolicy 创建后 Pod 无法解析 DNS

**现象：**
```bash
# 创建默认拒绝策略后
kubectl exec -n policy-demo client -- nslookup nginx
# ;; connection timed out; no servers could be reached
```

**排查步骤：**
1. 检查是否有 DNS 放行策略：`kubectl get networkpolicy -n policy-demo`
2. 检查 CoreDNS 是否正常运行：`kubectl get pods -n kube-system -l k8s-app=kube-dns`
3. 检查 NetworkPolicy 的 ingress/egress 规则

**解决方案：**
```bash
# 创建 DNS 放行策略
cat > /root/allow-dns.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: policy-demo
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
EOF

kubectl apply -f /root/allow-dns.yaml
```

### 案例 4: Calico Felix 内存占用过高

**现象：**
```bash
kubectl top pods -n kube-system -l k8s-app=calico-node
# NAME          CPU   MEMORY
# calico-node   100m  2Gi
# 内存持续增长
```

**排查步骤：**
1. 检查 Felix 日志：`kubectl logs -n kube-system -l k8s-app=calico-node | grep -i "memory\|oom"`
2. 检查 iptables 规则数量：`iptables -S | wc -l`
3. 检查 NetworkPolicy 数量：`kubectl get networkpolicy --all-namespaces | wc -l`

**解决方案：**
```bash
# 原因: 大量 NetworkPolicy 导致 iptables 规则过多
# 方案1: 减少 NetworkPolicy 数量，合并策略
# 方案2: 切换到 eBPF 数据面（Calico v3.7+）
# 方案3: 增加 Felix 内存限制
kubectl edit ds calico-node -n kube-system
# 在 container calico-node 中修改 resources.limits.memory

# 方案4: 调整 Felix 参数减少内存使用
kubectl patch felixconfiguration default --type merge \
    -p '{"spec":{"routeRefreshInterval":"60s","iptablesRefreshInterval":"60s"}}'
```

### 案例 5: Pod IP 冲突

**现象：**
```bash
# 两个 Pod 分配了相同的 IP
kubectl get pod -o wide
# pod-a   10.244.1.5   k8s-worker1
# pod-b   10.244.1.5   k8s-worker2
```

**排查步骤：**
1. 检查 IPAM 状态：`calicoctl ipam show`
2. 检查 Block 分配：`calicoctl ipam show --show-blocks`
3. 检查是否有手动分配的 IP 冲突

**解决方案：**
```bash
# 清理冲突的 IPAM 数据
# 1. 删除有问题的 Block
calicoctl delete block <block-cidr>

# 2. 重启 calico-node 重新分配
kubectl delete pod -n kube-system -l k8s-app=calico-node

# 3. 如果问题持续，清理 IPAM 数据库
# 注意: 此操作会导致所有 Pod 的 IP 重新分配
kubectl delete ippool default-ipv4-ippool
kubectl apply -f calico.yaml
```

### 案例 6: Calico 升级后网络不通

**现象：**
```bash
# Calico 从 v3.25 升级到 v3.26 后
# Pod 之间无法通信
kubectl logs -n kube-system -l k8s-app=calico-node | grep error
# "error initializing BGP: unable to start BGP"
```

**排查步骤：**
1. 检查 Calico 版本：`kubectl get ds calico-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'`
2. 检查 CRD 版本：`kubectl get crd | grep calico`
3. 检查 Felix 配置兼容性

**解决方案：**
```bash
# 1. 确认 CRD 已更新（使用本地 calico.yaml）
kubectl apply -f calico.yaml --server-side

# 2. 如果 CRD 版本不匹配，先删除旧 CRD 再重新安装
# 警告: 删除 CRD 会丢失所有 Calico 自定义资源
kubectl get crd | grep calico | awk '{print $1}' | xargs kubectl delete crd

# 3. 重新安装 Calico
kubectl apply -f calico.yaml

# 4. 重启所有 Pod
kubectl delete pod -n kube-system -l k8s-app=calico-node
kubectl delete pod -n kube-system -l k8s-app=calico-kube-controllers
```

---

## 10. Calico高级网络策略（进阶）

> 本节介绍Calico的高级网络策略功能，超越K8s原生NetworkPolicy。
> 
> **适用场景**: 多租户隔离、全局安全策略、策略分层管理
> **核心CRD**: GlobalNetworkPolicy、NetworkPolicy (Calico)、Tier

### 10.1 K8s原生NetworkPolicy局限

| 局限 | 说明 | Calico解决方案 |
|------|------|----------------|
| **命名空间隔离** | 无法创建跨命名空间策略 | GlobalNetworkPolicy |
| **策略优先级** | 所有策略平等，无法分层 | Tier机制 |
| **外部流量** | 无法定义集群外流量规则 | HostEndpoint |
| **命名规则** | 必须在命名空间内 | 集群级策略 |
| **动作类型** | 仅Allow，无Deny | 支持Allow/Deny/Pass/Log |

### 10.2 GlobalNetworkPolicy

**全局策略示例**:
```yaml
# 全局拒绝所有入站（除DNS）
apiVersion: projectcalico.org/v3  # Calico 原生 API
kind: GlobalNetworkPolicy  # 全局网络策略
metadata:
  name: default-deny-ingress
spec:
  # 全局策略不需要 namespace
  selector: all()  # 匹配所有 Pod
  ingress:
    - action: Deny  # 拒绝动作
  # 放行DNS（例外）
  egress:
    - action: Allow
      protocol: UDP
      destination:
        ports: [53]
    - action: Allow
      protocol: TCP
      destination:
        ports: [53]
---
# 全局放行监控采集
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: allow-prometheus
spec:
  selector: all()
  ingress:
    - action: Allow
      protocol: TCP
      source:
        selector: app.kubernetes.io/name == 'prometheus'
      destination:
        ports: [9090, 8080, 8081]
```

### 10.3 Tier策略分层

**Tier架构**:
```
┌─────────────────────────────────────────────────────────────┐
│                    Tier: security (最高优先级)               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  GlobalNetworkPolicy: deny-malicious-ips            │   │
│  │  GlobalNetworkPolicy: allow-admin-access            │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Tier: platform (中优先级)                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  GlobalNetworkPolicy: allow-monitoring              │   │
│  │  GlobalNetworkPolicy: allow-system-services         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Tier: application (默认)                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  NetworkPolicy: allow-app-a-to-app-b                │   │
│  │  NetworkPolicy: allow-app-ingress                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**创建Tier**:
```yaml
# 创建安全层Tier（最高优先级）
apiVersion: projectcalico.org/v3
kind: Tier  # 策略分层
metadata:
  name: security
spec:
  order: 100  # 数字越小优先级越高
---
# 创建平台层Tier
apiVersion: projectcalico.org/v3
kind: Tier
metadata:
  name: platform
spec:
  order: 200
---
# 应用层Tier（默认）
apiVersion: projectcalico.org/v3
kind: Tier
metadata:
  name: application
spec:
  order: 300
```

**将策略绑定到Tier**:
```yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-malicious-ips
spec:
  tier: security  # 绑定到security层
  selector: all()
  ingress:
    - action: Deny
      source:
        nets:
          - 10.0.0.0/8  # 示例：拒绝特定IP段
```

### 10.4 HostEndpoint

**节点级网络策略**:
```yaml
# 定义节点端点
apiVersion: projectcalico.org/v3
kind: HostEndpoint  # 主机端点（保护节点本身）
metadata:
  name: node1-eth0
  labels:
    node: node1
    interface: eth0
spec:
  node: node1
  interfaceName: eth0  # 网卡接口名
  expectedIPs: ["192.168.1.51"]  # 预期 IP 地址
---
# 节点级策略（保护节点本身）
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: protect-nodes
spec:
  selector: node-role.kubernetes.io/control-plane == 'true'
  ingress:
    - action: Allow
      protocol: TCP
      destination:
        ports: [6443, 2379, 2380, 10250, 10259, 10257]
    - action: Allow
      protocol: TCP
      source:
        nets: ["192.168.1.0/24"]  # 内网SSH
      destination:
        ports: [22]
    - action: Deny  # 拒绝其他所有入站
```

### 10.5 策略动作类型

| 动作 | 说明 | 使用场景 |
|------|------|----------|
| **Allow** | 放行流量 | 正常放行规则 |
| **Deny** | 拒绝流量 | 明确拒绝规则 |
| **Pass** | 跳过当前Tier，进入下一Tier | 分层策略中跳过 |
| **Log** | 记录但不阻断（调试用） | 策略调试 |

```yaml
# Log动作示例（调试）
apiVersion: projectcalico.org/v3
kind: NetworkPolicy
metadata:
  name: debug-policy
  namespace: default
spec:
  selector: app == 'myapp'
  ingress:
    - action: Log
      source:
        selector: app == 'unknown'
    - action: Allow  # Log后再Allow
```

### 10.6 查看策略状态

```bash
# 查看所有GlobalNetworkPolicy
calicoctl get globalnetworkpolicy

# 查看Tier
calicoctl get tier

# 查看策略详情
calicoctl get globalnetworkpolicy default-deny-ingress -o yaml

# 查看HostEndpoint
calicoctl get hostendpoint

# 查看策略影响范围
calicoctl get networkpolicy --all-namespaces
```

---

## 10b. eBPF 与 Cilium 深入（进阶）

> **为什么需要了解 Cilium/eBPF？** Calico 是当前课程的默认 CNI，但 Cilium 已成为 CNCF 毕业项目（2023），并在 2026 年成为高性能集群的新标准。面试中「Calico vs Cilium」是高频对比题。本节提供完整对比评估框架。

### 10b.1 eBPF 是什么？

eBPF（extended Berkeley Packet Filter，扩展伯克利包过滤器）是 Linux 内核中的沙盒虚拟机，允许在**内核态**安全运行用户自定义程序，无需修改内核源码或加载内核模块。

```
传统网络路径 (iptables):  应用 → 用户态 → 内核态(iptables规则匹配) → 网卡
                          └── 数据包在 iptables 链表中逐条匹配，O(n) 复杂度

eBPF 网络路径 (Cilium):   应用 → 用户态 → 内核态(eBPF程序直通) → 网卡
                          └── 数据包直接处理，O(1) 复杂度
```

**eBPF 的核心价值**：
- **高性能**：绕过 iptables 链表查询，直接在内核处理
- **可编程**：可在内核中实现自定义网络、安全、可观测性逻辑
- **安全**：BPF 验证器确保程序不会 crash 内核

### 10b.2 Cilium 架构

```
┌─────────────────────────────────────────────────┐
│                  Cilium Agent                    │
│  ┌───────────┐ ┌──────────┐ ┌────────────────┐  │
│  │ eBPF 程序  │ │ 安全策略  │ │ Hubble 可观测  │  │
│  │ (数据面)   │ │ (L3/L4/L7)│ │ (流量可视化)   │  │
│  └─────┬─────┘ └────┬─────┘ └───────┬────────┘  │
│        │             │               │           │
│  ┌─────▼─────────────▼───────────────▼────────┐  │
│  │              Linux 内核 eBPF              │  │
│  │  (XDP → TC → Socket → L7 Proxy)          │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

| 组件 | 作用 |
|------|------|
| **Cilium Agent** | 每个节点运行，管理 eBPF 程序，实现网络/安全/负载均衡 |
| **Cilium Operator** | 集群级管理（IPAM 等） |
| **Hubble** | 基于 eBPF 的流量可观测性平台（不修改应用代码） |
| **eBPF 数据面** | 替代 kube-proxy（iptables），直接在内核处理转发 |

### 10b.3 Cilium vs Calico 深度对比

| 维度 | Calico (当前课程) | Cilium (eBPF 原生) |
|------|-------------------|---------------------|
| **数据面** | iptables/IPVS（默认）+ eBPF 模式 | **纯 eBPF**（无 iptables 依赖） |
| **网络策略** | L3/L4 NetworkPolicy | **L3/L4/L7**（HTTP/gRPC/Kafka 协议感知） |
| **可观测性** | Felix metrics（指标） | **Hubble**（实时流量图 + L7 可视化 + 丢包诊断） |
| **Service 转发** | kube-proxy（iptables 链表） | **eBPF 替代 kube-proxy**（无代理模式） |
| **大规模性能** | 规则多时 iptables 遍历慢 | O(1) 哈希查找，不受规则数量影响 |
| **加密** | WireGuard | WireGuard + IPsec（透明加密） |
| **Service Mesh** | 需 Istio sidecar | **Sidecar-less**（eBPF 实现 mTLS） |
| **CNCF 状态** | — | **毕业项目** |
| **运维复杂度** | 中 | 较高（需理解 eBPF + 内核版本要求 ≥ 5.4） |
| **适用场景** | 通用生产环境 | 高性能 + L7 安全 + 全栈可观测 |

### 10b.4 什么时候选 Cilium？

| 场景 | 推荐 CNI |
|------|----------|
| 标准 K8s 集群（< 50 节点） | Calico（运维简单） |
| 大规模集群（> 500 节点 + 大量 NetworkPolicy） | **Cilium**（iptables 瓶颈） |
| 需要 L7 策略（限制 HTTP 路径/Header） | **Cilium**（Calico 不支持 L7） |
| 需要流量可视化（Hubble UI） | **Cilium** |
| 已熟悉 Calico 且无性能瓶颈 | 保持 Calico |
| 离线/隔离环境 | 两者均支持 |

### 10b.5 Cilium L7 策略示例（Calico 做不到）

```yaml
# CiliumNetworkPolicy: 仅允许 GET /api/health，禁止 POST /admin
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "l7-http-policy"
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: api-server
  ingress:
    - toPorts:
      - ports:
          - port: "8080"
            protocol: TCP
        rules:
          http:
            - method: "GET"
              path: "/api/health"
```

### 10b.6 Hubble 可观测性

```bash
# Hubble CLI：实时查看集群流量
hubble observe --namespace default

# 输出示例：
# default/api-server-7d8f9 (ID:1234) -> default/mysql-0:3306 (ID:5678)
#   TCP Flags: SYN, ACK
#   HTTP/1.1 GET http://api-server.default/api/health
#   response: 200 OK, latency: 3.2ms

# 查看丢包原因
hubble observe --verdict DROPPED

# Hubble UI：Web 界面展示服务依赖图
# 无需注入 Sidecar，不修改任何 Pod
```

### 10b.7 课程选 Calico 的理由

1. **运维成熟度**：Calico 文档全面，排错工具链完善，社区案例丰富
2. **离线部署友好**：Calico 仅需简单 Operator 安装，Cilium 离线部署需额外的 eBPF 工具链
3. **CKA/CKS 考试**：Calico 是官方推荐的 CNI 之一，NetworkPolicy 考点全面
4. **兼容性**：Calico 内核要求 ≥ 3.10（几乎所有 Linux 发行版），Cilium 需 ≥ 5.4

> **建议**：先用 Calico 掌握 CNI 和 NetworkPolicy 核心概念，在模块 14（全链路综合实战）或模块 29（K8S 故障排查）中再做 Cilium 迁移对比实验。

### 面试要点

> **Q: eBPF 相比 iptables 有什么优势？为什么 Cilium 要用 eBPF 做数据面？**
>
> iptables 使用线性链表匹配规则，5000 条 Service 规则时每条数据包需遍历上千条链表项，延迟显著增加。eBPF 使用哈希表（hash table）O(1) 查找，不受规则数量影响。此外 eBPF 程序在内核中直通处理，绕过用户态开销，吞吐量更高。Cilium 还利用 eBPF 实现 L7 协议感知策略（HTTP/gRPC/Kafka），这是 iptables 无法做到的。

---

## 11. CoreDNS故障排查（CKA高频考点）

> CoreDNS是K8s集群DNS服务，CKA考试高频考点。
> 
> **常见问题**: DNS解析失败、超时、CoreDNS Pod异常

### 11.1 CoreDNS架构

```
┌─────────────────────────────────────────────────────────────┐
│                        Pod                                   │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  /etc/resolv.conf                                      │ │
│  │  nameserver 10.96.0.10  # CoreDNS Service IP          │ │
│  │  search default.svc.cluster.local svc.cluster.local   │ │
│  │         cluster.local                                  │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              CoreDNS Service (10.96.0.10)                    │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              CoreDNS Pod (kube-system)                       │
│  ┌─────────────────────┐  ┌─────────────────────┐          │
│  │    coredns-xxx       │  │    coredns-yyy       │          │
│  │    :53 UDP/TCP       │  │    :53 UDP/TCP       │          │
│  └─────────────────────┘  └─────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### 11.2 常见故障排查流程

**故障1: DNS解析超时**
```bash
# 1. 检查CoreDNS Pod状态
kubectl get pods -n kube-system -l k8s-app=kube-dns
# NAME                       READY   STATUS    RESTARTS   AGE
# coredns-5644d7b6d9-abcde   1/1     Running   0          10d

# 2. 检查CoreDNS Service
kubectl get svc -n kube-system kube-dns
# NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)
# kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP

# 3. 测试DNS解析
kubectl run dns-test --rm -it --image=busybox -- nslookup kubernetes.default
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# Name:      kubernetes.default
# Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local

# 4. 检查CoreDNS日志
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 5. 检查CoreDNS配置
kubectl get configmap coredns -n kube-system -o yaml
```

**故障2: CoreDNS Pod无法启动**
```bash
# 1. 查看Pod事件
kubectl describe pod -n kube-system -l k8s-app=kube-dns

# 2. 常见原因
# - 镜像拉取失败: 检查镜像是否存在
# - 资源不足: 检查节点资源
# - 网络不通: 检查CNI插件

# 3. 手动拉取镜像
crictl pull registry.k8s.io/coredns/coredns:v1.11.1

# 4. 重启CoreDNS
kubectl rollout restart deployment coredns -n kube-system
```

**故障3: DNS解析返回错误结果**
```bash
# 1. 检查CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml

# 2. 常见配置错误
# - forward配置错误: 上游DNS不可达
# - cache配置缺失: 无缓存导致性能问题
# - loop检测: 检测DNS循环解析

# 3. 正确配置示例
apiVersion: v1
kind: ConfigMap  # 配置映射
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {  # 监听所有域名的 53 端口
        errors  # 错误日志
        health {
            lameduck 5s  # 停止前 5 秒标记为不健康
        }
        ready  # 就绪检查
        kubernetes cluster.local in-addr.arpa ip6.arpa {  # K8s DNS 解析
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30  # DNS 缓存 TTL 30 秒
        }
        prometheus :9153  # Prometheus 监控端口
        forward . /etc/resolv.conf {  # 转发外部 DNS 查询
            max_concurrent 1000  # 最大并发查询数
        }
        cache 30  # 缓存 30 秒
        loop  # 检测 DNS 循环解析
        reload  # 热重载配置
        loadbalance  # 负载均衡
    }
```

### 11.3 性能调优

```yaml
# 增加CoreDNS副本数
apiVersion: apps/v1
kind: Deployment  # 部署控制器
metadata:
  name: coredns
  namespace: kube-system
spec:
  replicas: 3  # 副本数（默认2，根据集群规模调整）
  template:
    spec:
      containers:
        - name: coredns
          resources:
            requests:
              cpu: 100m  # CPU 请求 100 毫核
              memory: 70Mi  # 内存请求
            limits:
              cpu: 500m  # CPU 限制 500 毫核
              memory: 256Mi  # 内存限制
```

### 11.4 NodeLocal DNSCache（可选优化）

```bash
# NodeLocal DNSCache在每个节点运行DNS缓存
# 减少CoreDNS压力，降低DNS延迟

# 部署NodeLocal DNSCache
kubectl apply -f https://github.com/kubernetes/kubernetes/raw/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml

# 修改后Pod的/etc/resolv.conf指向本地缓存
# nameserver 169.254.20.10  # NodeLocal DNSCache
```

### 11.5 CKA考试常见命令

```bash
# 查看DNS解析
kubectl exec -it <pod> -- nslookup <service-name>

# 查看DNS解析（带命名空间）
kubectl exec -it <pod> -- nslookup <service-name>.<namespace>

# 测试外部DNS
kubectl exec -it <pod> -- nslookup google.com

# 查看CoreDNS配置
kubectl get configmap coredns -n kube-system -o yaml

# 编辑CoreDNS配置
kubectl edit configmap coredns -n kube-system

# 重启CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# 查看CoreDNS指标
kubectl port-forward -n kube-system svc/kube-dns 9153:9153
curl http://localhost:9153/metrics
```

---

## 12. 生产环境建议

### 12.1 网络模式选择

1. **BGP 模式**：适合物理机/VM 部署，性能最优，需要网络设备支持
2. **IPIP 模式**：适合大多数环境（默认），无需特殊网络配置
3. **VXLAN 模式**：适合云环境或 IPIP 被阻止的环境
4. **CrossSubnet**：混合环境最佳选择，同子网直连，跨子网封装

### 12.2 安全加固

1. **默认拒绝**：为所有命名空间创建默认拒绝 Ingress/Egress 策略
2. **DNS 放行**：在默认拒绝策略中放行 DNS 流量
3. **Namespace 隔离**：使用 namespaceSelector 实现命名空间级别隔离
4. **Egress 控制**：限制 Pod 的出站流量，只允许访问必要的地址
5. **日志审计**：启用 Calico 的流量日志（Flow Logs），记录所有被拒绝的连接

### 12.3 性能优化

1. **eBPF 数据面**：大规模集群（> 500 节点）建议使用 eBPF 模式
2. **Route Reflector**：节点数 > 100 时使用 Route Reflector 替代全互联
3. **IP Block 大小**：根据每个节点的 Pod 数量调整 blockSize（默认 /26 = 64 IP）
4. **MTU 调整**：使用 IPIP/VXLAN 时，建议将 MTU 调小 20-50 字节（如 1450）
5. **连接跟踪**：大规模集群考虑禁用 conntrack（使用 eBPF 模式）

### 12.4 运维管理

1. **监控**：通过 Prometheus 监控 Calico 指标（Felix metrics、BIRD metrics）
2. **告警**：对 BGP 会话断开、Felix 重启、IP 耗尽等设置告警
3. **升级**：Calico 升级前备份 CRD，先升级 CRD 再升级 DaemonSet
4. **容量规划**：监控 IP Pool 使用率，提前规划扩容
5. **文档**：记录网络拓扑、IP 分配规划、BGP AS 号等

---

## 13. 2026技术趋势 -- eBPF与Cilium

> 📌 **2026技术趋势** -- 本章节关注 2026 年云原生网络领域最重要的技术演进方向：eBPF 与 Cilium。

### 11.1 趋势概述

📌 **2026技术趋势**

eBPF（Extended Berkeley Packet Filter）正在成为云原生网络、安全与可观测性的**统一数据面**。在 KubeCon EU 2026 上，多个核心信号进一步确认了这一趋势：

- **Cilium 已成为 Kubernetes 网络插件的事实标准**：Google GKE、阿里云 ACK、AWS EKS 等主流托管 K8s 服务均已提供 Cilium 作为默认或推荐的网络方案。
- **kube-proxy 替代进入稳定期**：Cilium 的 `kubeProxyReplacement: strict` 模式已全面 GA，大规模生产验证（数万节点级别）完成。
- **可观测性原生集成**：Hubble + Tetragon 构成了从网络到运行时的完整可观测 + 安全栈，无需额外 Sidecar 或 DaemonSet。
- **服务网格融合**：Cilium Mesh（基于 Kmesh）实现了无 Sidecar 的服务网格，大幅降低了服务网格的复杂度和资源开销。
- **内核原生支持增强**：Linux 6.x 内核对 eBPF 的持续优化（如 `bpf_loop`、结构体直接访问等）使 eBPF 程序开发更加高效。

```
  📌 2026 云原生网络演进路线

  2020 ────── 2022 ────── 2024 ────── 2026
    |           |           |           |
  Calico     Cilium 1.x  Cilium 1.14  Cilium 1.17
  主导期     进入生产     全面成熟     统一数据面
    |           |           |           |
  iptables   eBPF 替代   kube-proxy   服务网格
  数据面     kube-proxy   替代 GA      无 Sidecar
    |           |           |           |
  Network   L7 策略      Hubble       Tetragon
  Policy    可用          GA           运行时安全
```

### 11.2 Calico vs Cilium 对比表

📌 **2026技术趋势** -- 以下对比基于 Calico v3.26 与 Cilium v1.17（2026年5月最新稳定版）。

| 维度 | Calico (当前课程) | Cilium (2026趋势) |
|------|-------------------|-------------------|
| **数据面** | iptables / IPVS / eBPF (可选) | eBPF (原生，默认启用) |
| **性能** | 中等（iptables 规则遍历开销） | 高（eBPF 绕过 iptables，吞吐提升 30-50%） |
| **网络策略** | NetworkPolicy (L3/L4) | CiliumNetworkPolicy (超集，支持 L7 HTTP/gRPC/Kafka) |
| **可观测性** | 需要额外部署 Prometheus + Grafana | Hubble 内置（零侵入，服务拓扑 + 流量追踪） |
| **运行时安全** | 无原生支持 | Tetragon（eBPF 运行时安全，进程级审计） |
| **kube-proxy** | 依赖 kube-proxy | 可完全替代（kubeProxyReplacement: strict） |
| **服务网格** | 无 | 原生支持（Cilium Mesh / Kmesh，无 Sidecar） |
| **学习曲线** | 低（配置简单，文档成熟） | 中（eBPF 概念 + CRD 较多） |
| **生产成熟度** | 高（多年生产验证，社区广泛） | 高（Google/阿里/字节等大规模使用） |
| **CNCF 状态** | Graduated | Graduated |
| **资源开销** | 低（Felix ~200MB 内存） | 中（Agent ~500MB，Hubble ~300MB） |
| **加密** | WireGuard (手动配置) | WireGuard / IPsec (透明加密，一键启用) |
| **多集群** | Calico Enterprise (付费) | Cluster Mesh (开源) |

**选择建议：**
- **现有集群**：保持 Calico，稳定优先。Calico 已完全满足生产需求。
- **新集群**：优先考虑 Cilium，面向未来。eBPF 是长期趋势。
- **大规模集群（> 1000 节点）**：强烈建议 Cilium，eBPF 性能优势显著。
- **需要 L7 策略 + 可观测性**：Cilium + Hubble 是最佳组合。

### 11.3 eBPF 技术原理

📌 **2026技术趋势**

#### 11.3.1 eBPF 是什么

eBPF（Extended Berkeley Packet Filter，扩展伯克利包过滤器）是一种在 Linux 内核中运行沙箱程序的技术。它允许开发者在**不修改内核源码、不加载内核模块**的情况下，安全地在内核空间执行自定义逻辑。eBPF 程序在内核中事件触发时运行，如网络数据包到达、系统调用发生、进程创建等。

类比理解：eBPF 就像是给 Linux 内核装了一个"插件系统"，你可以在内核的关键路径上"注入"自定义的处理逻辑，而不用担心崩溃整个系统（因为 eBPF 有严格的验证器）。

#### 11.3.2 工作机制

```
  📌 eBPF 程序生命周期

  用户空间                              内核空间
  ─────────                            ─────────

  1. 编写 eBPF 程序 (C/Go/Rust)
         │
         v
  2. 编译为 eBPF 字节码 (clang/llvm)
         │
         v
  3. 通过 bpf() 系统调用加载
         │
         ├──────────────────────────────> 4. 验证器 (Verifier)
         │                                    │
         │                                    ├── 类型检查
         │                                    ├── 安全检查（无无限循环）
         │                                    ├── 内存访问检查
         │                                    └── 指令数限制检查
         │                                    │
         │                                    v
         │                                5. JIT 编译为原生机器码
         │                                    │
         │                                    v
         │                                6. 挂载到内核钩子点
         │                                    │
         │                    ┌───────────────┼───────────────┐
         │                    │               │               │
         │                    v               v               v
         │               XDP (网卡)    TC (网卡队列)    kprobe/uprobe
         │               (最早拦截)    (L3/L4处理)    (系统调用/函数)
         │                    │               │               │
         │                    └───────────────┼───────────────┘
         │                                    │
         │                                    v
         │                              7. 事件触发时执行
         │                                    │
         │                    ┌───────────────┼───────────────┐
         │                    v               v               v
         │               放行/丢弃       修改包内容      记录/告警
         │               (网络决策)     (NAT/重定向)   (可观测/安全)
         │                                    │
         │                                    v
         │                              8. 通过 Maps 共享数据
         │                                    │
         │<───────────────────────────────────┘
         │
         v
  9. 用户空间读取 Maps 数据 (Hubble/监控)
```

#### 11.3.3 CO-RE（一次编译，到处运行）

CO-RE（Compile Once - Run Everywhere，一次编译到处运行）是 eBPF 生态的关键技术，解决了 eBPF 程序在不同内核版本间可移植性的问题。

```
  传统方式 (BCC):                    CO-RE 方式:
  ┌──────────────────┐              ┌──────────────────┐
  │ eBPF C 源码      │              │ eBPF C 源码      │
  └────────┬─────────┘              └────────┬─────────┘
           │                                 │
           v                                 v
  ┌──────────────────┐              ┌──────────────────┐
  │ 目标机器上编译    │              │ 预编译 + BTF 信息 │
  │ (需要内核头文件)  │              │ (一次编译)        │
  └────────┬─────────┘              └────────┬─────────┘
           │                                 │
           v                                 v
  ┌──────────────────┐              ┌──────────────────┐
  │ 绑定特定内核版本  │              │ 运行时 BTF 重定位 │
  └──────────────────┘              │ (自动适配)        │
                                    └────────┬─────────┘
                                             │
                                             v
                                    ┌──────────────────┐
                                    │ 任意内核版本运行  │
                                    └──────────────────┘
```

**关键概念：**
- **BTF（BPF Type Format）**：内核类型信息的描述格式，类似于 DWARF 调试信息，但专为 eBPF 设计
- **libbpf**：Cilium 团队开发的 eBPF 库，内置 CO-RE 支持
- **bpftool**：内核提供的 eBPF 工具，用于加载/查看/调试 eBPF 程序

### 11.4 Cilium 核心组件

📌 **2026技术趋势**

```
  📌 Cilium 架构全景图 (v1.17)

  +------------------------------------------------------------------+
  |                      Kubernetes Cluster                           |
  +------------------------------------------------------------------+
  |                                                                   |
  |  Control Plane (控制面)                                            |
  |  +-----------------------------------------------------------+   |
  |  |  Cilium Operator (Deployment, 全局 1-2 副本)                |   |
  |  |  - 管理 CiliumIdentity、CiliumEndpoint 等 CRD                |   |
  |  |  - 处理节点加入/离开                                         |   |
  |  +-----------------------------------------------------------+   |
  |                                                                   |
  |  Data Plane (数据面)                                               |
  |  +---------------------------+  +---------------------------+     |
  |  |      Node-1               |  |      Node-2               |     |
  |  |  +---------------------+  |  |  +---------------------+  |     |
  |  |  |  Cilium Agent (DS)  |  |  |  |  Cilium Agent (DS)  |  |     |
  |  |  |  - eBPF 程序管理    |  |  |  |  - eBPF 程序管理    |  |     |
  |  |  |  - 网络策略执行    |  |  |  |  - 网络策略执行    |  |     |
  |  |  |  - 服务负载均衡    |  |  |  |  - 服务负载均衡    |  |     |
  |  |  |  - 身份管理        |  |  |  |  - 身份管理        |  |     |
  |  |  +---------------------+  |  |  +---------------------+  |     |
  |  |  +---------------------+  |  |  +---------------------+  |     |
  |  |  |  Hubble Relay (DS)  |  |  |  |  Hubble Relay (DS)  |  |     |
  |  |  |  - 流量聚合         |  |  |  |  - 流量聚合         |  |     |
  |  |  |  - 拓扑构建         |  |  |  |  - 拓扑构建         |  |     |
  |  |  +---------------------+  |  |  +---------------------+  |     |
  |  |  +---------------------+  |  |  +---------------------+  |     |
  |  |  |  Tetragon Agent (DS) |  |  |  |  Tetragon Agent (DS) |  |     |
  |  |  |  - 运行时安全审计   |  |  |  |  - 运行时安全审计   |  |     |
  |  |  |  - 进程追踪         |  |  |  |  - 进程追踪         |  |     |
  |  |  +---------------------+  |  |  +---------------------+  |     |
  |  +---------------------------+  +---------------------------+     |
  |                                                                   |
  |  Observability (可观测性)                                          |
  |  +-----------------------------------------------------------+   |
  |  |  Hubble Server (Deployment)                                  |   |
  |  |  - Hubble UI (服务拓扑可视化)                                |   |
  |  |  - Hubble CLI (命令行流量查询)                               |   |
  |  |  - Hubble API (REST/gRPC 接口)                               |   |
  |  +-----------------------------------------------------------+   |
  |                                                                   |
  |  eBPF Programs (内核空间)                                         |
  |  +-----------------------------------------------------------+   |
  |  |  XDP:   网卡级别数据包过滤 (DDoS 防护、L3/L4 策略)          |   |
  |  |  TC:    流量控制 (NAT、路由、策略执行)                       |   |
  |  |  cgroup: Socket 级别操作 (服务负载均衡)                     |   |
  |  |  trace: 系统调用追踪 (Tetragon 运行时安全)                  |   |
  |  |  Maps:  内核与用户空间数据共享 (连接跟踪、指标)              |   |
  |  +-----------------------------------------------------------+   |
  +------------------------------------------------------------------+
```

**核心组件说明：**

| 组件 | 类型 | 功能 | 资源需求 |
|------|------|------|---------|
| **Cilium Agent** | DaemonSet | eBPF 程序管理、网络策略执行、服务负载均衡 | 500MB 内存, 0.5 CPU |
| **Cilium Operator** | Deployment | CRD 管理、节点生命周期管理 | 256MB 内存, 0.1 CPU |
| **Hubble Relay** | DaemonSet | 聚合各节点流量数据，提供统一查询接口 | 300MB 内存, 0.3 CPU |
| **Hubble Server** | Deployment | Hubble UI/API 服务 | 256MB 内存, 0.1 CPU |
| **Tetragon Agent** | DaemonSet | eBPF 运行时安全审计（进程/文件/网络事件） | 400MB 内存, 0.3 CPU |
| **Cilium CLI** | 二进制 | 命令行管理工具（安装、诊断、配置） | 无（客户端工具） |

### 11.5 Cilium 轻量部署指南

📌 **2026技术趋势** -- 以下部署指南适配离线环境（Harbor 192.168.1.61），资源需求适配 2C4G 节点。

#### 11.5.1 镜像清单

| 镜像 | 用途 | 必需 | 大小 |
|------|------|------|------|
| `quay.io/cilium/cilium:v1.17.0` | Cilium Agent | 是 | ~250MB |
| `quay.io/cilium/operator-generic:v1.17.0` | Cilium Operator | 是 | ~80MB |
| `quay.io/cilium/hubble-relay:v1.17.0` | Hubble Relay | 推荐 | ~60MB |
| `quay.io/cilium/hubble-ui-backend:v1.17.0` | Hubble UI 后端 | 推荐 | ~30MB |
| `quay.io/cilium/hubble-ui:v1.17.0` | Hubble UI 前端 | 推荐 | ~20MB |
| `quay.io/cilium/cilium-envoy:v1.17.0` | Envoy 代理（L7 策略） | 可选 | ~150MB |
| `quay.io/cilium/tetragon:v1.2.0` | Tetragon 运行时安全 | 可选 | ~120MB |

#### 11.5.2 离线镜像同步

```bash
# ========== 在美国服务器（有外网）上执行 ==========
ssh us-server

HARBOR_ADDR="192.168.1.61"
HARBOR_USER="admin"
HARBOR_PASS="Harbor12345"
CILIUM_VERSION="v1.17.0"

# 登录 Harbor
echo "${HARBOR_PASS}" | docker login ${HARBOR_ADDR} -u "${HARBOR_USER}" --password-stdin

# Cilium 镜像列表
IMAGES=(
    "quay.io/cilium/cilium:${CILIUM_VERSION}"
    "quay.io/cilium/operator-generic:${CILIUM_VERSION}"
    "quay.io/cilium/hubble-relay:${CILIUM_VERSION}"
    "quay.io/cilium/hubble-ui-backend:${CILIUM_VERSION}"
    "quay.io/cilium/hubble-ui:${CILIUM_VERSION}"
    "quay.io/cilium/cilium-envoy:${CILIUM_VERSION}"
)

# 拉取、打标签、推送
for img in "${IMAGES[@]}"; do
    echo "=== 处理: ${img} ==="
    docker pull "${img}" || { echo "警告: 拉取失败 ${img}"; continue; }
    no_prefix="${img#*/}"
    target="${HARBOR_ADDR}/${no_prefix}"
    docker tag "${img}" "${target}"
    docker push "${target}"
    echo "=== 完成: ${img} -> ${target} ==="
done

# ========== 传输 Helm Chart 到 Master-1 ==========
# 下载 Cilium Helm Chart
helm repo add cilium https://helm.cilium.io/
helm pull cilium/cilium --version 1.17.0
scp cilium-1.17.0.tgz root@192.168.1.51:/root/
```

#### 11.5.3 Helm 离线安装

```bash
# ========== 在 Master-1 上执行 ==========

# 1. 确认内核版本 (eBPF 要求 >= 5.4, 推荐 >= 5.10)
uname -r
# 预期: 5.x 或 6.x

# 2. 确认 BPF 文件系统已挂载
mount | grep bpf
# 如果未挂载:
mount bpffs /sys/fs/bpf -t bpf

# 3. 创建 Cilium 命名空间
kubectl create namespace cilium-system

# 4. 使用 Helm 离线安装 Cilium
helm install cilium /root/cilium-1.17.0.tgz \
    --namespace cilium-system \
    --set image.repository=192.168.1.61/cilium/cilium \
    --set image.tag=v1.17.0 \
    --set operator.image.repository=192.168.1.61/cilium/operator-generic \
    --set operator.image.tag=v1.17.0 \
    --set hubble.relay.image.repository=192.168.1.61/cilium/hubble-relay \
    --set hubble.relay.image.tag=v1.17.0 \
    --set hubble.ui.backend.image.repository=192.168.1.61/cilium/hubble-ui-backend \
    --set hubble.ui.frontend.image.repository=192.168.1.61/cilium/hubble-ui \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set kubeProxyReplacement=strict \
    --set k8sServiceHost=192.168.1.51 \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes \
    --set tunnel=vxlan \
    --set autoDirectNodeRoutes=true \
    --set routingMode=tunnel \
    --set bandwidthManager.enabled=true \
    --set resources.requests.cpu=250m \
    --set resources.requests.memory=256Mi \
    --set resources.limits.cpu=500m \
    --set resources.limits.memory=512Mi \
    --set operator.resources.requests.cpu=50m \
    --set operator.resources.requests.memory=128Mi \
    --set operator.resources.limits.cpu=200m \
    --set operator.resources.limits.memory=256Mi

# 5. 删除 kube-proxy (strict 模式下必须)
kubectl delete ds kube-proxy -n kube-system
# 注意: 删除后所有节点的 iptables 规则将被 Cilium eBPF 接管

# 6. 清理残留的 iptables 规则 (每个节点执行)
iptables -F KUBE-FORWARD
iptables -F KUBE-NODE-PORTS
iptables -F KUBE-PROXY-CANARY
```

#### 11.5.4 轻量化资源配置（适配 2C4G 节点）

```yaml
# cilium-values-lightweight.yaml
# 用途: 2C4G 节点的轻量化 Cilium 配置
# 使用方式: helm install cilium /root/cilium-1.17.0.tgz -f cilium-values-lightweight.yaml -n cilium-system

image:
  repository: 192.168.1.61/cilium/cilium
  tag: v1.17.0
  useDigest: false

operator:
  image:
    repository: 192.168.1.61/cilium/operator-generic
    tag: v1.17.0
    useDigest: false
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

resources:
  requests:
    cpu: 100m
    memory: 200Mi
  limits:
    cpu: 500m
    memory: 512Mi

# 轻量化: 禁用 L7 代理以节省资源
l7Proxy: false

# 轻量化: 减少 eBPF Map 大小
bpf:
  mapDynamicSizeRatio: 0.0025

# 启用 Hubble (轻量模式)
hubble:
  enabled: true
  relay:
    enabled: true
    image:
      repository: 192.168.1.61/cilium/hubble-relay
      tag: v1.17.0
      useDigest: false
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi
  ui:
    enabled: true
    backend:
      image:
        repository: 192.168.1.61/cilium/hubble-ui-backend
        useDigest: false
    frontend:
      image:
        repository: 192.168.1.61/cilium/hubble-ui
        useDigest: false

# kube-proxy 完全替代
kubeProxyReplacement: strict

# 网络配置
ipam:
  mode: kubernetes
tunnel: vxlan
routingMode: tunnel
autoDirectNodeRoutes: true

# 禁用不必要功能 (节省资源)
encryption:
  enabled: false
prometheus:
  enabled: false
operator:
  prometheus:
    enabled: false
```

#### 11.5.5 验证安装

```bash
# 检查 Cilium Pod 状态
kubectl get pods -n cilium-system -o wide
# 预期: 所有 Pod 均为 Running

# 检查 Cilium 状态
kubectl exec -n cilium-system ds/cilium -- cilium status
# 预期输出:
#   KVStore:                 Ok
#   Kubernetes:              Ok   [1/1] Pod CIDRs allocated
#   Host Routing:            Legacy
#   Cilium:                  Ok
#   NodeMonitor:             Listening for events on 4 CPUs with 64x4096 of shared memory
#   Cilium health daemon:    Ok
#   IPAM:                    IPv4: 2/256 allocated from 10.244.1.0/24

# 检查 kube-proxy 替代状态
kubectl exec -n cilium-system ds/cilium -- cilium status | grep "kube-proxy"
# 预期: kube-proxy replacement: strict

# 检查 Hubble
kubectl exec -n cilium-system ds/cilium -- cilium hubble port-forward &
hubble observe --since 1m
# 预期: 实时流量日志输出

# 检查 Pod 间网络连通性
kubectl run test-cilium --image=192.168.1.61/k8s/busybox:latest --rm -it --restart=Never -- \
    ping -c 3 kubernetes.default
# 预期: 3 packets transmitted, 3 received
```

### 11.6 Hubble 可观测性

📌 **2026技术趋势** -- Hubble 是 Cilium 内置的可观测性平台，提供零侵入的网络流量可视化。

#### 11.6.1 架构

```
  📌 Hubble 可观测性架构

  +------------------------------------------------------------------+
  |  Node-1                           Node-2                         |
  |  +-------------+                  +-------------+                |
  |  | Cilium Agent|                  | Cilium Agent|                |
  |  | +---------+ |                  | +---------+ |                |
  |  | | eBPF    | |                  | | eBPF    | |                |
  |  | | 程序    | |                  | | 程序    | |                |
  |  | +----+----+ |                  | +----+----+ |                |
  |  |      |      |                  |      |      |                |
  |  |      v      |                  |      v      |                |
  |  | +---------+ |   gRPC/TCP      | +---------+ |                |
  |  | | Hubble  | |<================>| | Hubble  | |                |
  |  | | Observer| |   流量数据       | | Observer| |                |
  |  | +---------+ |                  | +---------+ |                |
  |  +------+------+                  +------+------+                |
  |         |                                  |                      |
  +---------|----------------------------------|----------------------+
            |                                  |
            v                                  v
  +------------------------------------------------------------------+
  |                    Hubble Relay (聚合层)                          |
  |  +-----------------------------------------------------------+   |
  |  |  接收所有节点的 Hubble Observer 数据，提供统一查询接口       |   |
  |  +-----------------------------------------------------------+   |
  +----------------------------------+----------------------------+
                                     |
                                     v
  +------------------------------------------------------------------+
  |                      Hubble Server                                |
  |  +------------------+  +------------------+  +-----------------+  |
  |  |   Hubble UI      |  |   Hubble CLI     |  |  Hubble API     |  |
  |  | (服务拓扑可视化)  |  | (命令行查询)     |  | (REST/gRPC)     |  |
  |  +------------------+  +------------------+  +-----------------+  |
  +------------------------------------------------------------------+
            |                      |                    |
            v                      v                    v
  +------------------+  +------------------+  +-----------------+
  |  Grafana 仪表盘  |  | Prometheus 指标  |  | OTel Trace 导出 |
  +------------------+  +------------------+  +-----------------+
```

#### 11.6.2 服务拓扑自动生成

```bash
# 启用 Hubble 端口转发
kubectl port-forward -n cilium-system svc/hubble-ui 8080:80

# 访问 Hubble UI
# 浏览器打开 http://<master-ip>:8080
# Hubble UI 自动生成服务拓扑图:
#
#   +--------+    HTTP/80    +--------+
#   | frontend|=============>| backend|
#   +--------+              +--------+
#       |                        |
#       | DNS/UDP:53             | TCP/5432
#       v                        v
#   +--------+              +--------+
#   | CoreDNS |              |  PostgreSQL|
#   +--------+              +--------+

# 使用 Hubble CLI 查看服务间流量
hubble observe --since 5m --namespace default
# 预期输出:
#   May 24 10:00:01.000: default/frontend-7d4f5b (id:12345) -> default/backend-8a9c3d (id:67890)
#     to-endpoint: 67890, to-id: 67890, ifindex: 0, to-labels: app=backend
#     verdict: forwarded, ethernet-src: aa:bb:cc:dd:ee:ff, ethernet-dst: 11:22:33:44:55:66
#     IP: 10.244.1.5 -> 10.244.2.3, TTL: 64, PacketID: 12345, TCP Flags: ACK
#     L4: TCP, Ports: 45678 -> 80

# 查看特定 Pod 的流量
hubble observe --pod-name nginx-7d4f5b --namespace default --since 1m

# 查看被网络策略拒绝的流量
hubble observe --verdict dropped --since 10m
```

#### 11.6.3 与 Prometheus/Grafana 集成

```bash
# 启用 Cilium Prometheus 指标
helm upgrade cilium /root/cilium-1.17.0.tgz \
    --namespace cilium-system \
    --reuse-values \
    --set prometheus.enabled=true \
    --set operator.prometheus.enabled=true \
    --set hubble.metrics.enabled="["dns:query;ignoreAAAA","drop","flow","icmp","tcp","http"]"

# Prometheus 抓取配置 (添加到 prometheus.yml)
cat >> /etc/prometheus/prometheus.yml << 'EOF'
  - job_name: 'cilium'
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
            - cilium-system
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        regex: cilium-metrics
        action: keep
EOF

# Grafana Dashboard 导入
# 推荐 Dashboard ID:
#   - 12878: Cilium Dashboard (官方)
#   - 18622: Hubble Metrics Dashboard
#   - 15475: Cilium Operator Dashboard
```

#### 11.6.4 与 OpenTelemetry 集成

```bash
# 启用 Hubble OTel 导出
helm upgrade cilium /root/cilium-1.17.0.tgz \
    --namespace cilium-system \
    --reuse-values \
    --set hubble.export.otlp.enabled=true \
    --set hubble.export.otlp.endpoint="otel-collector.observability.svc:4317"

# Hubble 流量数据将自动导出为 OTel Trace 格式
# 可在 Jaeger/Tempo 中查看网络请求的完整调用链
```

### 11.7 Tetragon 运行时安全

📌 **2026技术趋势** -- Tetragon 是 Cilium 生态的 eBPF 运行时安全引擎，提供内核级别的进程、文件、网络事件审计。

#### 11.7.1 架构

```
  📌 Tetragon 运行时安全架构

  +------------------------------------------------------------------+
  |                        内核空间                                   |
  |  +-----------------------------------------------------------+   |
  |  |  Tetragon eBPF 程序                                        |   |
  |  |  +-------------+  +-------------+  +-------------+        |   |
  |  |  | tracepoint/  |  | tracepoint/  |  | kprobe/     |        |   |
  |  |  | sched/       |  | syscalls/   |  | security/   |        |   |
  |  |  | process_exec |  | sys_enter   |  | bprm_check  |        |   |
  |  |  +------+------+  +------+------+  +------+------+        |   |
  |  |         |                 |                 |                |   |
  |  |         v                 v                 v                |   |
  |  |  +------------------------------------------------------+  |   |
  |  |  |  Tetragon Maps (Perf Ring Buffer + BPF Ring Buffer)   |  |   |
  |  |  |  - 进程事件 (exec/exit/fork)                           |  |   |
  |  |  |  - 文件事件 (open/read/write)                          |  |   |
  |  |  |  - 网络事件 (connect/accept/bind)                      |  |   |
  |  |  |  - 安全事件 (capabilities/mount)                       |  |   |
  |  |  +------------------------------------------------------+  |   |
  |  +-----------------------------------------------------------+   |
  +------------------------------------------------------------------+
            |
            | Perf Event / Ring Buffer
            v
  +------------------------------------------------------------------+
  |                        用户空间                                   |
  |  +-----------------------------------------------------------+   |
  |  |  Tetragon Agent (DaemonSet)                                |   |
  |  |  - 读取内核事件                                             |   |
  |  |  - 匹配 TracingPolicy 规则                                  |   |
  |  |  - 生成告警/日志                                           |   |
  |  +-----------------------------------------------------------+   |
  |         |                                                       |
  |         +---------> JSON 日志 (stdout)                          |
  |         +---------> gRPC 导出 (告警平台)                        |
  |         +---------> Prometheus 指标                             |
  +------------------------------------------------------------------+
```

#### 11.7.2 安全策略示例

```yaml
# 监控敏感文件访问
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: monitor-sensitive-files
spec:
  kprobes:
    - call: "vfs_read"
      syscall: false
      args:
        - index: 0
          type: "file"
        - index: 2
          type: "size_t"
      selectors:
        - matchNamespaces:
            - namespace: RuntimeDefault
          matchArgs:
            - index: 0
              operator: "Prefix"
              values:
                - "/etc/shadow"
                - "/etc/passwd"
                - "/etc/kubernetes/admin.conf"
                - "/var/run/secrets/kubernetes.io/serviceaccount"
          matchActions:
            - action: Post
              outputActions:
                - action: Print
```

```yaml
# 监控容器内进程执行 (检测异常进程)
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: monitor-process-exec
spec:
  tracepoints:
    - subsystem: "sched"
      event: "sched_process_exec"
      args:
        - index: 0
          type: "pid_t"    # parent PID
        - index: 2
          type: "file"     # executable file
      selectors:
        - matchNamespaces:
            - namespace: RuntimeDefault
          matchArgs:
            - index: 2
              operator: "Prefix"
              values:
                - "/bin/sh"
                - "/usr/bin/curl"
                - "/usr/bin/wget"
                - "/bin/bash"
          matchActions:
            - action: Post
              outputActions:
                - action: Print
```

```yaml
# 监控可疑网络连接 (反向 Shell 检测)
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: detect-reverse-shell
spec:
  kprobes:
    - call: "tcp_connect"
      syscall: true
      args:
        - index: 1
          type: "sockaddr"
      selectors:
        - matchNamespaces:
            - namespace: RuntimeDefault
          matchActions:
            - action: Post
              outputActions:
                - action: Print
```

#### 11.7.3 Tetragon vs Falco 对比

| 维度 | Tetragon | Falco |
|------|----------|-------|
| **技术** | eBPF (原生) | eBPF (现代驱动) / Legacy (内核模块) |
| **性能开销** | 极低 (内核原生) | 中等 (用户空间处理) |
| **事件丰富度** | 高 (内核任意 tracepoint/kprobe) | 中 (预定义规则集) |
| **策略语言** | TracingPolicy CRD (K8s 原生) | Falco Rules (YAML) |
| **告警输出** | gRPC/JSON/Prometheus | gRPC/JSON/Syslog/Webhook |
| **K8s 集成** | 深度集成 (Cilium 生态) | 需要额外部署 |
| **容器感知** | 原生 (自动关联 Pod/Service) | 支持 (通过标签) |
| **社区** | Cilium/CNCF | Sysdig/CNCF |
| **推荐场景** | 已有 Cilium 的集群 | 独立安全审计需求 |

#### 11.7.4 告警集成

```bash
# Tetragon 离线部署
helm repo add tetragon https://helm.cilium.io/
helm pull tetragon/tetragon --version 1.2.0
scp tetragon-1.2.0.tgz root@192.168.1.51:/root/

# 离线镜像同步 (在美国服务器执行)
IMAGES=(
    "quay.io/cilium/tetragon:v1.2.0"
    "quay.io/cilium/tetragon-operator:v1.2.0"
)

# Helm 安装 Tetragon
helm install tetragon /root/tetragon-1.2.0.tgz \
    --namespace cilium-system \
    --set image.repository=192.168.1.61/cilium/tetragon \
    --set image.tag=v1.2.0 \
    --set operator.image.repository=192.168.1.61/cilium/tetragon-operator \
    --set operator.image.tag=v1.2.0 \
    --set export.allowlist="\"process_exec,process_exit,sensitive_file_access\""

# 查看 Tetragon 事件
kubectl logs -n cilium-system -l app.kubernetes.io/name=tetragon -f

# 与告警平台集成 (JSON 输出 -> Logstash/Fluentd -> Elasticsearch)
# Tetragon 默认以 JSON 格式输出事件到 stdout，可直接被日志采集器采集
```

### 11.8 迁移路径: Calico -> Cilium

📌 **2026技术趋势**

#### 11.8.1 迁移步骤

```
  📌 Calico -> Cilium 迁移流程

  阶段 1: 评估 (1-2 周)              阶段 2: 准备 (1 周)
  ┌──────────────────────┐          ┌──────────────────────┐
  │ - 评估集群规模        │          │ - 备份 Calico 配置   │
  │ - 检查内核版本 >=5.4  │          │ - 备份 NetworkPolicy │
  │ - 评估 NetworkPolicy  │          │ - 准备 Cilium 镜像   │
  │   兼容性              │          │ - 准备回滚方案       │
  │ - 资源评估            │          │ - 通知相关团队       │
  └──────────┬───────────┘          └──────────┬───────────┘
             │                                 │
             v                                 v
  阶段 3: 灰度 (2-4 周)              阶段 4: 全量 (1-2 周)
  ┌──────────────────────┐          ┌──────────────────────┐
  │ - 新节点用 Cilium     │          │ - 所有节点迁移完成   │
  │ - 旧节点保持 Calico   │          │ - 验证网络连通性     │
  │ - 双 CNI 并存运行     │          │ - 验证 NetworkPolicy │
  │ - 逐步迁移工作负载    │          │ - 清理 Calico 残留   │
  │ - 性能对比测试        │          │ - 更新文档和监控     │
  └──────────┬───────────┘          └──────────┬───────────┘
             │                                 │
             v                                 v
  阶段 5: 稳定观察 (2-4 周)
  ┌──────────────────────┐
  │ - 监控网络性能指标    │
  │ - 监控 eBPF 程序状态  │
  │ - 收集问题和反馈      │
  │ - 优化配置            │
  └──────────────────────┘
```

```bash
# ========== 迁移步骤详解 ==========

# 步骤 1: 备份现有 Calico 配置
kubectl get ippools -o yaml > calico-backup-ippools.yaml
kubectl get networkpolicy --all-namespaces -o yaml > calico-backup-networkpolicies.yaml
kubectl get bgpconfig -o yaml > calico-backup-bgp.yaml
kubectl get felixconfiguration -o yaml > calico-backup-felix.yaml

# 步骤 2: 安装 Cilium (与 Calico 并存)
# 注意: Cilium 使用不同的 Pod CIDR，避免 IP 冲突
helm install cilium /root/cilium-1.17.0.tgz \
    --namespace cilium-system \
    --set kubeProxyReplacement=false \
    --set ipam.mode=kubernetes

# 步骤 3: 逐节点迁移
# 对于每个节点:
#   a. 驱逐节点上的 Pod: kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
#   b. 在节点上删除 Calico: kubectl label node <node> cilium.io/no-schedule-
#   c. 确认 Cilium Agent 在节点上运行
#   d. 恢复节点: kubectl uncordon <node>

# 步骤 4: 验证迁移
kubectl get pods -n cilium-system -o wide
kubectl exec -n cilium-system ds/cilium -- cilium status
kubectl run test-migration --image=192.168.1.61/k8s/busybox:latest --rm -it --restart=Never -- \
    ping -c 3 kubernetes.default

# 步骤 5: 清理 Calico
kubectl delete -f calico.yaml
kubectl delete crd ippools.crd.projectcalico.org
kubectl delete crd bgpconfigurations.crd.projectcalico.org
kubectl delete crd felixconfigurations.crd.projectcalico.org
kubectl delete crd networkpolicies.crd.projectcalico.org
kubectl delete crd hostendpoints.crd.projectcalico.org
kubectl delete crd blockaffinities.crd.projectcalico.org
kubectl delete crd ipamblocks.crd.projectcalico.org
kubectl delete crd ipamhandles.crd.projectcalico.org
kubectl delete crd clusterinformations.crd.projectcalico.org

# 步骤 6: 启用 kube-proxy 替代
helm upgrade cilium /root/cilium-1.17.0.tgz \
    --namespace cilium-system \
    --reuse-values \
    --set kubeProxyReplacement=strict
kubectl delete ds kube-proxy -n kube-system
```

#### 11.8.2 风险评估

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| NetworkPolicy 不兼容 | 中 | Cilium 兼容 K8s NetworkPolicy；CiliumNetworkPolicy 需要单独迁移 |
| Pod IP 变更导致连接中断 | 高 | 迁移期间逐节点操作，确保 Pod 重建后重新注册 |
| 内核版本不满足要求 | 中 | 提前检查所有节点内核版本，必要时升级内核 |
| eBPF 程序加载失败 | 低 | 检查 BPF 文件系统挂载、内核配置 |
| 回滚复杂度 | 中 | 保留 Calico 配置备份，准备快速回滚脚本 |
| 服务中断 | 高 | 选择维护窗口，逐节点迁移，确保 Pod 优雅终止 |

#### 11.8.3 回滚方案

```bash
# 紧急回滚步骤 (在 30 分钟内完成)

# 1. 重新部署 Calico
kubectl apply -f calico.yaml

# 2. 删除 Cilium
helm uninstall cilium -n cilium-system
kubectl delete namespace cilium-system

# 3. 恢复 kube-proxy
# 如果 kube-proxy 的 DaemonSet 被删除，需要重新创建
# 从备份恢复或从 kubeadm 配置重新生成

# 4. 验证回滚
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl run test-rollback --image=192.168.1.61/k8s/busybox:latest --rm -it --restart=Never -- \
    ping -c 3 kubernetes.default
```

#### 11.8.4 最终建议

| 场景 | 建议 | 原因 |
|------|------|------|
| **现有生产集群** | 保持 Calico | 稳定优先，Calico 已完全满足需求 |
| **新集群** | 使用 Cilium | 面向未来，eBPF 是长期趋势 |
| **大规模集群 (>1000 节点)** | 迁移到 Cilium | eBPF 性能优势显著 |
| **需要 L7 策略** | 迁移到 Cilium | Calico 不原生支持 L7 |
| **需要运行时安全** | 迁移到 Cilium + Tetragon | Calico 无原生运行时安全能力 |
| **BGP 网络集成** | 保持 Calico | Calico BGP 支持更成熟 |

### 11.9 面试题补充

📌 **2026技术趋势**

### Q13: 什么是 eBPF？为什么它被认为是云原生网络的未来？ [难度: 中]

**答案：** eBPF（Extended Berkeley Packet Filter）是一种在 Linux 内核中安全运行沙箱程序的技术。它允许开发者在不修改内核源码、不加载内核模块的情况下，在内核空间执行自定义逻辑。eBPF 被认为是云原生网络未来的原因：第一，性能优势：eBPF 程序在内核空间直接处理数据包，绕过了 iptables 和 conntrack，延迟更低、吞吐更高（相比 iptables 提升 30-50%）。第二，可编程性：eBPF 提供了内核的可编程接口，网络策略、负载均衡、加密等功能都可以通过 eBPF 程序实现，无需修改内核。第三，统一数据面：eBPF 不仅用于网络，还可用于安全（Tetragon 运行时安全）、可观测性（Hubble 网络流量追踪）等多个领域，实现了真正的统一数据面。第四，安全性：eBPF 有严格的验证器（Verifier），确保程序不会导致内核崩溃或安全问题。第五，CO-RE 技术：一次编译到处运行，解决了 eBPF 程序在不同内核版本间的可移植性问题。Cilium 是 eBPF 在 Kubernetes 网络领域最成功的实践，已被 Google、阿里云等大规模生产验证。

### Q14: Cilium 如何替代 kube-proxy？有什么好处和风险？ [难度: 高]

**答案：** Cilium 通过 eBPF 程序替代 kube-proxy 的核心功能（Service 负载均衡和 NAT）。kube-proxy 基于 iptables/IPVS 实现 Service 的 ClusterIP、NodePort 和 LoadBalancer 的流量转发。在大规模集群中，kube-proxy 的 iptables 规则数量可达数万条，导致显著的性能下降。Cilium 的替代方式：使用 eBPF 程序挂载到 cgroup 和 tc（Traffic Control）钩子点，在内核空间直接实现 Service 的负载均衡和 NAT，绕过了 iptables。Cilium 支持三种 kube-proxy 替代模式：disabled（不替代，与 kube-proxy 共存）、partial（替代部分功能，如 ClusterIP）、strict（完全替代，删除 kube-proxy）。好处：第一，性能提升：eBPF 负载均衡的延迟比 iptables 低一个数量级；第二，规则数量无关：eBPF 使用 Hash Map 查找 Service 后端，时间复杂度 O(1)，与 Service/Endpoint 数量无关；第三，支持高级功能：如基于拓扑感知的路由、直接服务器返回（DSR）等。风险：第一，兼容性：需要内核版本 >= 5.4（推荐 >= 5.10）；第二，排错复杂度：eBPF 程序的排错比 iptables 更复杂，需要使用 `bpftool`、`cilium-dbg` 等专用工具；第三，生态依赖：某些依赖 kube-proxy iptables 规则的第三方工具可能不兼容。在生产环境中，建议先在测试集群验证 kube-proxy 替代功能，确认所有 Service 正常工作后再在生产集群启用。

### Q15: Hubble 和 Tetragon 分别解决什么问题？它们与传统的监控方案有什么区别？ [难度: 高]

**答案：** Hubble 和 Tetragon 是 Cilium 生态中分别解决网络可观测性和运行时安全问题的两个核心组件。Hubble 解决的是**网络可观测性**问题：它基于 Cilium 的 eBPF 数据面，自动采集所有 Pod 间的网络流量数据（包括 DNS 查询、HTTP 请求、TCP 连接等），提供服务拓扑图、流量追踪、策略审计等功能。与传统方案（如 Prometheus + Grafana）的区别：Hubble 的数据来自 eBPF 内核级采集，零侵入（不需要 Sidecar）、零性能损耗（数据面已有的事件），且可以关联到 Pod/Service/Identity 级别，粒度更细。传统方案通常基于 iptables 日志或 NetFlow，粒度粗且有性能损耗。Tetragon 解决的是**运行时安全**问题：它使用 eBPF 在内核级别监控进程执行、文件访问、网络连接等安全事件，支持自定义安全策略（TracingPolicy CRD）。与传统方案（如 Falco）的区别：Tetragon 原生使用 eBPF（Falco 早期版本使用内核模块），性能开销更低；Tetragon 与 Cilium 深度集成，可以自动关联 Pod/Service 身份信息；Tetragon 的策略语言（TracingPolicy）是 K8s 原生 CRD，可以直接通过 kubectl 管理。总结：Hubble 是"网络望远镜"（看到所有网络流量），Tetragon 是"安全摄像头"（监控所有系统行为），两者结合实现了从网络到安全的全栈可观测性。

---

> **下一模块：** 06-Prometheus 与 Grafana 监控 -- 指标采集、告警规则与可视化仪表盘