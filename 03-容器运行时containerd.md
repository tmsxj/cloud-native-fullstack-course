# 模块03：容器运行时 containerd

---

## 1. 概述与架构图

### 1.1 课程目标

本模块深入讲解 containerd 容器运行时的原理、配置与运维。containerd 是 Kubernetes 默认的容器运行时（CRI，容器运行时接口），替代了早期的 Docker Engine。完成本模块后，你将掌握 containerd 的完整配置方法，包括 CRI 插件、Harbor 私有仓库对接、sandbox_image 配置以及 crictl/ctr 命令行工具的使用。

### 1.2 容器运行时架构图

```
  +------------------------------------------------------------------+
  |                        Kubernetes Cluster                        |
  +------------------------------------------------------------------+
       |                    |                    |
  +----+----+         +-----+-----+         +----+----+
  | kubelet |         | kubelet  |         | kubelet |
  +----+----+         +-----+-----+         +----+----+
       |                    |                    |
       +--------------------+--------------------+
                            |
                    +-------+-------+
                    |  CRI (gRPC)   |
                    +-------+-------+
                            |
              +-------------+-------------+
              |                           |
     +--------+--------+        +--------+--------+
     |    containerd    |        |    containerd    |
     |   (Master Node)  |        |   (Worker Node)  |
     +--------+---------+        +--------+---------+
              |                           |
     +--------+---------+        +--------+---------+
     |  CRI Plugin      |        |  CRI Plugin      |
     |  (containerd v2) |        |  (containerd v2) |
     +--------+---------+        +--------+---------+
              |                           |
     +--------+---------+        +--------+---------+
     |  Image Service   |        |  Image Service   |
     |  (镜像管理)       |        |  (镜像管理)       |
     +--------+---------+        +--------+---------+
              |                           |
     +--------+---------+        +--------+---------+
     | Container Service|        | Container Service|
     | (容器生命周期)     |        | (容器生命周期)     |
     +--------+---------+        +--------+---------+
              |                           |
     +--------+---------+        +--------+---------+
     |   container-shim |        |   container-shim |
     |   (进程管理)       |        |   (进程管理)       |
     +--------+---------+        +--------+---------+
              |                           |
     +--------+---------+        +--------+---------+
     |    runc          |        |    runc          |
     | (OCI Runtime)    |        | (OCI Runtime)    |
     +------------------+        +------------------+
```

### 1.3 CRI 协议架构

```
  kubelet                                    containerd (CRI Plugin)
    |                                              |
    |--- RuntimeService.RunPodSandbox ------------->|
    |    (创建 Pause 容器/网络命名空间)               |
    |<-- 返回 PodSandbox ID -----------------------|
    |                                              |
    |--- ImageService.PullImage ------------------->|
    |    (拉取容器镜像)                              |
    |<-- 返回镜像引用 -----------------------------|
    |                                              |
    |--- RuntimeService.CreateContainer ------------>|
    |    (创建业务容器)                              |
    |<-- 返回 Container ID ------------------------|
    |                                              |
    |--- RuntimeService.StartContainer ------------>|
    |    (启动业务容器)                              |
    |<-- 返回成功 ----------------------------------|
    |                                              |
    |--- RuntimeService.StopPodSandbox ------------>|
    |    (停止并删除 Pod)                            |
    |<-- 返回成功 ----------------------------------|
```

### 1.4 容器运行时对比

```
  +------------------+-------------------+-------------------+------------------+
  |      特性         |     containerd    |      Docker       |     CRI-O        |
  +------------------+-------------------+-------------------+------------------+
  | 架构             | 简洁、模块化       | 重量级（Daemon）   | 专为 K8s 设计    |
  | CRI 支持         | 内置 CRI 插件      | 需要 dockershim   | 原生 CRI         |
  | 镜像管理         | 内置 Image Service | 内置              | 内置             |
  | Docker Compose   | 不支持             | 原生支持           | 不支持           |
  | K8s 支持         | 默认运行时         | 已移除（v1.24+）   | OpenShift 默认   |
  | 性能             | 低延迟、低资源占用  | 较高资源占用        | 低延迟           |
  | 生态             | CNCF 毕业项目      | Docker Inc.        | OCI 社区         |
  | 守护进程         | 有（轻量）          | 有（较重）          | 有（轻量）        |
  | OCI 兼容         | 完全兼容            | 完全兼容            | 完全兼容          |
  +------------------+-------------------+-------------------+------------------+
```

---

## 2. 理论基础

### 2.1 CRI（Container Runtime Interface）

CRI 是 Kubernetes 定义的一组 gRPC 接口（远程过程调用协议），用于 kubelet 与容器运行时之间的通信。CRI 将容器运行时的功能分为两个服务：

| 服务 | 接口 | 说明 |
|------|------|------|
| **RuntimeService** | RunPodSandbox | 创建 Pod 基础设施（Pause 容器） |
| | StopPodSandbox | 停止 Pod 基础设施 |
| | RemovePodSandbox | 删除 Pod 基础设施 |
| | CreateContainer | 在 Pod 中创建容器 |
| | StartContainer | 启动容器 |
| | StopContainer | 停止容器 |
| | RemoveContainer | 删除容器 |
| | ListContainers | 列出容器 |
| | ContainerStatus | 查询容器状态 |
| **ImageService** | PullImage | 拉取镜像 |
| | ListImages | 列出镜像 |
| | RemoveImage | 删除镜像 |
| | ImageStatus | 查询镜像状态 |

### 2.2 containerd 核心概念

| 概念 | 说明 |
|------|------|
| **Namespace** | 镜像和容器的隔离空间（moby/k8s.io/default） |
| **Image** | OCI 标准镜像（Manifest 清单 + Config 配置 + Layers 层） |
| **Container** | 运行中的容器实例 |
| **Snapshot** | 容器文件系统的快照 |
| **Task** | 容器的运行时执行上下文 |
| **Content Store** | 内容寻址存储（存储 Blob 二进制大对象数据） |
| **Metadata Store** | 元数据存储（BoltDB 嵌入式数据库） |

### 2.3 containerd vs Docker vs CRI-O 详细对比

| 维度 | containerd | Docker | CRI-O |
|------|-----------|--------|-------|
| **定位** | 通用容器运行时 | 完整容器平台 | K8s 专用运行时 |
| **守护进程** | containerd | dockerd + containerd | crio |
| **CRI 实现** | 内置 CRI 插件 | dockershim（已废弃） | 原生 CRI |
| **镜像构建** | 需要 buildkit（镜像构建工具） | docker build | 需要 buildah |
| **CLI 工具** | ctr/crictl | docker | crictl/podman |
| **网络** | CNI 插件（容器网络接口） | libnetwork | CNI 插件 |
| **存储** | overlayfs/aufs/btrfs（联合文件系统） | overlayfs2/aufs/btrfs | overlayfs |
| **资源占用** | ~50MB 内存 | ~200MB 内存 | ~50MB 内存 |
| **启动速度** | 快 | 较慢 | 快 |
| **K8s 集成** | v1.24+ 默认 | v1.24 移除 | OpenShift 默认 |
| **社区** | CNCF 毕业项目 | Docker Inc. | OCI 社区 |

### 2.4 Pause 容器（Sandbox，沙箱）

```
  Pod (192.168.1.54)
  +-------------------------------------------+
  |           Network Namespace                |
  |  +-----------+  +-----------+  +---------+ |
  |  |  Pause    |  | Container |  |Container| |
  |  | Container |  |  (Nginx)  |  | (Redis) | |
  |  | (Infra)   |  |           |  |         | |
  |  | 10.244.1.2|  | 共享网络   |  |共享网络  | |
  |  +-----------+  +-----------+  +---------+ |
  |                                           |
  |  Pause 容器负责:                            |
  |  1. 持有 Pod 的网络命名空间                   |
  |  2. 作为 PID 1 回收僵尸进程                   |
  |  3. 挂载共享卷的挂载点                        |
  +-------------------------------------------+
```

---

## 3. 部署实战

### 3.1 安装 containerd

在所有 K8s 节点（192.168.1.51-55）上执行。

#### 3.1.1 安装 containerd 1.7.x

```bash
# 添加 Docker APT 源（containerd 包含在 Docker 仓库中）
apt-get update
apt-get install -y ca-certificates curl gnupg

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y containerd.io

# 验证版本
containerd --version
# 预期输出: containerd github.com/containerd/containerd v1.7.x
```

#### 3.1.2 生成默认配置

```bash
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
```

### 3.2 配置 containerd

#### 3.2.1 完整 config.toml 配置

```bash
cat > /etc/containerd/config.toml << 'EOF'
# /etc/containerd/config.toml
# containerd v1.7.x 完整配置

version = 2  # 配置文件版本

# 插件配置
[plugins]

  # CRI 插件配置
  [plugins."io.containerd.grpc.v1.cri"]

    # 使用 systemd cgroup 驱动（K8s 要求）
    sandbox_image = "192.168.1.61/k8s/pause:3.9"  # Pause 容器镜像

    # CNI 配置
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"  # CNI 插件二进制目录
      conf_dir = "/etc/cni/net.d"  # CNI 配置文件目录

    # 容器运行时配置
    [plugins."io.containerd.grpc.v1.cri".containerd]
      # 默认运行时
      default_runtime_name = "runc"  # OCI 运行时

      # runc 运行时配置
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"  # runc v2 接口
        runtime_engine = ""
        runtime_root = ""

        # 使用 systemd cgroup 驱动
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true  # 使用 systemd 管理 cgroup
          BinaryName = "/usr/bin/runc"

    # 镜像拉取配置
    [plugins."io.containerd.grpc.v1.cri".image_pull_progress_timeout] = "5m"  # 镜像拉取超时

    # Registry 配置（私有仓库）
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"  # 仓库认证配置目录

  # 镜像快照配置
  [plugins."io.containerd.snapshotter.v1.overlayfs"]
    root_path = "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs"  # 快照存储路径

  # 日志配置
  [plugins."io.containerd.internal.v1.logging"]
    level = "info"

# 日志配置
[debug]
  level = "info"

# 指标配置
[metrics]
  address = ""
  grpc_histogram = false

# OOM 配置
[oom]
  score = 0

# GRPC 配置
[grpc]
  address = "/run/containerd/containerd.sock"  # gRPC 通信套接字
  tcp_address = ""
  tcp_tls_cert = ""
  tcp_tls_key = ""
  uid = 0
  gid = 0
  max_recv_message_size = 16777216  # 最大接收消息 16MB
  max_send_message_size = 16777216  # 最大发送消息 16MB

# TTRPC 配置
[ttrpc]
  address = ""
  uid = 0
  gid = 0

# 时区
[time]
  timestamp_format = ""
  timezone = "Asia/Shanghai"
EOF
```

#### 3.2.2 配置 Harbor 私有仓库认证

```bash
# 创建证书目录
mkdir -p /etc/containerd/certs.d/192.168.1.61

# 配置 Harbor 访问（HTTP 模式）
cat > /etc/containerd/certs.d/192.168.1.61/hosts.toml << 'EOF'
server = "http://192.168.1.61"  # Harbor 仓库地址

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]  # 拉取和解析权限
  skip_verify = true  # 跳过 TLS 证书验证
EOF

# 如果使用 HTTPS，配置如下
# mkdir -p /etc/containerd/certs.d/harbor.example.com
# cat > /etc/containerd/certs.d/harbor.example.com/hosts.toml << 'EOF'
# server = "https://harbor.example.com"
#
# [host."https://harbor.example.com"]
#   ca_file = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
#   capabilities = ["pull", "resolve", "push"]
# EOF
```

#### 3.2.3 配置 Docker Hub 镜像加速（可选）

```bash
mkdir -p /etc/containerd/certs.d/docker.io

cat > /etc/containerd/certs.d/docker.io/hosts.toml << 'EOF'
server = "https://docker.io"

[host."https://mirror.gcr.io"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF
```

### 3.3 启动 containerd

```bash
# 重启 containerd 使配置生效
systemctl daemon-reload
systemctl enable --now containerd
systemctl restart containerd

# 验证状态
systemctl status containerd
# 预期: active (running)

# 验证 CRI 插件
ctr --address /run/containerd/containerd.sock plugin ls | grep cri
# 预期输出: io.containerd.grpc.v1          cri        running
```

### 3.4 安装 crictl

```bash
# 下载 crictl
VERSION="v1.29.0"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/${VERSION}/crictl-${VERSION}-linux-amd64.tar.gz

# 安装
tar zxvf crictl-${VERSION}-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-${VERSION}-linux-amd64.tar.gz

# 配置 crictl 连接 containerd
cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock  # CRI 运行时端点
image-endpoint: unix:///run/containerd/containerd.sock  # 镜像服务端点
timeout: 10  # 超时时间（秒）
debug: false
EOF

# 验证
crictl version
# 预期输出:
# RuntimeName:  containerd
# RuntimeVersion: v1.7.x
# RuntimeApiVersion: v1
```

### 3.5 ctr 镜像管理

#### 3.5.1 镜像操作

```bash
# 拉取镜像
ctr -n k8s.io images pull docker.io/library/nginx:alpine  # -n 指定命名空间

# 列出镜像
ctr -n k8s.io images ls

# 列出镜像（带详细信息）
ctr -n k8s.io images ls -q

# 查看镜像详情
ctr -n k8s.io images inspect docker.io/library/nginx:alpine

# 删除镜像
ctr -n k8s.io images rm docker.io/library/nginx:alpine

# 导出镜像
ctr -n k8s.io images export nginx.tar docker.io/library/nginx:alpine

# 导入镜像
ctr -n k8s.io images import nginx.tar

# 给镜像打 tag
ctr -n k8s.io images tag docker.io/library/nginx:alpine 192.168.1.61/k8s/nginx:alpine

# 推送镜像到 Harbor
ctr -n k8s.io images push --user "admin:Harbor12345" 192.168.1.61/k8s/nginx:alpine

# 清理未使用的镜像
ctr -n k8s.io images prune
```

#### 3.5.2 命名空间管理

```bash
# 列出命名空间
ctr namespaces ls

# 创建命名空间
ctr namespaces create myapp

# 在指定命名空间中操作
ctr -n myapp images pull docker.io/library/redis:alpine
ctr -n myapp images ls
```

#### 3.5.3 容器操作

```bash
# 运行容器
ctr -n k8s.io run -d --rm docker.io/library/nginx:alpine nginx-test  # -d 后台运行

# 列出运行中的容器
ctr -n k8s.io containers ls

# 列出任务
ctr -n k8s.io tasks ls

# 停止容器
ctr -n k8s.io tasks kill nginx-test

# 删除容器
ctr -n k8s.io containers delete nginx-test
```

### 3.6 crictl 常用命令

```bash
# 查看版本
crictl version

# 拉取镜像
crictl pull 192.168.1.61/k8s/nginx:alpine

# 列出镜像
crictl images

# 列出运行中的容器
crictl ps

# 列出所有容器（包括已停止的）
crictl ps -a

# 查看容器详情
crictl inspect <container-id>

# 查看容器日志
crictl logs <container-id>

# 在容器中执行命令
crictl exec <container-id> ls /

# 查看容器资源使用
crictl stats

# 停止容器
crictl stop <container-id>

# 删除容器
crictl rm <container-id>

# 查看 Pod Sandbox
crictl pods
crictl inspectp <sandbox-id>

# 查看镜像信息
crictl inspecti 192.168.1.61/k8s/nginx:alpine
```

### 3.7 预拉取 K8s 核心镜像

```bash
# 预拉取 K8s v1.28.15 所需镜像到所有节点
for img in \
    "192.168.1.61/k8s/kube-apiserver:v1.28.15" \
    "192.168.1.61/k8s/kube-controller-manager:v1.28.15" \
    "192.168.1.61/k8s/kube-scheduler:v1.28.15" \
    "192.168.1.61/k8s/kube-proxy:v1.28.15" \
    "192.168.1.61/k8s/pause:3.9" \
    "192.168.1.61/k8s/etcd:3.5.12-0" \
    "192.168.1.61/k8s/coredns:v1.10.1"; do
    crictl pull ${img}
    echo "Pulled: ${img}"
done
```

---

## 4. 配置详解

### 4.1 SystemdCgroup 配置

```toml
# config.toml 中的关键配置
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
```

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `SystemdCgroup` | `true` | 使用 systemd 管理 cgroup（K8s 推荐） |
| `SystemdCgroup` | `false` | 使用 containerd 直接管理 cgroup（旧版行为） |

**为什么 K8s 推荐 SystemdCgroup=true：**
- 与 kubelet 的 `--cgroup-driver=systemd` 保持一致
- systemd 作为统一的 cgroup 管理器，避免资源泄漏
- 更好的资源追踪和回收机制

### 4.2 sandbox_image 配置

```toml
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "192.168.1.61/k8s/pause:3.9"
```

- `sandbox_image` 指定 Pause 容器镜像，每个 Pod 创建时首先拉取此镜像
- 生产环境建议使用私有仓库中的 Pause 镜像，避免依赖外部网络
- K8s v1.28 默认使用 `registry.k8s.io/pause:3.9`

### 4.3 镜像存储配置

```toml
[plugins."io.containerd.snapshotter.v1.overlayfs"]
  root_path = "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs"
```

containerd 支持多种 Snapshotter：

| Snapshotter | 说明 | 适用场景 |
|-------------|------|---------|
| `overlayfs` | 基于 OverlayFS（默认） | 大多数 Linux 发行版 |
| `native` | 原生 snapshot（快照） | 无 OverlayFS 支持的系统 |
| `btrfs` | 基于 Btrfs（写时复制文件系统） | 使用 Btrfs 文件系统 |
| `devmapper` | Device Mapper（设备映射器） | 需要精简配置 |
| `fuse-overlayfs` | FUSE 实现 OverlayFS（用户空间） | Rootless 容器 |

### 4.4 日志配置

```toml
# containerd 全局日志
[debug]
  level = "info"  # debug/info/warn/error

# 容器日志（通过 CRI）
# 容器日志由 kubelet 管理，在 kubelet 配置中设置
# --container-log-max-size=100Mi
# --container-log-max-files=5
```

### 4.5 性能调优参数

```toml
# GRPC 配置
[grpc]
  max_recv_message_size = 16777216  # 16MB，默认值
  max_send_message_size = 16777216  # 16MB，默认值

# 如果需要处理大镜像，可以增大
# max_recv_message_size = 104857600  # 100MB
```

---

## 5. 验证与测试

### 5.1 验证 containerd 服务

```bash
# 检查服务状态
systemctl status containerd

# 检查 CRI 插件
ctr plugin ls | grep cri

# 检查配置
containerd config dump | grep -A5 "SystemdCgroup"
# 预期输出: SystemdCgroup = true

# 检查 sandbox_image
containerd config dump | grep sandbox_image
# 预期输出: sandbox_image = "192.168.1.61/k8s/pause:3.9"
```

### 5.2 验证 crictl

```bash
# 版本信息
crictl version

# 拉取测试镜像
crictl pull 192.168.1.61/k8s/busybox:latest

# 列出镜像
crictl images | grep busybox

# 运行测试容器
crictl run --rm 192.168.1.61/k8s/busybox:latest echo "Hello containerd"
```

### 5.3 验证 Harbor 连通性

```bash
# 使用 ctr 测试拉取
ctr -n k8s.io images pull --user "admin:Harbor12345" 192.168.1.61/k8s/nginx:alpine

# 验证镜像已下载
ctr -n k8s.io images ls | grep nginx
```

### 5.4 验证 SystemdCgroup

```bash
# 运行一个容器后检查 cgroup
crictl run -d --rm 192.168.1.61/k8s/busybox:latest sleep 3600

# 获取容器 ID
CONTAINER_ID=$(crictl ps -q | head -1)

# 检查 cgroup 路径
cat /proc/$(crictl inspect ${CONTAINER_ID} | jq -r '.info.pid')/cgroup
# 预期输出应包含 systemd 路径，如:
# 0::/kubepods/besteffort/podxxx/xxx
```

---

## 6. CKA/CKS 考点融入

### 6.1 CKA 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 容器运行时 | 理解 CRI 协议和 containerd 角色 | 2.1 节 |
| crictl 命令 | 使用 crictl 管理容器和镜像 | 3.6 节 |
| 镜像管理 | 拉取、推送、删除镜像 | 3.5 节 |

### 6.2 CKS 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 私有仓库认证 | 配置 containerd 访问私有仓库 | 3.2.2 节 |
| 镜像安全 | 使用私有仓库控制镜像来源 | 3.2.2 节 |
| SystemdCgroup | 正确配置 cgroup 驱动 | 4.1 节 |

### 6.3 考试技巧

1. CKA 中 `crictl` 是排查容器问题的核心工具，记住常用命令：`crictl ps`、`crictl logs`、`crictl inspect`
2. CKS 中配置私有仓库认证是必考题，注意 `hosts.toml` 的格式和路径
3. 区分 `ctr`（containerd 原生工具，操作 `k8s.io` 命名空间）和 `crictl`（CRI 兼容工具）

---

## 7. 高频面试题

### Q1: 什么是 CRI？为什么 Kubernetes 要引入 CRI？ [难度: 中]

**答案：** CRI（Container Runtime Interface）是 Kubernetes 在 v1.5 引入的标准接口，定义了 kubelet 与容器运行时之间的通信协议。引入 CRI 的核心原因是解耦：在 CRI 出现之前，kubelet 内部硬编码了对 Docker 的支持（通过 dockershim），如果要支持新的运行时（如 rkt、containerd），必须修改 kubelet 源码，违反了开放-封闭原则。CRI 通过定义一组标准的 gRPC 接口（RuntimeService 和 ImageService），使任何实现了 CRI 的运行时都可以接入 Kubernetes，无需修改 kubelet 代码。CRI 的引入催生了 containerd CRI 插件和 CRI-O 等专用运行时。Kubernetes v1.24 正式移除了 dockershim，containerd 成为默认运行时。CRI 接口设计精炼，只关注 Pod 和容器的生命周期管理，不涉及镜像构建、网络等高层功能，保持了接口的简洁性和稳定性。

### Q2: containerd 和 Docker 有什么区别？为什么 K8s 选择 containerd？ [难度: 中]

**答案：** Docker 是一个完整的容器平台，包含 Docker CLI、Docker Daemon（dockerd）、containerd、runc 等多个组件，功能覆盖镜像构建、容器运行、编排（Docker Swarm）、网络（libnetwork）等。containerd 是一个专注于容器运行时的轻量级组件，只负责容器的生命周期管理和镜像管理。K8s 选择 containerd 的原因：第一，架构简洁：containerd 直接实现 CRI 接口，减少了 Docker Daemon 这一中间层，降低了调用链路和资源开销（内存从 ~200MB 降到 ~50MB）。第二，性能更好：去掉了 Docker Daemon 后，容器启动延迟更低，资源占用更少。第三，维护更简单：containerd 是 CNCF 毕业项目，社区活跃，版本迭代快。第四，安全性更高：更少的组件意味着更小的攻击面。第五，K8s 本身已经提供了编排、网络（CNI）、存储（CSI）等功能，不需要 Docker 的这些附加功能。

### Q3: SystemdCgroup=true 的作用是什么？为什么 K8s 推荐使用？ [难度: 中]

**答案：** SystemdCgroup=true 表示 containerd 将容器的 cgroup 管理委托给 systemd，而不是由 containerd/runc 直接操作 cgroup 文件系统。K8s 推荐使用 SystemdCgroup 的原因有三个：第一，cgroup 管理一致性：当 kubelet 和 containerd 都使用 systemd 作为 cgroup 驱动时，systemd 作为唯一的 cgroup 管理者，可以确保 cgroup 层级结构的一致性，避免出现"孤儿 cgroup"（进程退出但 cgroup 未清理）。第二，资源回收更可靠：systemd 会自动清理空 cgroup，而直接操作 cgroup 文件系统可能导致资源泄漏，特别是在容器频繁创建销毁的场景下。第三，与 Linux 发行版集成更好：现代 Linux 发行版（Ubuntu 22.04、RHEL 9）默认使用 systemd 管理系统资源，使用 systemd cgroup 可以更好地与系统级资源管理集成。如果 kubelet 使用 `--cgroup-driver=systemd` 而 containerd 使用 `SystemdCgroup=false`，会导致 Pod 的 cgroup 路径不一致，可能引发资源限制失效等问题。

### Q4: Pause 容器的作用是什么？为什么每个 Pod 都需要它？ [难度: 中]

**答案：** Pause 容器（也称 Sandbox 容器或 Infra 容器）是每个 Pod 的第一个容器，由 kubelet 通过 CRI 的 RunPodSandbox 接口创建。它的作用有三个方面：第一，持有网络命名空间：Pause 容器创建了 Pod 的网络命名空间（Network Namespace），Pod 中的所有业务容器共享这个网络命名空间，因此它们共享同一个 IP 地址和端口空间，可以通过 localhost 互相访问。第二，PID 1 进程回收：Pause 容器作为 Pod 中 PID 为 1 的进程，负责回收僵尸进程。当业务容器的子进程成为孤儿进程时，Pause 容器会通过 init 机制回收它们，避免僵尸进程堆积。第三，挂载点保持：Pause 容器持有 Pod 的挂载命名空间，确保即使所有业务容器重启，Pod 的挂载点也不会丢失。Pause 容器使用极简的镜像（约 300KB），资源消耗可以忽略不计。在 containerd 中，Pause 镜像通过 `sandbox_image` 配置指定。

### Q5: crictl 和 ctr 有什么区别？什么时候用哪个？ [难度: 低]

**答案：** crictl 和 ctr 都是 containerd 的命令行工具，但定位不同。ctr 是 containerd 的原生 CLI 工具，直接通过 containerd 的原生 gRPC API 与 containerd 通信，功能最全面，包括命名空间管理、镜像导入导出、内容管理、快照管理等。ctr 需要指定命名空间（`-n k8s.io`）来操作 K8s 相关的镜像和容器。crictl 是 Kubernetes CRI 兼容的命令行工具，通过 CRI gRPC 接口与 containerd 通信，命令风格类似 Docker CLI。crictl 只能操作 K8s 相关的容器和镜像，功能子集较小（不支持命名空间、内容管理等）。使用场景：排查 K8s 容器问题时使用 crictl（因为它操作的是 K8s 管理的容器），进行底层镜像管理、导入导出、调试时使用 ctr。在 CKA 考试中，主要使用 crictl。

### Q6: containerd 的命名空间（Namespace）有什么作用？ [难度: 低]

**答案：** containerd 的命名空间用于隔离不同使用者的镜像和容器。containerd 内置了三个默认命名空间：`default`（containerd 默认命名空间）、`moby`（Docker 使用的命名空间）和 `k8s.io`（Kubernetes 使用的命名空间）。命名空间的隔离意味着在 `k8s.io` 命名空间中拉取的镜像在 `default` 命名空间中不可见，反之亦然。这种设计允许多个上层系统（K8s、Docker、自定义程序）共享同一个 containerd 实例而互不干扰。在 K8s 环境中，kubelet 通过 CRI 插件操作 `k8s.io` 命名空间，因此使用 ctr 操作 K8s 镜像时必须指定 `-n k8s.io`。命名空间可以通过 `ctr namespaces create/delete/ls` 管理。

### Q7: 如何配置 containerd 使用 Harbor 私有仓库？ [难度: 中]

**答案：** containerd v1.7+ 支持通过 `/etc/containerd/certs.d/<registry>/hosts.toml` 文件配置镜像仓库。配置步骤为：首先在 config.toml 中设置 `[plugins."io.containerd.grpc.v1.cri".registry].config_path = "/etc/containerd/certs.d"`，然后为每个仓库创建对应的 hosts.toml 文件。对于 HTTP 仓库（无 TLS），需要设置 `server = "http://192.168.1.61"` 并在 host 段落中设置 `skip_verify = true`。对于 HTTPS 仓库，需要指定 CA 证书路径 `ca_file`。认证方式有两种：一是在 hosts.toml 中不配置认证，通过 `ctr images pull --user username:password` 手动认证后 containerd 会缓存凭据；二是在 K8s 中创建 `imagePullSecrets`（类型为 `kubernetes.io/dockerconfigjson`），kubelet 会自动将凭据传递给 CRI。生产环境推荐使用 HTTPS + 机器人账号的方式。

### Q8: containerd 的镜像存储结构是怎样的？ [难度: 高]

**答案：** containerd 使用内容寻址存储（Content Addressable Storage, CAS，内容寻址存储）来管理镜像数据。镜像存储在 `/var/lib/containerd/` 目录下，核心子目录包括：`io.containerd.content.v1.content/blobs/sha256/` 存储所有 Blob 数据（镜像层、Manifest、Config），文件名为内容的 SHA256 摘要；`io.containerd.snapshotter.v1.overlayfs/snapshots/` 存储容器的文件系统快照（基于 OverlayFS 的 upper/lower/work 目录）；`io.containerd.metadata.v1.bolt/meta.db` 是 BoltDB 数据库，存储镜像和容器的元数据索引。当拉取镜像时，containerd 首先下载 Manifest，解析出所有 Layer 的 digest，然后并行下载所有 Layer Blob，最后通过 Snapshotter 创建可用的文件系统快照。CAS 的优势是天然去重：相同内容的 Blob 只存储一份，即使被多个镜像引用。

### Q9: 什么是 OCI（Open Container Initiative）？containerd 如何遵循 OCI 标准？ [难度: 中]

**答案：** OCI（Open Container Initiative，开放容器倡议）是 Linux 基金会下的开放标准项目，旨在定义容器格式和运行时的行业标准。OCI 包含三个核心规范：第一，镜像规范（Image Spec）：定义了容器的文件系统格式，包括 Manifest（描述镜像的元数据）、Config（容器的默认配置）、Layer（文件系统层，使用 tar+gzip 格式）。第二，运行时规范（Runtime Spec）：定义了容器的运行时行为，包括文件系统隔离（rootfs）、命名空间（PID/Network/Mount/UTS/IPC/User）、cgroup 资源限制、Linux capabilities、Seccomp 等。第三，分发规范（Distribution Spec）：定义了镜像仓库的 API（基于 Docker Registry V2 API）。containerd 完全遵循 OCI 标准：镜像管理遵循镜像规范，通过 runc 运行容器遵循运行时规范，镜像推送拉取遵循分发规范。这种标准化使得容器可以在任何 OCI 兼容的运行时之间迁移。

### Q10: 如何排查 containerd 拉取镜像失败的问题？ [难度: 中]

**答案：** containerd 拉取镜像失败的排查步骤为：首先检查网络连通性，`curl -v http://192.168.1.61/v2/` 确认仓库可达；然后检查认证配置，确认 `/etc/containerd/certs.d/` 下的 hosts.toml 配置正确；接着检查 containerd 日志，`journalctl -u containerd --since "10 minutes ago"` 查看详细错误；如果是证书问题，确认 `skip_verify` 设置或 CA 证书路径正确；如果是 DNS 问题，检查 `/etc/resolv.conf` 配置；如果是存储空间不足，`df -h /var/lib/containerd` 检查磁盘空间。常见错误及解决方案：`401 Unauthorized` 表示认证失败，检查用户名密码；`connection refused` 表示仓库不可达，检查网络和防火墙；`no space left on device` 表示磁盘满，清理空间或扩容；`x509: certificate signed by unknown authority` 表示证书问题，配置 skip_verify 或添加 CA 证书。

### Q11: containerd 如何实现容器的资源限制？ [难度: 高]

**答案：** containerd 通过 OCI Runtime（runc）将 K8s 的资源限制转换为 Linux cgroup 配置。当 kubelet 创建 Pod 时，会在 PodSpec 中指定容器的资源请求（requests）和限制（limits），包括 CPU、内存、hugepages 等。这些信息通过 CRI 的 CreateContainerRequest 传递给 containerd 的 CRI 插件，CRI 插件将其转换为 OCI Runtime Spec 中的 Linux 资源配置。runc 在创建容器时，根据 OCI Spec 设置 cgroup：CPU 限制通过 `cpu.cfs_quota_us` 和 `cpu.cfs_period_us` 实现（设置 CPU 使用上限），CPU 请求通过 `cpu.shares` 实现（设置相对权重）；内存限制通过 `memory.limit_in_bytes` 实现，内存请求通过 `memory.soft_limit_in_bytes` 实现。当使用 `SystemdCgroup=true` 时，runc 通过 systemd 的 `org.freedesktop.systemd1.Manager.StartTransientUnit` 接口创建 cgroup，systemd 负责管理 cgroup 的生命周期。

### Q12: 什么是 Snapshotter？containerd 支持哪些 Snapshotter？ [难度: 中]

**答案：** Snapshotter 是 containerd 中负责管理容器文件系统快照的组件。当创建容器时，Snapshotter 将镜像的只读层（Layer）组合成一个可写的文件系统视图（Union Mount）。containerd 支持多种 Snapshotter 实现：OverlayFS（默认，基于内核 OverlayFS 驱动，性能最好，要求内核 >= 4.0 且文件系统支持 OverlayFS）；Native（使用原生目录复制，兼容性最好但性能最差）；Btrfs（基于 Btrfs 文件系统的 CoW 特性，性能好但需要 Btrfs 文件系统）；Device Mapper（基于内核 Device Mapper，支持精简配置但需要额外的块设备）；Fuse-overlayfs（在用户空间实现 OverlayFS，适用于 Rootless 容器）。在生产环境中，推荐使用 OverlayFS Snapshotter，它利用内核的 OverlayFS 驱动，通过 lowerdir（只读层）+ upperdir（可写层）+ workdir（工作目录）的组合实现高效的文件系统叠加。

---

## 8. 故障排查案例

### 案例 1: containerd 启动失败 "Failed to start containerd"

**现象：**
```bash
systemctl status containerd
# containerd.service - containerd container runtime
#    Loaded: loaded
#    Active: failed (Result: exit-code)
# Error: failed to start containerd: open /etc/containerd/config.toml: permission denied
```

**排查步骤：**
1. 检查配置文件权限：`ls -la /etc/containerd/config.toml`
2. 检查 containerd 数据目录权限：`ls -la /var/lib/containerd/`
3. 检查 SELinux/AppArmor 状态

**解决方案：**
```bash
# 修复配置文件权限
chown root:root /etc/containerd/config.toml
chmod 644 /etc/containerd/config.toml

# 修复数据目录权限
chown -R root:root /var/lib/containerd

# 重启
systemctl restart containerd
```

### 案例 2: crictl 报错 "runtime service not found"

**现象：**
```bash
crictl version
# FATA: getting the runtime version failed: rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /run/containerd/containerd.sock: connect: no such file or directory"
```

**排查步骤：**
1. 检查 containerd 是否运行：`systemctl status containerd`
2. 检查 socket 文件：`ls -la /run/containerd/containerd.sock`
3. 检查 crictl 配置：`cat /etc/crictl.yaml`

**解决方案：**
```bash
# 确保 crictl 配置正确
cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# 如果 containerd 未运行，启动它
systemctl start containerd

# 验证
crictl version
```

### 案例 3: 拉取镜像超时 "context deadline exceeded"

**现象：**
```bash
crictl pull 192.168.1.61/k8s/nginx:alpine
# FATA: pulling image failed: rpc error: code = DeadlineExceeded desc = failed to pull and unpack image "192.168.1.61/k8s/nginx:alpine": failed to resolve reference "192.168.1.61/k8s/nginx:alpine": failed to do request: Head "https://192.168.1.61/v2/k8s/nginx/manifests/alpine": context deadline exceeded
```

**排查步骤：**
1. 检查网络连通性：`curl -v http://192.168.1.61/v2/`
2. 检查 hosts.toml 配置：`cat /etc/containerd/certs.d/192.168.1.61/hosts.toml`
3. 注意错误中的 `https://`，说明 containerd 尝试使用 HTTPS

**解决方案：**
```bash
# 问题原因：containerd 默认尝试 HTTPS，但 Harbor 使用 HTTP
# 修复 hosts.toml，明确指定 HTTP
cat > /etc/containerd/certs.d/192.168.1.61/hosts.toml << 'EOF'
server = "http://192.168.1.61"

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF

# 重启 containerd
systemctl restart containerd

# 重新拉取
crictl pull 192.168.1.61/k8s/nginx:alpine
```

### 案例 4: kubelet 报错 "cgroup driver mismatch"

**现象：**
```bash
journalctl -u kubelet | grep cgroup
# "Failed to create pod sandbox: rpc error: code = Unknown desc = failed to create containerd task: failed to create shim task: OCI runtime create failed: unable to retrieve OCI runtime error: cgroup driver mismatch"
```

**排查步骤：**
1. 检查 kubelet 的 cgroup 驱动：`ps aux | grep kubelet | grep cgroup-driver`
2. 检查 containerd 的 SystemdCgroup 配置：`containerd config dump | grep SystemdCgroup`

**解决方案：**
```bash
# 确保 kubelet 和 containerd 使用相同的 cgroup 驱动

# 方案1: 修改 containerd 使用 systemd（推荐）
# 确认 config.toml 中:
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
#   SystemdCgroup = true
systemctl restart containerd

# 方案2: 修改 kubelet 使用 cgroupfs
# 在 /etc/default/kubelet 或 kubelet 配置中设置:
# --cgroup-driver=cgroupfs
# 不推荐，K8s 默认使用 systemd
```

### 案例 5: sandbox_image 拉取失败导致 Pod 无法创建

**现象：**
```bash
kubectl describe pod <pod-name>
# Events:
#   Warning  FailedCreatePodSandBox  Failed to create pod sandbox: rpc error: code = Unknown desc = failed to pull image "registry.k8s.io/pause:3.9": failed to resolve reference
```

**排查步骤：**
1. 检查 sandbox_image 配置：`containerd config dump | grep sandbox_image`
2. 确认镜像是否存在于 Harbor：`curl -s http://192.168.1.61/v2/k8s/pause/tags/list -u admin:Harbor12345`

**解决方案：**
```bash
# 修改 sandbox_image 指向 Harbor 中的镜像
sed -i 's|sandbox_image = "registry.k8s.io/pause:3.9"|sandbox_image = "192.168.1.61/k8s/pause:3.9"|' \
    /etc/containerd/config.toml

systemctl restart containerd

# 预拉取 Pause 镜像
crictl pull 192.168.1.61/k8s/pause:3.9

# 删除 Pending 的 Pod 让其重建
kubectl delete pod <pod-name> -n <namespace>
```

### 案例 6: containerd 磁盘空间不足

**现象：**
```bash
# 容器创建缓慢或失败
# containerd 日志: no space left on device

df -h /var/lib/containerd
# /dev/sda1  100G  98G  2G  98% /var/lib/containerd
```

**排查步骤：**
1. 检查磁盘使用：`du -sh /var/lib/containerd/*`
2. 检查未使用的镜像：`crictl images`
3. 检查已退出的容器：`crictl ps -a | grep Exited`

**解决方案：**
```bash
# 1. 清理未使用的镜像
crictl rmi --prune

# 2. 使用 ctr 清理
ctr -n k8s.io images prune

# 3. 清理 containerd 内容存储
ctr -n k8s.io content prune

# 4. 如果仍然不足，手动清理旧快照
# 查看快照占用
du -sh /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/*

# 5. 长期方案：将 containerd 数据目录迁移到更大的磁盘
# 修改 /etc/containerd/config.toml 中的 root 路径
# 或使用符号链接
```

---

## 9. 生产环境建议

### 9.1 性能优化

1. **OverlayFS**：确保使用 OverlayFS 作为 Snapshotter（性能最优）
2. **磁盘 I/O**：将 containerd 数据目录放在 SSD 上，特别是 `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/`
3. **GRPC 限制**：对于大镜像场景，适当增大 `max_recv_message_size`
4. **镜像预加载**：使用 `ctr images import` 预加载常用镜像，避免运行时拉取延迟
5. **并发拉取**：containerd 默认支持并行拉取镜像层，无需额外配置

### 9.2 安全加固

1. **TLS 通信**：生产环境使用 HTTPS 访问镜像仓库，配置 CA 证书
2. **镜像签名**：使用 Cosign 或 Notary 对镜像签名，部署时验证
3. **私有仓库**：禁止从公共仓库直接拉取镜像，所有镜像通过 Harbor 分发
4. **Seccomp/AppArmor**：为容器配置 Seccomp Profile 和 AppArmor Profile
5. **Rootless 模式**：对非特权容器考虑使用 Rootless containerd

### 9.3 运维管理

1. **日志管理**：配置 containerd 日志轮转，避免日志文件过大
2. **监控**：通过 Prometheus 监控 containerd 指标（容器数、镜像数、操作延迟）
3. **定期清理**：配置定时任务清理未使用的镜像和快照
4. **版本管理**：跟随 K8s 版本选择对应的 containerd 版本
5. **备份**：定期备份 containerd 配置文件和 certs.d 目录

### 9.4 故障恢复

1. **配置备份**：将 `/etc/containerd/` 目录纳入版本管理
2. **快速恢复**：准备 containerd 重装脚本，确保 10 分钟内恢复
3. **数据恢复**：containerd 数据目录损坏时，重新拉取镜像即可恢复
4. **健康检查**：监控 containerd 进程状态和 socket 可用性

---

> **下一模块：** 04-K8s 集群初始化 -- HA 架构、kubeadm init/join 与 etcd 管理
