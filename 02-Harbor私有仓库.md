# 模块02：Harbor 私有仓库

---

## 1. 概述与架构图

### 1.1 课程目标

本模块详细介绍 Harbor 私有镜像仓库的部署、配置与运维。Harbor 是 CNCF（云原生计算基金会）毕业项目，提供镜像存储、漏洞扫描、镜像签名、Helm Chart 仓库等企业级功能。完成本模块后，你将掌握 Harbor v2.9.0 的完整部署流程，包括从海外服务器同步镜像、Trivy（容器安全扫描器）安全扫描以及 containerd 对接 Harbor 的配置方法。

### 1.2 Harbor 架构图

```
                          +-------------------------------------------+
                          |            Harbor Server                   |
                          |           192.168.1.61                     |
                          |            4C / 8G                         |
                          +-------------------+-----------------------+
                                              |
              +-------------------------------+-------------------------------+
              |                               |                               |
     +--------+--------+            +---------+---------+           +---------+---------+
     |    Nginx/Proxy   |            |    Harbor Core    |           |     Registry     |
     |  (反向代理/路由)   |            |  (API/权限/策略)  |           |  (镜像存储后端)   |
     +--------+---------+            +---------+---------+           +---------+---------+
              |                               |                               |
              +-------------------------------+-------------------------------+
                                              |
              +-------------------------------+-------------------------------+
              |               |               |               |               |
     +--------+------+  +-----+------+  +----+-----+  +----+-----+  +-----+------+
     |    Portal     |  |   Trivy    |  |  JobSvc  |  |   Redis   |  |  PostgreSQL |
     |  (Web UI)    |  | (漏洞扫描)  |  | (异步任务)|  |  (缓存)   |  |  (元数据)   |
     +---------------+  +------------+  +----------+  +-----------+  +-------------+
```

### 1.3 镜像同步架构

```
  海外镜像源            美国云服务器              Harbor
  (Docker Hub/         43.135.167.116          192.168.1.61
   gcr.io/k8s.gcr.io)
       |                      |                      |
       |--- docker pull ----->|                      |
       |                      |--- docker save ----->|
       |                      |    (tar 文件)        |
       |                      |                      |--- docker load
       |                      |    rsync/scp         |    trivy scan
       |                      |<--- rsync/scp -------|    推送到项目
       |                      |                      |
```

### 1.4 Harbor 核心组件

| 组件 | 说明 |
|------|------|
| **Core** | Harbor 核心服务，提供 API、权限管理、策略管理 |
| **Portal** | Web UI 管理界面 |
| **Registry** | 基于 Docker Distribution v2 的镜像存储后端 |
| **Trivy** | Aqua Security 开源的容器镜像漏洞扫描器 |
| **JobService** | 异步任务服务（镜像复制、GC、扫描） |
| **Redis** | 缓存层，存储会话和 Job 状态 |
| **PostgreSQL** | 元数据存储（用户、项目、策略、扫描结果） |
| **Nginx/Proxy** | 反向代理（Reverse Proxy），统一入口，路由分发 |

---

## 2. 理论基础

### 2.1 Harbor 核心功能

| 功能 | 说明 |
|------|------|
| **多项目管理** | 支持创建多个项目，每个项目独立权限控制 |
| **RBAC 权限** | 基于角色的访问控制（Admin/Maintainer/Developer/Guest/LimitedGuest） |
| **镜像复制** | 支持跨 Harbor 实例的镜像同步（Push/Pull 模式） |
| **漏洞扫描** | 集成 Trivy，支持镜像层和 OS 包的 CVE（通用漏洞披露）扫描 |
| **镜像签名** | 基于 Notary 的镜像内容信任（DCT，Docker Content Trust） |
| **Helm Chart** | 原生支持 Helm Chart（K8s 应用包）仓库 |
| **垃圾回收** | 清理未被引用的镜像层，释放存储空间 |
| **镜像保留策略** | 基于标签/规则的自动清理策略 |

### 2.2 Harbor 认证方式

```
docker login harbor.example.com
# 方式1: 用户名/密码认证
# 方式2: 客户端证书认证
# 方式3: OIDC/SSO 集成

# 认证流程:
Client                    Harbor (Nginx)              Core               Registry
  |                           |                        |                    |
  |-- docker pull ----------->|                        |                    |
  |                           |-- Token Request ------->|                    |
  |                           |                        |-- Auth Request --->|
  |                           |                        |<-- Auth Response ---|
  |                           |<-- Bearer Token -------|                    |
  |<-- 401 + WWW-Auth ------|                        |                    |
  |-- docker login ---------->|                        |                    |
  |                           |-- Auth (user/pass) --->|                    |
  |                           |<-- Bearer Token -------|                    |
  |<-- Login Success ---------|                        |                    |
  |-- docker pull (token) --->|                        |                    |
  |                           |                        |-- Pull (token) --->|
  |                           |                        |<-- Manifest/Blob --|
  |<-- Image Layers ---------|                        |                    |
```

### 2.3 镜像同步策略

| 策略 | 说明 | 适用场景 |
|------|------|---------|
| **Pull 模式** | 从远端 Harbor/Docker Hub 拉取镜像到本地 | 国内加速海外镜像 |
| **Push 模式** | 将本地镜像推送到远端 Harbor | 多数据中心分发 |
| **定时同步** | 基于 Cron 表达式定时执行 | 定期同步上游更新 |
| **事件驱动** | Webhook 触发同步 | 实时同步需求 |

---

## 3. 部署实战

### 3.1 Harbor 服务器环境准备

在 192.168.1.61 上执行。

#### 3.1.1 安装 Docker

```bash
# 安装 Docker（Harbor 依赖 Docker Compose v2）
apt-get update
apt-get install -y ca-certificates curl gnupg

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable --now docker
docker --version
docker compose version
```

#### 3.1.2 配置 Docker

```bash
cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m", # 单个日志文件最大100MB
        "max-file": "3" # 最多保留3个日志文件
    },
    "storage-driver": "overlay2", # 存储驱动
    "exec-opts": ["native.cgroupdriver=systemd"], # cgroup驱动与K8s一致
    "insecure-registries": ["192.168.1.61:80"] # 信任的HTTP仓库
}
EOF

systemctl daemon-reload
systemctl restart docker
```

### 3.2 安装 Harbor v2.9.0

#### 3.2.1 下载并解压

```bash
cd /opt
wget https://github.com/goharbor/harbor/releases/download/v2.9.0/harbor-offline-installer-v2.9.0.tgz
tar zxvf harbor-offline-installer-v2.9.0.tgz
cd harbor
```

#### 3.2.2 配置 harbor.yml

```bash
cp harbor.yml.tmpl harbor.yml
cat > harbor.yml << 'EOF'
# Harbor 核心配置
hostname: 192.168.1.61 # Harbor访问地址

# HTTP 端口
http:
  port: 80 # HTTP服务端口

# HTTPS 端口（可选，建议生产环境启用）
# https:
#   port: 443
#   certificate: /your/cert/path
#   private_key: /your/key/path

# Harbor 管理员初始密码
harbor_admin_password: Harbor12345 # 管理员密码

# 数据库配置（使用内置 PostgreSQL）
database:
  password: Harbor12345 # 数据库密码
  max_idle_conns: 100 # 最大空闲连接数
  max_open_conns: 300 # 最大打开连接数

# 数据卷挂载路径
data_volume: /data # 数据存储路径

# Trivy 漏洞扫描配置
trivy:
  ignore_unfixed: false # 不忽略无修复方案的漏洞
  skip_update: false
  offline_scan: true # 离线扫描模式
  security_check: vuln # 安全检查类型
  insecure: false

# Job Service 并发数
jobservice:
  max_job_workers: 10 # 最大并发任务数

# 日志级别
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor

# 镜像存储（可选 S3/MinIO）
# storage_service:
#   s3:
#     accesskey: xxx
#     secretkey: xxx
#     region: us-east-1
#     regionendpoint: http://minio:9000
#     bucket: harbor
EOF
```

#### 3.2.3 执行安装

```bash
# 安装 Harbor（含 Trivy 扫描器）
./install.sh --with-trivy

# 预期输出:
# ----Harbor has been installed and started successfully.----
```

#### 3.2.4 验证安装

```bash
# 检查容器状态
docker compose -f /opt/harbor/docker-compose.yml ps

# 访问 Web UI
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.61
# 预期输出: 200
```

### 3.3 创建项目和用户

#### 3.3.1 创建项目

```bash
# 通过 API 创建项目
curl -X POST "http://192.168.1.61/api/v2.0/projects" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "project_name": "k8s",
        "public": false,
        "metadata": {
            "auto_scan": "true",
            "reuse_sys_cve_allowlist": "false",
            "retention_id": "2"
        }
    }'

# 创建更多项目
for proj in library k8s middleware app devops; do
    curl -X POST "http://192.168.1.61/api/v2.0/projects" \
        -H "Content-Type: application/json" \
        -u "admin:Harbor12345" \
        -d "{\"project_name\": \"${proj}\", \"public\": false}"
done
```

#### 3.3.2 创建机器人账号（供 K8s 使用）

```bash
# 创建机器人账号，用于 K8s 节点拉取镜像
curl -X POST "http://192.168.1.61/api/v2.0/robots" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "name": "k8s-pull",
        "description": "K8s cluster pull robot",
        "access": [
            {
                "resource": "/project/k8s/repository",
                "action": "pull"
            },
            {
                "resource": "/project/library/repository",
                "action": "pull"
            }
        ],
        "duration": -1
    }'

# 记录返回的 token（格式: robot$k8s-pull@harbor:xxxxx）
```

### 3.4 镜像同步（美国服务器 -> Harbor）

#### 3.4.1 在美国服务器（43.135.167.116）准备环境

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | bash
systemctl enable --now docker

# 登录 Harbor
echo "Harbor12345" | docker login 192.168.1.61 -u admin --password-stdin
```

#### 3.4.2 批量拉取并同步 K8s 核心镜像

```bash
cat > /root/sync-images.sh << 'SCRIPT'
#!/bin/bash
# K8s v1.28.15 核心镜像同步脚本
# 在美国服务器上执行

HARBOR_ADDR="192.168.1.61"
HARBOR_USER="admin"
HARBOR_PASS="Harbor12345"

# K8s v1.28.15 核心镜像列表
IMAGES=(
    "registry.k8s.io/kube-apiserver:v1.28.15"
    "registry.k8s.io/kube-controller-manager:v1.28.15"
    "registry.k8s.io/kube-scheduler:v1.28.15"
    "registry.k8s.io/kube-proxy:v1.28.15"
    "registry.k8s.io/pause:3.9"
    "registry.k8s.io/etcd:3.5.12-0"
    "registry.k8s.io/coredns/coredns:v1.10.1"
    "calico/cni:v3.26.4"
    "calico/node:v3.26.4"
    "calico/kube-controllers:v3.26.4"
    "calico/pod2daemon-flexvol:v3.26.4"
    "quay.io/prometheus-operator/prometheus-operator:v0.68.0"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.68.0"
    "quay.io/prometheus-operator/prometheus:v2.48.1"
    "quay.io/prometheus-operator/alertmanager:v0.26.0"
    "quay.io/prometheus-operator/node-exporter:v1.7.0"
    "quay.io/prometheus-operator/kube-state-metrics:v2.10.1"
    "grafana/grafana:10.2.3"
    "quay.io/kiwigrid/k8s-sidecar:1.25.2"
    "docker.io/jettech/kube-webhook-certgen:v1.5.2"
    "docker.io/library/nginx:1.25-alpine"
    "docker.io/library/busybox:1.36"
    "docker.io/library/redis:7-alpine"
    "docker.io/bitnami/promtail:2.9.4"
    "docker.io/grafana/loki:2.9.4"
    "docker.io/library/mysql:8.0"
    "docker.io/library/java:11-jdk-slim"
)

# 登录 Harbor
echo "${HARBOR_PASS}" | docker login ${HARBOR_ADDR} -u ${HARBOR_USER} --password-stdin

for img in "${IMAGES[@]}"; do
    echo "========================================"
    echo "Processing: ${img}"
    echo "========================================"

    # 1. 拉取镜像
    docker pull ${img}

    # 2. 转换 tag
    # registry.k8s.io -> 192.168.1.61/registry.k8s.io
    # quay.io -> 192.168.1.61/registry.k8s.io
    # docker.io -> 192.168.1.61/library
    if [[ "${img}" == registry.k8s.io/* ]]; then
        target="${HARBOR_ADDR}/k8s/${img#registry.k8s.io/}"
    elif [[ "${img}" == quay.io/* ]]; then
        target="${HARBOR_ADDR}/k8s/${img#quay.io/}"
    elif [[ "${img}" == docker.io/* ]]; then
        target="${HARBOR_ADDR}/${img#docker.io/}"
    else
        target="${HARBOR_ADDR}/k8s/${img}"
    fi

    # 3. 打 tag
    docker tag ${img} ${target}

    # 4. 推送到 Harbor
    docker push ${target}

    # 5. 清理本地镜像
    docker rmi ${img} ${target}

    echo "Done: ${img} -> ${target}"
done

echo "All images synced successfully!"
SCRIPT

chmod +x /root/sync-images.sh
```

#### 3.4.3 执行同步

```bash
# 执行同步脚本
/root/sync-images.sh 2>&1 | tee /root/sync-images.log
```

#### 3.4.4 使用 rsync 增量同步（备选方案）

```bash
# 在美国服务器上导出镜像为 tar 文件
mkdir -p /data/images
for img in "${IMAGES[@]}"; do
    safe_name=$(echo ${img} | tr '/:' '_')
    docker pull ${img}
    docker save ${img} -o /data/images/${safe_name}.tar
done

# 使用 rsync 同步到 Harbor 服务器
rsync -avz --progress /data/images/ root@192.168.1.61:/data/images/

# 在 Harbor 服务器上导入
for f in /data/images/*.tar; do
    docker load -i ${f}
done
```

### 3.5 Trivy 漏洞扫描

#### 3.5.1 手动触发扫描

```bash
# 扫描指定镜像
curl -X POST "http://192.168.1.61/api/v2.0/projects/k8s/repositories/kube-apiserver/artifacts/v1.28.15/scans" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"scan_type": "vulnerability"}'

# 查看扫描结果
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/kube-apiserver/artifacts/v1.28.15/additions/vulnerabilities" \
    -u "admin:Harbor12345" | jq '.vulnerabilities | length'
```

#### 3.5.2 配置自动扫描

```bash
# 在 Harbor Web UI 中配置:
# 1. 系统管理 -> 漏洞扫描 -> 扫描器选择 Trivy
# 2. 项目 -> k8s -> 自动扫描 -> 启用 "推送时自动扫描"
```

#### 3.5.3 配置扫描策略

```bash
# 设置项目漏洞策略：阻止 Critical 级别漏洞的镜像部署
curl -X PUT "http://192.168.1.61/api/v2.0/projects/1/metadatas" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "severity": "critical",
        "reuse_sys_cve_allowlist": false,
        "auto_scan": true
    }'
```

### 3.6 Helm Chart 仓库

#### 3.6.1 推送 Helm Chart

```bash
# 安装 Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 创建示例 Chart
helm create myapp
helm package myapp

# 推送到 Harbor
helm push myapp-0.1.0.tgz oci://192.168.1.61/k8s-charts/myapp

# 或者使用 HTTP 推送方式
curl -X POST "http://192.168.1.61/api/v2.0/projects/k8s-charts/repositories" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"project_name": "k8s-charts", "name": "myapp", "type": "helm_chart"}'
```

#### 3.6.2 添加 Harbor 作为 Helm 仓库

```bash
helm repo add myrepo http://192.168.1.61/chartrepo/k8s-charts \
    --username admin --password Harbor12345
helm repo update
helm search repo myrepo
```

### 3.7 containerd 访问 Harbor 配置

在所有 K8s 节点（192.168.1.51-55）上配置 containerd 访问 Harbor。

```bash
# 配置 containerd 访问 Harbor 的认证信息
mkdir -p /etc/containerd/certs.d/192.168.1.61

cat > /etc/containerd/certs.d/192.168.1.61/hosts.toml << 'EOF'
server = "http://192.168.1.61" # 仓库服务地址

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve", "push"] # 允许的操作
  skip_verify = true # 跳过TLS证书验证
EOF

# 如果使用 HTTPS，配置证书
# mkdir -p /etc/containerd/certs.d/192.168.1.61
# cp harbor.crt /etc/containerd/certs.d/192.168.1.61/ca.crt
```

---

## 4. 配置详解

### 4.1 harbor.yml 完整参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `hostname` | - | Harbor 访问地址（IP 或域名），必填 |
| `http.port` | 80 | HTTP 端口 |
| `https.port` | 443 | HTTPS 端口（启用 HTTPS 时） |
| `harbor_admin_password` | Harbor12345 | 管理员初始密码 |
| `database.password` | - | PostgreSQL 密码 |
| `data_volume` | /data | 数据存储路径 |
| `trivy.ignore_unfixed` | false | 是否忽略无修复方案的漏洞 |
| `jobservice.max_job_workers` | 10 | 并发任务数 |
| `log.level` | info | 日志级别（debug/info/warning/error） |

### 4.2 镜像保留策略

镜像保留策略是 Harbor 的重要功能，用于自动清理旧版本镜像，释放存储空间，同时保留重要的历史版本。

#### 4.2.1 保留策略算法说明

| 算法 | 说明 | 适用场景 |
|------|------|---------|
| **latestPushedK** | 保留最近推送的 K 个 artifact | 持续集成场景，保留最新构建 |
| **latestPulledK** | 保留最近拉取的 K 个 artifact | 生产环境，保留活跃使用的镜像 |
| **nDaysSinceLastPush** | 保留最近 N 天推送的 artifact | 定期清理旧构建 |
| **nDaysSinceLastPull** | 保留最近 N 天拉取的 artifact | 清理不活跃镜像 |
| **always** | 总是保留（永不删除） | 重要基础镜像 |

#### 4.2.2 按标签模式保留

```bash
# 策略1：保留所有 release 标签，清理其他标签
curl -X POST "http://192.168.1.61/api/v2.0/projects/k8s/retentions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "algorithm": "latestPushedK",
        "params": {
            "latestPushedK": 5
        },
        "rule_trigger": {
            "kind": "Schedule",
            "cron": "0 2 * * 0"
        },
        "scope_selectors": [
            {
                "kind": "repository",
                "decoration": "repoMatches",
                "pattern": "**"
            }
        ],
        "tag_selectors": [
            {
                "kind": "doublestar",
                "decoration": "excludes",
                "pattern": "release-*"
            }
        ]
    }'

# 策略2：保留特定标签模式，清理其他
curl -X POST "http://192.168.1.61/api/v2.0/projects/app/retentions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "algorithm": "nDaysSinceLastPush",
        "params": {
            "nDaysSinceLastPush": 30
        },
        "rule_trigger": {
            "kind": "Schedule",
            "cron": "0 3 1 * *"
        },
        "scope_selectors": [
            {
                "kind": "repository",
                "decoration": "repoMatches",
                "pattern": "**"
            }
        ],
        "tag_selectors": [
            {
                "kind": "doublestar",
                "decoration": "excludes",
                "pattern": "{v*,latest,stable,prod*}"
            }
        ]
    }'
```

#### 4.2.3 按时间保留

```bash
# 策略3：保留最近 90 天内推送的镜像
curl -X POST "http://192.168.1.61/api/v2.0/projects/dev/retentions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "algorithm": "nDaysSinceLastPush",
        "params": {
            "nDaysSinceLastPush": 90
        },
        "rule_trigger": {
            "kind": "Schedule",
            "cron": "0 2 * * *"
        },
        "scope_selectors": [
            {
                "kind": "repository",
                "decoration": "repoMatches",
                "pattern": "**"
            }
        ],
        "tag_selectors": [
            {
                "kind": "doublestar",
                "decoration": "matches",
                "pattern": "**"
            }
        ]
    }'

# 策略4：保留最近 30 天内被拉取的镜像（清理不活跃镜像）
curl -X POST "http://192.168.1.61/api/v2.0/projects/test/retentions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "algorithm": "nDaysSinceLastPull",
        "params": {
            "nDaysSinceLastPull": 30
        },
        "rule_trigger": {
            "kind": "Schedule",
            "cron": "0 4 * * 0"
        },
        "scope_selectors": [
            {
                "kind": "repository",
                "decoration": "repoMatches",
                "pattern": "**"
            }
        ],
        "tag_selectors": [
            {
                "kind": "doublestar",
                "decoration": "matches",
                "pattern": "**"
            }
        ]
    }'
```

#### 4.2.4 自动清理旧版本

```bash
# 策略5：多规则组合 - 生产项目保留策略
curl -X POST "http://192.168.1.61/api/v2.0/projects/production/retentions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "algorithm": "latestPushedK",
        "params": {
            "latestPushedK": 20
        },
        "rule_trigger": {
            "kind": "Schedule",
            "cron": "0 1 * * 0"
        },
        "scope_selectors": [
            {
                "kind": "repository",
                "decoration": "repoMatches",
                "pattern": "**"
            }
        ],
        "tag_selectors": [
            {
                "kind": "doublestar",
                "decoration": "excludes",
                "pattern": "{v[0-9]*,latest,stable,release-*,hotfix-*}"
            }
        ]
    }'

# 策略6：开发环境激进清理 - 只保留最近 5 个版本
curl -X POST "http://192.168.1.61/api/v2.0/projects/development/retentions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "algorithm": "latestPushedK",
        "params": {
            "latestPushedK": 5
        },
        "rule_trigger": {
            "kind": "Schedule",
            "cron": "0 2 * * *"
        },
        "scope_selectors": [
            {
                "kind": "repository",
                "decoration": "repoMatches",
                "pattern": "**"
            }
        ],
        "tag_selectors": [
            {
                "kind": "doublestar",
                "decoration": "matches",
                "pattern": "**"
            }
        ]
    }'
```

#### 4.2.5 GC 优化配置

GC（Garbage Collection，垃圾回收）用于清理未被引用的镜像层数据。

```bash
# 查看当前保留策略列表
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/retentions" \
    -u "admin:Harbor12345" | jq '.'

# 手动触发保留策略执行
curl -X POST "http://192.168.1.61/api/v2.0/projects/k8s/retentions/{retention_id}/executions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{}'

# 查看保留策略执行历史
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/retentions/{retention_id}/executions" \
    -u "admin:Harbor12345" | jq '.'

# 手动触发垃圾回收（GC）
curl -X POST "http://192.168.1.61/api/v2.0/system/gc/schedule" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "schedule": {
            "type": "Manual"
        },
        "parameters": {
            "delete_untagged": true,
            "dry_run": false
        }
    }'

# 配置定时 GC
curl -X POST "http://192.168.1.61/api/v2.0/system/gc/schedule" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "schedule": {
            "type": "Custom",
            "cron": "0 3 * * 0"
        },
        "parameters": {
            "delete_untagged": true,
            "dry_run": false
        }
    }'
```

#### 4.2.6 保留策略最佳实践

```yaml
# 保留策略配置建议

# 生产环境 (production)
production_policy:
  algorithm: latestPushedK
  keep_count: 20
  exclude_tags:
    - "v*"           # 保留所有版本标签
    - "latest"       # 保留 latest
    - "stable"       # 保留 stable
    - "release-*"    # 保留发布标签
    - "hotfix-*"     # 保留热修复标签
  schedule: "0 1 * * 0"  # 每周日凌晨1点执行

# 预发布环境 (staging)
staging_policy:
  algorithm: nDaysSinceLastPush
  keep_days: 60
  exclude_tags:
    - "rc*"          # 保留候选版本
    - "beta*"        # 保留测试版本
  schedule: "0 2 * * 0"  # 每周日凌晨2点执行

# 开发环境 (development)
development_policy:
  algorithm: latestPushedK
  keep_count: 5
  exclude_tags:
    - "dev-stable"   # 仅保留 dev-stable
  schedule: "0 2 * * *"  # 每天凌晨2点执行

# 测试环境 (testing)
testing_policy:
  algorithm: nDaysSinceLastPull
  keep_days: 14
  exclude_tags: []
  schedule: "0 3 * * 0"  # 每周日凌晨3点执行
```

**保留策略注意事项：**

1. **先测试后执行**：首次配置时建议启用 `dry_run` 模式，确认清理范围
2. **排除重要标签**：务必配置 `exclude_tags` 避免误删生产镜像
3. **监控清理结果**：定期检查保留策略执行日志，确认清理效果
4. **配合 GC 使用**：保留策略只删除 Tag 引用，需要配合 GC 释放存储空间
5. **备份重要镜像**：清理前确保重要镜像已备份或复制到其他项目

### 4.3 Harbor 复制规则（Harbor 原生同步）

```bash
# 创建复制目标（远端 Harbor 或 Docker Hub）
curl -X POST "http://192.168.1.61/api/v2.0/registries" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "name": "docker-hub-proxy",
        "description": "Docker Hub 代理",
        "url": "https://hub.docker.com",
        "credential": {
            "type": "basic",
            "access_key": "admin",
            "access_secret": "Harbor12345"
        },
        "type": "docker-hub",
        "insecure": false
    }'

# 创建复制规则
curl -X POST "http://192.168.1.61/api/v2.0/projects/1/replication/rules" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "name": "sync-from-docker-hub",
        "description": "从 Docker Hub 同步镜像",
        "src_registry": 1,
        "dest_registry": 1,
        "dest_namespace": "library",
        "trigger": {
            "type": "scheduled",
            "trigger_settings": {
                "cron": "0 3 * * *"
            }
        },
        "filters": [
            {
                "type": "name",
                "value": "**"
            },
            {
                "type": "tag",
                "value": "latest"
            }
        ],
        "deletion": false,
        "enabled": true
    }'
```

---

## 5. 镜像漏洞扫描(Trivy)深度实践

### 5.1 镜像安全扫描概述

容器镜像安全扫描是云原生安全体系的第一道防线。Trivy 作为 Aqua Security 开源的容器安全扫描器，被 Harbor 集成作为默认扫描引擎。

**扫描范围：**

| 扫描类型 | 说明 | 覆盖范围 |
|---------|------|---------|
| **OS 包漏洞** | 操作系统层面的软件包漏洞 | Alpine/Debian/Ubuntu/CentOS/RHEL 等 |
| **应用依赖漏洞** | 编程语言依赖库漏洞 | npm/pip/gem/maven/nuget 等 |
| **配置错误** | 容器镜像配置安全问题 | Dockerfile 最佳实践检查 |
| **密钥泄露** | 检测硬编码密钥和密码 | AWS/Azure/GCP 凭证、私钥等 |

**漏洞等级定义：**

```
CRITICAL (严重)    - 可被远程利用，可能导致系统完全控制
HIGH (高危)        - 可被利用，可能导致数据泄露或服务中断
MEDIUM (中危)      - 需要特定条件才能利用
LOW (低危)         - 影响较小，建议修复
UNKNOWN (未知)     - 暂无足够信息评估
```

**Trivy 扫描架构图：**

```
+------------------+     +------------------+     +------------------+
|   Harbor Core    |     |   Job Service    |     |   Trivy Scanner  |
|   (API/策略)     |---->|   (任务调度)     |---->|   (漏洞扫描)     |
+------------------+     +------------------+     +------------------+
         |                                               |
         |                                               v
         |                                      +------------------+
         |                                      |  Trivy DB        |
         |                                      |  (漏洞数据库)    |
         v                                      +------------------+
+------------------+                                      |
|  PostgreSQL      |<-------------------------------------+
|  (扫描结果存储)   |
+------------------+
```

### 5.2 Trivy 离线部署与漏洞数据库管理

在离线环境中，Trivy 需要手动维护漏洞数据库。

#### 5.2.1 离线漏洞数据库准备

```bash
# 在有网络的环境中下载 Trivy DB
trivy db download --output /data/trivy-db.tar.gz

# 或者分别下载漏洞数据库和 Java 数据库
trivy db download --db-repository ghcr.io/aquasecurity/trivy-db
trivy java-db download --java-db-repository ghcr.io/aquasecurity/trivy-java-db

# 查看数据库版本信息
trivy db status
```

#### 5.2.2 Harbor 集成 Trivy 离线配置

```yaml
# harbor.yml 中 Trivy 离线配置
trivy:
  # 是否跳过数据库更新（离线环境必须设为 true）
  skip_update: true
  
  # 离线扫描模式
  offline_scan: true
  
  # 漏洞数据库路径（挂载到容器内）
  db_path: /home/scanner/.cache/trivy/db # 漏洞数据库路径
  
  # Java 数据库路径
  java_db_path: /home/scanner/.cache/trivy/java-db # Java漏洞数据库
  
  # 忽略无修复方案的漏洞
  ignore_unfixed: false
  
  # 安全检查类型
  security_check: vuln,config,secret # 漏洞、配置、密钥检查
  
  # 漏洞等级过滤
  severity: UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL # 扫描的漏洞等级
  
  # 是否跳过证书验证
  insecure: false
```

#### 5.2.3 离线数据库导入脚本

```bash
#!/bin/bash
# 离线 Trivy 数据库更新脚本
# 在 Harbor 服务器上执行

TRIVY_DB_VERSION="v2"
DB_SOURCE="/data/trivy-offline-db"
HARBOR_PATH="/opt/harbor"

# 创建数据库目录
mkdir -p ${DB_SOURCE}

# 从外部导入数据库（通过 U 盘或内部网络传输）
# 假设数据库文件已放置在 /data/trivy-offline-db/

# 停止 Trivy 服务
cd ${HARBOR_PATH}
docker compose stop trivy-adapter

# 复制数据库到 Trivy 容器
docker cp ${DB_SOURCE}/trivy.db $(docker compose ps -q trivy-adapter):/home/scanner/.cache/trivy/db/
docker cp ${DB_SOURCE}/metadata.json $(docker compose ps -q trivy-adapter):/home/scanner/.cache/trivy/db/

# 设置权限
docker compose exec trivy-adapter chown -R scanner:scanner /home/scanner/.cache/trivy

# 重启 Trivy 服务
docker compose start trivy-adapter

echo "Trivy 数据库更新完成"
echo "当前数据库版本:"
docker compose exec trivy-adapter trivy db status
```

#### 5.2.4 自动化数据库同步（内网环境）

```bash
#!/bin/bash
# 内网环境 Trivy 数据库同步脚本
# 部署在内网镜像服务器上

LOCAL_DB_PATH="/data/trivy-db"
HARBOR_SERVERS=("192.168.1.61" "192.168.1.62" "192.168.1.63")

# 从内部镜像源下载最新数据库
# 假设内部有 Trivy DB 镜像服务器
curl -o ${LOCAL_DB_PATH}/trivy-db-latest.tar.gz \
    http://internal-mirror.company.com/trivy-db/latest.tar.gz

# 分发到所有 Harbor 节点
for server in "${HARBOR_SERVERS[@]}"; do
    echo "Updating Trivy DB on ${server}..."
    scp ${LOCAL_DB_PATH}/trivy-db-latest.tar.gz root@${server}:/tmp/
    ssh root@${server} "bash /opt/harbor/update-trivy-db.sh"
done

echo "All Harbor nodes updated successfully"
```

### 5.3 Harbor 集成 Trivy 扫描器

#### 5.3.1 安装时启用 Trivy

```bash
# 标准安装（在线模式）
./install.sh --with-trivy

# 离线安装
./install.sh --with-trivy --offline
```

#### 5.3.2 手动配置 Trivy 扫描器

```bash
# 通过 API 注册 Trivy 扫描器
curl -X POST "http://192.168.1.61/api/v2.0/scanners" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "name": "Trivy-Offline",
        "description": "Offline Trivy Scanner",
        "url": "http://trivy-adapter:8080",
        "auth": "",
        "access_credential": "",
        "skip_cert_verify": false,
        "use_internal_addr": true,
        "is_default": true
    }'

# 查看已注册的扫描器
curl -s "http://192.168.1.61/api/v2.0/scanners" \
    -u "admin:Harbor12345" | jq '.[] | {name, url, is_default}'
```

#### 5.3.3 项目级扫描配置

```bash
# 为项目启用自动扫描
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/auto_scan" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"auto_scan": "true"}'

# 配置项目使用特定扫描器
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/scanner" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"scanner": "Trivy-Offline"}'
```

### 5.4 扫描策略配置（阻止高危漏洞推送）

#### 5.4.1 系统级漏洞策略

```bash
# 配置系统级 CVE 白名单
curl -X PUT "http://192.168.1.61/api/v2.0/system/CVEAllowlist" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "items": [
            {"cve_id": "CVE-2023-1234"},
            {"cve_id": "CVE-2023-5678"}
        ],
        "expires_at": null,
        "project_id": 0
    }'
```

#### 5.4.2 项目级阻止策略

```bash
# 配置项目阻止策略：阻止 Critical 和 High 级别漏洞
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/severity" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"severity": "high"}'

# 配置阻止策略生效范围
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/prevent_vul" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"prevent_vul": "true"}'

# 配置是否允许使用系统白名单
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/reuse_sys_cve_allowlist" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"reuse_sys_cve_allowlist": "false"}'
```

#### 5.4.3 完整策略配置示例

```yaml
# 项目漏洞策略配置示例
project: k8s
policies:
  # 自动扫描配置
  auto_scan:
    enabled: true
    trigger: on_push  # 推送时触发扫描
  
  # 阻止策略
  prevention:
    enabled: true
    severity_threshold: high  # 阻止高危及以上漏洞
    allowlist: # CVE白名单
      use_system: false
      project_specific:
        - CVE-2023-1234
        - CVE-2023-5678
  
  # 扫描范围
  scan_scope:
    - os_packages # 操作系统包漏洞
    - application_dependencies # 应用依赖漏洞
    - secrets # 密钥泄露检测
    - misconfigurations # 配置错误检测
```

#### 5.4.4 测试阻止策略

```bash
# 推送一个包含高危漏洞的镜像
docker pull vulnimage/nginx:1.18.0
docker tag vulnimage/nginx:1.18.0 192.168.1.61/k8s/nginx:vulnerable
docker push 192.168.1.61/k8s/nginx:vulnerable

# 预期结果：推送被阻止，返回错误信息
# denied: The image is not scanned or the scan result does not meet the requirement
```

### 5.5 扫描报告查看与分析

#### 5.5.1 通过 API 获取扫描结果

```bash
# 获取镜像扫描摘要
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts/latest" \
    -u "admin:Harbor12345" | jq '.scan_overview'

# 获取详细漏洞列表
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts/latest/additions/vulnerabilities" \
    -u "admin:Harbor12345" | jq '.'

# 统计各等级漏洞数量
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts/latest/additions/vulnerabilities" \
    -u "admin:Harbor12345" | jq '
    .vulnerabilities | 
    group_by(.severity) | 
    map({severity: .[0].severity, count: length}) | 
    sort_by(.count) | reverse
'
```

#### 5.5.2 扫描报告导出

```bash
#!/bin/bash
# 扫描报告导出脚本

PROJECT="k8s"
REPO="nginx"
TAG="latest"
OUTPUT_DIR="/data/scan-reports"

mkdir -p ${OUTPUT_DIR}

# 导出 JSON 格式报告
curl -s "http://192.168.1.61/api/v2.0/projects/${PROJECT}/repositories/${REPO}/artifacts/${TAG}/additions/vulnerabilities" \
    -u "admin:Harbor12345" > ${OUTPUT_DIR}/${PROJECT}_${REPO}_${TAG}_scan.json

# 生成 CSV 格式报告
cat ${OUTPUT_DIR}/${PROJECT}_${REPO}_${TAG}_scan.json | jq -r '
    .vulnerabilities[] | 
    [.id, .severity, .package, .version, .fix_version, .description[:100]] | 
    @csv
' > ${OUTPUT_DIR}/${PROJECT}_${REPO}_${TAG}_scan.csv

echo "Scan report exported to ${OUTPUT_DIR}"
```

#### 5.5.3 扫描结果分析

```bash
# 分析最严重的漏洞
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts/latest/additions/vulnerabilities" \
    -u "admin:Harbor12345" | jq '
    .vulnerabilities | 
    map(select(.severity == "CRITICAL" or .severity == "HIGH")) |
    group_by(.package) |
    map({package: .[0].package, count: length, max_severity: (. | max_by(.severity) | .severity)})
'

# 查找可修复的漏洞
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts/latest/additions/vulnerabilities" \
    -u "admin:Harbor12345" | jq '
    .vulnerabilities | 
    map(select(.fix_version != "" and .fix_version != null))
'
```

### 5.6 漏洞修复流程

#### 5.6.1 修复流程图

```
+----------------+     +----------------+     +----------------+
|  发现漏洞      |---->|  评估影响      |---->|  制定修复计划  |
+----------------+     +----------------+     +----------------+
                                                      |
+----------------+     +----------------+     +----------------+
|  验证修复      |<----|  重新扫描      |<----|  更新镜像      |
+----------------+     +----------------+     +----------------+
```

#### 5.6.2 常见漏洞修复方法

```dockerfile
# 示例：修复基础镜像漏洞

# 问题镜像
FROM nginx:1.18.0

# 修复方案 1：升级到最新补丁版本
FROM nginx:1.25.3-alpine # 使用Alpine精简基础镜像

# 修复方案 2：手动更新软件包
FROM nginx:1.18.0
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

# 修复方案 3：使用最小化基础镜像
FROM nginx:alpine-slim

# 修复方案 4：多阶段构建（Multi-stage Build），减少攻击面
FROM node:18-alpine AS builder # 构建阶段
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine # 运行阶段
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
USER node # 以非root用户运行
EXPOSE 3000 # 应用端口
CMD ["node", "server.js"]
```

#### 5.6.3 自动化修复流水线

```yaml
# .gitlab-ci.yml 示例
stages:
  - build
  - scan
  - fix
  - push

build:
  stage: build
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

scan:
  stage: scan
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  allow_failure: true

auto_fix:
  stage: fix
  script:
    # 如果扫描失败，尝试自动更新基础镜像
    - sed -i 's/FROM nginx:1.18.0/FROM nginx:alpine/' Dockerfile
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA-fixed .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA-fixed
  when: on_failure

push_fixed:
  stage: push
  script:
    - docker tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA-fixed $CI_REGISTRY_IMAGE:latest
    - docker push $CI_REGISTRY_IMAGE:latest
  when: on_success
```

---

## 6. 验证与测试

### 5.1 验证 Harbor 服务

```bash
# 检查所有容器运行状态
docker compose -f /opt/harbor/docker-compose.yml ps

# 检查 Harbor 健康状态
curl -s http://192.168.1.61/api/v2.0/health -u "admin:Harbor12345"

# 检查各组件状态
docker compose -f /opt/harbor/docker-compose.yml logs --tail=20 core
docker compose -f /opt/harbor/docker-compose.yml logs --tail=20 trivy
```

### 5.2 验证镜像推送/拉取

```bash
# 登录
docker login 192.168.1.61 -u admin -p Harbor12345

# 拉取测试镜像
docker pull 192.168.1.61/library/busybox:latest

# 打 tag
docker tag busybox:latest 192.168.1.61/library/busybox:latest

# 推送
docker push 192.168.1.61/library/busybox:latest

# 验证
curl -s "http://192.168.1.61/api/v2.0/projects/library/repositories/busybox/artifacts" \
    -u "admin:Harbor12345" | jq '.[0].tags[0].name'
# 预期输出: "latest"
```

### 5.3 验证 Trivy 扫描

```bash
# 查看扫描结果
curl -s "http://192.168.1.61/api/v2.0/projects/library/repositories/busybox/artifacts/latest/additions/vulnerabilities" \
    -u "admin:Harbor12345" | jq '.vulnerabilities | length'
```

### 5.4 验证 K8s 节点访问 Harbor

```bash
# 在 K8s 节点上使用 crictl 测试
crictl pull 192.168.1.61/library/busybox:latest

# 验证镜像已下载
crictl images | grep busybox
```

---

## 7. 镜像签名与验证(Cosign)深度实践

### 7.1 供应链安全概述

软件供应链攻击是近年来增长最快的安全威胁之一。镜像签名机制确保从构建到部署的完整链路可信。

**供应链攻击场景：**

```
+----------------+     +----------------+     +----------------+
|   源码仓库     |     |   构建环境     |     |   镜像仓库     |
|  (GitHub)      |---->|  (CI/CD)       |---->|  (Harbor)      |
+----------------+     +----------------+     +----------------+
        |                       |                       |
        v                       v                       v
   恶意代码注入           构建工具篡改           镜像替换攻击
```

**镜像签名价值：**

| 安全需求 | 说明 | 签名机制作用 |
|---------|------|-------------|
| **来源验证** | 确认镜像来自可信构建系统 | 私钥签名证明来源 |
| **完整性** | 确保镜像未被篡改 | 哈希值签名绑定 |
| **不可否认** | 构建者无法否认发布行为 | 数字签名特性 |
| **可追溯** | 关联镜像与构建记录 | 签名元数据存储 |

**Cosign vs Notary 对比：**

| 特性 | Cosign | Notary (DCT) |
|------|--------|--------------|
| 项目归属 | Sigstore (Linux Foundation) | Docker (已归档) |
| 密钥管理 | 支持 KMS（密钥管理服务）、HashiCorp Vault | 本地密钥或 Notary Server |
| 密钥less | 支持 Fulcio 临时密钥 | 不支持 |
| 透明度日志 | 支持 Rekor（透明度日志） | 不支持 |
| Harbor 集成 | v2.5+ 原生支持 | v2.x 仍支持 |
| 离线支持 | 完整支持 | 完整支持 |
| 推荐使用 | 是 | 否（已过时） |

### 7.2 Cosign 离线安装与密钥生成

#### 7.2.1 离线安装 Cosign

```bash
# 在有网络的环境中下载 Cosign
wget https://github.com/sigstore/cosign/releases/download/v2.2.0/cosign-linux-amd64
wget https://github.com/sigstore/cosign/releases/download/v2.2.0/cosign-linux-amd64.sig

# 验证下载（可选）
cosign verify-blob \
    --certificate-identity-regexp "^https://github.com/sigstore/cosign/.*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    --signature cosign-linux-amd64.sig \
    --certificate cosign-linux-amd64.crt \
    cosign-linux-amd64

# 传输到离线环境并安装
chmod +x cosign-linux-amd64
mv cosign-linux-amd64 /usr/local/bin/cosign
cosign version
```

#### 7.2.2 生成签名密钥对

```bash
# 生成 Cosign 密钥对（离线环境）
export COSIGN_PASSWORD="YourSecurePassword123"
cosign generate-key-pair

# 生成文件：
# cosign.key  - 私钥（严格保密）
# cosign.pub  - 公钥（分发到验证端）

# 查看公钥内容
cat cosign.pub
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
-----END PUBLIC KEY-----
```

#### 7.2.3 使用 KMS 管理密钥（生产环境推荐）

```bash
# AWS KMS 示例
cosign generate-key-pair --kms awskms:///alias/harbor-signing-key

# HashiCorp Vault 示例
cosign generate-key-pair --kms hashivault://harbor-signing-key

# 本地 PKCS#11 HSM 示例
cosign generate-key-pair --kms pkcs11://"module=/usr/lib/softhsm/libsofthsm2.so;token=harbor;pin-value=1234"
```

#### 7.2.4 密钥安全存储

```bash
#!/bin/bash
# 密钥安全管理脚本

KEY_DIR="/etc/harbor/cosign-keys"
mkdir -p ${KEY_DIR}
chmod 700 ${KEY_DIR}

# 生成密钥
cosign generate-key-pair --output-key-prefix ${KEY_DIR}/harbor-prod

# 设置严格权限
chmod 600 ${KEY_DIR}/harbor-prod.key
chmod 644 ${KEY_DIR}/harbor-prod.pub
chown -R root:root ${KEY_DIR}

# 备份私钥（加密存储到安全位置）
gpg --symmetric --cipher-algo AES256 --output ${KEY_DIR}/harbor-prod.key.gpg ${KEY_DIR}/harbor-prod.key

# 删除明文私钥（使用时解密）
shred -u ${KEY_DIR}/harbor-prod.key

echo "Keys generated and secured in ${KEY_DIR}"
```

### 7.3 镜像签名流程

#### 7.3.1 基础签名操作

```bash
# 对镜像进行签名
cosign sign --key cosign.key 192.168.1.61/k8s/nginx:1.25.3

# 使用环境变量传递私钥密码
export COSIGN_PASSWORD="YourSecurePassword123"
cosign sign --key cosign.key 192.168.1.61/k8s/nginx:1.25.3

# 签名并附加元数据
cosign sign --key cosign.key \
    --annotations "built-by=jenkins" \
    --annotations "build-id=12345" \
    --annotations "git-commit=abc123" \
    192.168.1.61/k8s/nginx:1.25.3
```

#### 7.3.2 CI/CD 流水线签名集成

```yaml
# Jenkins Pipeline 示例
pipeline {
    agent any
    environment {
        COSIGN_PASSWORD = credentials('cosign-key-password')
        HARBOR_ADDR = '192.168.1.61'
    }
    stages {
        stage('Build') {
            steps {
                script {
                    docker.build("${HARBOR_ADDR}/k8s/myapp:${BUILD_NUMBER}")
                }
            }
        }
        stage('Push') {
            steps {
                script {
                    docker.withRegistry("http://${HARBOR_ADDR}", 'harbor-credentials') {
                        docker.image("${HARBOR_ADDR}/k8s/myapp:${BUILD_NUMBER}").push()
                    }
                }
            }
        }
        stage('Sign') {
            steps {
                withCredentials([file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY')]) {
                    sh """
                        cosign sign --key ${COSIGN_KEY} \
                            --annotations "build-number=${BUILD_NUMBER}" \
                            --annotations "git-commit=${GIT_COMMIT}" \
                            --annotations "built-by=jenkins" \
                            ${HARBOR_ADDR}/k8s/myapp:${BUILD_NUMBER}
                    """
                }
            }
        }
    }
}
```

#### 7.3.3 GitLab CI 签名示例

```yaml
# .gitlab-ci.yml
stages:
  - build
  - push
  - sign

variables:
  HARBOR_ADDR: "192.168.1.61"
  IMAGE_NAME: "$HARBOR_ADDR/k8s/$CI_PROJECT_NAME"

build:
  stage: build
  script:
    - docker build -t $IMAGE_NAME:$CI_COMMIT_SHA .

push:
  stage: push
  script:
    - docker login $HARBOR_ADDR -u $HARBOR_USER -p $HARBOR_PASSWORD
    - docker push $IMAGE_NAME:$CI_COMMIT_SHA
    - docker tag $IMAGE_NAME:$CI_COMMIT_SHA $IMAGE_NAME:latest
    - docker push $IMAGE_NAME:latest

sign:
  stage: sign
  variables:
    COSIGN_PASSWORD: $COSIGN_KEY_PASSWORD
  script:
    - cosign sign --key <(echo "$COSIGN_PRIVATE_KEY") \\
        --annotations "gitlab-project=$CI_PROJECT_PATH" \\
        --annotations "commit-sha=$CI_COMMIT_SHA" \\
        $IMAGE_NAME:$CI_COMMIT_SHA
    - cosign sign --key <(echo "$COSIGN_PRIVATE_KEY") $IMAGE_NAME:latest
  only:
    - main
```

#### 7.3.4 批量签名脚本

```bash
#!/bin/bash
# 批量签名 Harbor 镜像脚本

HARBOR_ADDR="192.168.1.61"
PROJECT="k8s"
COSIGN_KEY="/etc/harbor/cosign-keys/harbor-prod.key"
export COSIGN_PASSWORD="${COSIGN_KEY_PASSWORD}"

# 获取项目下所有镜像
REPOS=$(curl -s "http://${HARBOR_ADDR}/api/v2.0/projects/${PROJECT}/repositories" \
    -u "admin:Harbor12345" | jq -r '.[].name')

for repo in $REPOS; do
    # 获取镜像的所有 tag
    TAGS=$(curl -s "http://${HARBOR_ADDR}/api/v2.0/projects/${PROJECT}/repositories/${repo}/artifacts" \
        -u "admin:Harbor12345" | jq -r '.[].tags[].name')
    
    for tag in $TAGS; do
        IMAGE="${HARBOR_ADDR}/${PROJECT}/${repo}:${tag}"
        echo "Signing: ${IMAGE}"
        
        # 检查是否已签名
        if cosign verify --key cosign.pub ${IMAGE} >/dev/null 2>&1; then
            echo "  Already signed, skipping"
        else
            cosign sign --key ${COSIGN_KEY} ${IMAGE}
            echo "  Signed successfully"
        fi
    done
done
```

### 7.4 Harbor 验证签名策略

#### 7.4.1 配置 Cosign 公钥

```bash
# 在 Harbor 中配置签名策略
# 1. 进入项目 -> 策略 -> 内容信任
# 2. 上传 Cosign 公钥
# 3. 启用签名验证

# 通过 API 配置签名策略
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/cosign" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "cosign": {
            "enabled": true,
            "public_keys": [
                {
                    "name": "production-key",
                    "content": "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...\n-----END PUBLIC KEY-----"
                }
            ]
        }
    }'
```

#### 7.4.2 配置强制签名策略

```bash
# 启用强制签名验证
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/enable_content_trust_cosign" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"enable_content_trust_cosign": "true"}'

# 配置签名验证失败时阻止拉取
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/strict_cosign" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"strict_cosign": "true"}'
```

#### 7.4.3 Kubernetes Admission Controller 集成

```yaml
# Kyverno 策略示例：强制验证镜像签名
apiVersion: kyverno.io/v1
kind: ClusterPolicy # 集群级别策略
metadata:
  name: verify-image-signatures
spec:
  validationFailureAction: enforce # 不满足策略时拒绝
  background: false
  rules:
    - name: verify-cosign-signature
      match:
        resources:
          kinds:
            - Pod
      verifyImages:
        - imageReferences:
            - "192.168.1.61/k8s/*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                      -----END PUBLIC KEY-----
```

```yaml
# OPA Gatekeeper 策略示例
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate # 约束模板
metadata:
  name: k8srequiredcosignsignature
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredCosignSignature # 约束资源类型
  targets:
    - target: admission.k8s.gatekeeper.sh # 准入控制目标
      rego: |
        package k8srequiredcosignsignature
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          image := container.image
          startswith(image, "192.168.1.61/k8s/")
          not cosign_verify(image)
          msg := sprintf("Container image %s is not signed with Cosign", [image])
        }
        
        cosign_verify(image) {
          # 调用 Cosign 验证
          # 实际实现需要配合 Cosign 验证服务
          data.cosign.verified_images[image]
        }
```

### 7.5 签名密钥管理

#### 7.5.1 密钥轮换策略

```bash
#!/bin/bash
# 密钥轮换脚本

KEY_DIR="/etc/harbor/cosign-keys"
OLD_KEY_PREFIX="harbor-prod"
NEW_KEY_PREFIX="harbor-prod-$(date +%Y%m%d)"

# 1. 生成新密钥对
cosign generate-key-pair --output-key-prefix ${KEY_DIR}/${NEW_KEY_PREFIX}

# 2. 使用新旧密钥同时签名（过渡期）
# 新推送的镜像使用新密钥签名
# 同时保留旧密钥用于验证历史镜像

# 3. 更新 Harbor 配置，添加新公钥
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/cosign" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d "{
        \"cosign\": {
            \"enabled\": true,
            \"public_keys\": [
                {\"name\": \"production-key-v1\", \"content\": \"$(cat ${KEY_DIR}/${OLD_KEY_PREFIX}.pub)\"},
                {\"name\": \"production-key-v2\", \"content\": \"$(cat ${KEY_DIR}/${NEW_KEY_PREFIX}.pub)\"}
            ]
        }
    }"

# 4. 重新签名重要镜像
for image in "nginx:1.25.3" "redis:7-alpine"; do
    cosign sign --key ${KEY_DIR}/${NEW_KEY_PREFIX}.key 192.168.1.61/k8s/${image}
done

# 5. 验证期后，移除旧密钥
echo "Key rotation completed. Old key will be deprecated in 30 days."
```

#### 7.5.2 多环境密钥管理

```
密钥层级结构：

/etc/harbor/cosign-keys/
├── production/
│   ├── harbor-prod.key      # 生产环境私钥（加密存储）
│   ├── harbor-prod.pub      # 生产环境公钥
│   └── harbor-prod.key.gpg  # 加密备份
├── staging/
│   ├── harbor-staging.key
│   └── harbor-staging.pub
└── development/
    ├── harbor-dev.key
    └── harbor-dev.pub
```

```bash
# 多环境签名脚本
#!/bin/bash

ENV=${1:-development}
IMAGE=$2
TAG=$3

KEY_DIR="/etc/harbor/cosign-keys/${ENV}"
KEY_PREFIX="harbor-${ENV}"

# 解密私钥
gpg --decrypt --output ${KEY_DIR}/${KEY_PREFIX}.key ${KEY_DIR}/${KEY_PREFIX}.key.gpg

# 签名镜像
export COSIGN_PASSWORD=$(cat /run/secrets/cosign-password-${ENV})
cosign sign --key ${KEY_DIR}/${KEY_PREFIX}.key 192.168.1.61/${ENV}/${IMAGE}:${TAG}

# 删除解密后的私钥
shred -u ${KEY_DIR}/${KEY_PREFIX}.key

echo "Image signed for ${ENV} environment"
```

### 7.6 生产环境签名验证

#### 7.6.1 客户端验证

```bash
# 验证镜像签名
cosign verify --key cosign.pub 192.168.1.61/k8s/nginx:1.25.3

# 验证并显示签名元数据
cosign verify --key cosign.pub \
    --output json \
    192.168.1.61/k8s/nginx:1.25.3 | jq .

# 验证特定注解
cosign verify --key cosign.pub \
    --annotations "built-by=jenkins" \
    192.168.1.61/k8s/nginx:1.25.3
```

#### 7.6.2 自动化验证脚本

```bash
#!/bin/bash
# 镜像签名验证脚本（用于部署前检查）

HARBOR_ADDR="192.168.1.61"
IMAGE=$1
PUBLIC_KEY="/etc/harbor/cosign-keys/harbor-prod.pub"

echo "Verifying signature for: ${IMAGE}"

# 执行验证
if cosign verify --key ${PUBLIC_KEY} ${IMAGE} >/dev/null 2>&1; then
    echo "[PASS] Signature verification successful"
    
    # 获取签名信息
    cosign verify --key ${PUBLIC_KEY} --output json ${IMAGE} | jq '.[0] | {
        digest: .critical.image.docker-manifest-digest,
        annotations: .optional
    }'
    exit 0
else
    echo "[FAIL] Signature verification failed"
    echo "Image ${IMAGE} is not signed or signature is invalid"
    exit 1
fi
```

#### 7.6.3 与 Helm Chart 签名集成

```bash
# 签名 Helm Chart
cosign sign-blob \
    --key cosign.key \
    --output-signature myapp-1.0.0.tgz.sig \
    myapp-1.0.0.tgz

# 验证 Helm Chart 签名
cosign verify-blob \
    --key cosign.pub \
    --signature myapp-1.0.0.tgz.sig \
    myapp-1.0.0.tgz

# 推送到 Harbor Helm 仓库
helm push myapp-1.0.0.tgz oci://192.168.1.61/k8s-charts
```

---

## 8. CKA/CKS 考点融入

### 6.1 CKS 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 镜像安全扫描 | 使用 Trivy 扫描镜像漏洞 | 3.5 节 |
| 私有仓库认证 | 配置 containerd 访问私有仓库 | 3.7 节 |
| 镜像签名验证 | Notary/DCT 内容信任 | 2.2 节 |
| 最小基础镜像 | 使用 distroless/alpine 镜像 | 3.4 节 |

### 6.2 考试技巧

1. CKS 中常考 `trivy image` 命令行扫描，记住关键参数：`trivy image --severity HIGH,CRITICAL <image>`
2. containerd 配置私有仓库认证是 CKS 必考题，注意 hosts.toml 的格式
3. 镜像签名使用 `cosign` 或 `notary`，了解签名和验证流程

---

## 9. 高频面试题

### Q1: Harbor 的架构是怎样的？各组件的作用是什么？ [难度: 中]

**答案：** Harbor 采用微服务架构，核心组件包括：Nginx/Proxy 作为统一入口，负责反向代理和路由分发，所有请求通过 80/443 端口进入；Harbor Core 是核心业务逻辑层，提供 RESTful API，处理用户认证、项目管理、权限控制、复制策略等；Portal 是基于 Vue.js 的 Web 管理界面；Registry 是基于 Docker Distribution v2 的镜像存储后端，实际存储镜像的 Manifest 和 Layer；JobService 负责执行异步任务，如镜像复制、垃圾回收、漏洞扫描等；Trivy 是集成的漏洞扫描引擎，支持扫描 OS 包和应用依赖的 CVE；PostgreSQL 存储元数据（用户、项目、策略、扫描结果）；Redis 作为缓存层，存储会话信息和 Job 状态。所有组件通过 Docker Compose 编排部署，共享一个 Docker 网络。Harbor 的设计遵循云原生原则，每个组件可以独立扩展。

### Q2: Harbor 如何实现镜像的漏洞扫描？Trivy 的工作原理是什么？ [难度: 中]

**答案：** Harbor 集成了 Trivy 作为默认漏洞扫描器。扫描流程为：用户推送镜像到 Harbor 后，JobService 会自动（或手动）触发 Trivy 扫描任务；Trivy 解析镜像的 Manifest，逐层下载并解压文件系统；然后扫描 OS 包（dpkg/apk/rpm）和应用依赖（npm/pip/gem/maven 等），将包名和版本与 Trivy 内置的 CVE 数据库进行比对；扫描结果以 JSON 格式返回给 JobService，存储到 PostgreSQL 中。Trivy 的优势在于：扫描速度快（并行扫描）、支持多种语言生态、数据库更新频繁（每 6 小时）、资源消耗低。在 Harbor 中可以配置自动扫描策略（推送时/定时扫描），并设置漏洞阻止策略（如 Critical 级别漏洞阻止部署）。扫描结果可以在 Web UI 中查看，也支持通过 API 获取。

### Q3: 如何配置 containerd 使用 Harbor 私有仓库？ [难度: 中]

**答案：** containerd v1.7+ 使用 `/etc/containerd/certs.d/<registry>/hosts.toml` 文件配置镜像仓库。配置步骤为：首先创建目录 `mkdir -p /etc/containerd/certs.d/192.168.1.61`，然后创建 hosts.toml 文件，指定 server 地址和认证方式。如果 Harbor 使用 HTTP（无 TLS），需要配置 `skip_verify = true` 并使用 `http://` 协议。认证信息可以通过两种方式提供：一是直接在 hosts.toml 中配置 `[host."http://192.168.1.61"]` 段落并设置 `capabilities = ["pull", "resolve"]`；二是通过 `ctr -n k8s.io images pull --user username:password` 命令认证后，containerd 会自动缓存凭据。在 K8s 环境中，还可以通过创建 `imagePullSecrets`（包含 `.dockerconfigjson`）来为 Pod 提供仓库认证信息，这种方式更适合多租户环境。

### Q4: Harbor 的镜像复制机制是怎样的？ [难度: 高]

**答案：** Harbor 支持两种复制模式：Push 模式和 Pull 模式。Push 模式下，源 Harbor 主动将镜像推送到目标 Harbor；Pull 模式下，目标 Harbor 主动从源 Harbor 拉取镜像。复制流程为：用户创建复制规则，指定源/目标仓库、过滤条件（名称/标签模式匹配）和触发方式（手动/定时/事件驱动）；JobService 根据规则创建复制任务；任务执行时，Registry 会先拉取源镜像的 Manifest，然后逐层下载 Blob 数据并推送到目标仓库。Harbor v2.x 支持增量复制，只同步变化的层，大幅提升效率。复制规则支持多种过滤条件：按名称模式匹配（如 `**/nginx**`）、按标签正则匹配、按资源类型过滤（image/chart）。在大规模场景下，建议使用独立的 JobService 节点，避免复制任务影响主服务性能。

### Q5: 什么是 Helm Chart 仓库？Harbor 如何支持？ [难度: 中]

**答案：** Helm Chart 仓库是用于存储和分发 Helm Chart 的服务。Helm Chart 是 Kubernetes 应用的打包格式，包含一组预定义的 Kubernetes 资源模板和默认值。Harbor v2.x 原生支持 Helm Chart 仓库功能，每个 Harbor 项目都可以作为独立的 Chart 仓库。使用方式有两种：一是通过 Helm OCI 推送（推荐），使用 `helm push chart.tgz oci://harbor-address/project/chart-name` 命令，Harbor 会自动解析并存储 Chart；二是通过 HTTP API 推送，使用 `helm cm-push` 插件。在消费端，通过 `helm repo add` 添加 Harbor 仓库地址，然后 `helm install` 即可安装 Chart。Harbor 还支持 Chart 的版本管理、搜索和漏洞扫描。在 CI/CD 流水线中，通常将 Helm Chart 推送到 Harbor，然后通过 ArgoCD/Flux 从 Harbor 拉取并部署。

### Q6: Harbor 如何实现垃圾回收（GC）？ [难度: 中]

**答案：** Harbor 的垃圾回收（Garbage Collection，GC）用于清理未被任何镜像 Tag 引用的 Blob 数据，释放存储空间。工作原理为：Registry 使用 Content Addressable Storage（CAS，内容可寻址存储），每个 Blob 通过 SHA256 摘要唯一标识；当用户删除镜像 Tag 时，Registry 只是删除了 Tag 到 Manifest 的引用，实际的 Blob 数据仍然保留在磁盘上；GC 时，Registry 会遍历所有 Manifest，标记被引用的 Blob，然后删除未被标记的 Blob。执行 GC 的步骤为：首先在 Web UI 中执行"垃圾回收"或通过 API 触发；JobService 会先运行一个"标记"阶段，识别所有未引用的 Blob；然后运行"清除"阶段，删除标记的 Blob。注意：GC 期间 Registry 会进入只读模式，建议在低峰期执行。生产环境中建议配置定时 GC（如每周一次），并配合镜像保留策略自动清理旧版本。

### Q7: 如何实现从海外服务器到国内 Harbor 的镜像同步？ [难度: 高]

**答案：** 海外到国内的镜像同步有三种方案。方案一（推荐）：在美国云服务器上使用脚本批量拉取镜像、打 tag、推送到国内 Harbor。这种方式最灵活，可以精确控制同步的镜像列表和版本。方案二：使用 rsync + docker save/load，先在美国服务器上 `docker save` 导出 tar 文件，通过 rsync 增量传输到国内服务器，再 `docker load` 导入并推送。这种方式适合网络不稳定的环境，rsync 支持断点续传。方案三：使用 Harbor 原生的复制规则，配置美国 Harbor 作为源，国内 Harbor 作为目标，定时同步。但这种方式需要美国服务器也部署 Harbor。在实际生产中，建议使用方案一，配合 Cron 定时执行，并在脚本中加入重试逻辑和失败告警。同步完成后，在 Harbor 中配置 Trivy 自动扫描，确保推送的镜像安全。

### Q8: Harbor 的 RBAC 权限模型是怎样的？ [难度: 中]

**答案：** Harbor 采用基于项目和角色的访问控制模型。角色分为系统级别和项目级别。系统级别角色包括：系统管理员（Admin，管理所有项目和系统配置）和普通用户。项目级别角色包括：项目管理员（ProjectAdmin，管理项目设置和成员）、维护人员（Maintainer，推送/拉取镜像、管理漏洞白名单）、开发人员（Developer，推送/拉取镜像）、访客（Guest，只读拉取镜像）和受限访客（LimitedGuest，只能拉取指定仓库）。权限控制粒度包括：项目级别（对整个项目的操作权限）和仓库级别（对特定仓库的操作权限）。Harbor 还支持基于标签的权限控制（Tag-level permissions）和机器人账号（Robot Accounts），机器人账号可以配置精确到仓库级别的只读/读写权限，非常适合 CI/CD 流水线和 K8s 集群使用。

### Q9: Harbor 如何实现高可用？ [难度: 高]

**答案：** Harbor 高可用需要解决两个层面的问题：无状态服务层和有状态存储层。无状态服务层（Core、Portal、JobService、Proxy）可以通过多副本 + 负载均衡实现高可用，使用 Docker Swarm 或 Kubernetes 部署时直接设置 replicas > 1。有状态存储层需要外部化：PostgreSQL 使用主从复制或云数据库（如 RDS（AWS 关系型数据库服务））；Redis 使用 Sentinel（哨兵模式）或 Cluster 模式；Registry 存储使用共享存储（NFS、S3、MinIO），所有 Registry 实例挂载相同的后端存储。完整的高可用架构为：前端 HAProxy 负载均衡 -> 多个 Harbor 实例（Core/Portal/JobService 多副本）-> 外部 PostgreSQL（主从）+ 外部 Redis（Sentinel）+ 共享存储（S3/MinIO）。Harbor v2.x 还支持跨数据中心的双活架构，通过复制规则实现双向同步。

### Q10: 如何排查 Harbor 镜像推送失败的问题？ [难度: 中]

**答案：** Harbor 镜像推送失败的排查步骤为：首先检查网络连通性，`curl -v http://192.168.1.61/v2/` 确认 API 可达；然后检查认证，`docker login 192.168.1.61` 确认凭据正确；接着检查磁盘空间，`df -h /data` 确认存储充足；然后检查 Harbor 日志，`docker compose logs core` 查看错误信息；如果是 HTTPS 证书问题，检查证书是否过期或域名不匹配；如果是权限问题，确认用户对目标项目有 push 权限；如果是镜像大小限制，检查 Harbor 的配置和 Quota 设置。常见错误码：401 表示认证失败，403 表示权限不足，500 表示服务端错误。在 containerd 环境下，还需要检查 `/etc/containerd/certs.d/` 配置是否正确，以及 `skip_verify` 是否设置。

### Q11: 什么是镜像的 Content Trust（DCT）？Harbor 如何支持？ [难度: 高]

**答案：** Docker Content Trust（DCT，镜像内容信任）是 Docker 提供的镜像内容信任机制，基于 Notary 项目实现。核心原理是：镜像发布者使用私钥对镜像的 Manifest（镜像清单）进行数字签名，镜像消费者使用发布者的公钥验证签名，确保镜像内容未被篡改且来自可信来源。Harbor 集成了 Notary 服务（端口 4443），在安装时通过 `./install.sh --with-notary` 启用。启用后，用户推送镜像时可以同时推送签名（`DOCKER_CONTENT_TRUST=1 docker push`），拉取时自动验证签名（`DOCKER_CONTENT_TRUST=1 docker pull`）。Harbor Web UI 中可以查看镜像的签名状态。在生产环境中，可以配合 Admission Controller（准入控制器，如 gatekeeper）强制要求所有部署的镜像必须经过签名验证，实现"未签名不部署"的安全策略。

### Q12: Harbor v2.9.0 有哪些新特性？ [难度: 低]

**答案：** Harbor v2.9.0 的主要新特性包括：第一，Trivy 升级到最新版本，支持更多语言生态的漏洞扫描（包括 Java JAR、Go Binary 等），扫描速度进一步提升；第二，改进了 OCI Artifact 支持，除了 Docker 镜像和 Helm Chart 外，还支持 Sigstore Bundle、SBOM（Software Bill of Materials）等 OCI Artifact 类型；第三，增强了机器人账号功能，支持设置过期时间和更细粒度的权限控制；第四，改进了垃圾回收性能，大仓库的 GC 速度显著提升；第五，支持基于 SBOM（Software Bill of Materials，软件物料清单）的漏洞扫描，可以导入外部生成的 SBOM 文件进行关联分析；第六，改进了 Web UI 的用户体验，包括新的仪表盘和更直观的扫描结果展示；第七，安全修复和性能优化，包括修复了多个 CVE。升级时需要注意数据库迁移，建议先备份数据库再升级。

---

## 10. 故障排查案例

### 案例 1: Harbor 启动失败，Core 服务不断重启

**现象：**
```bash
docker compose -f /opt/harbor/docker-compose.yml ps
# harbor-core    Restarting
```

Core 日志：
```
failed to initialize database: dial tcp 127.0.0.1:5432: connect: connection refused
```

**排查步骤：**
1. 检查 PostgreSQL 容器状态：`docker compose ps postgres`
2. 检查 PostgreSQL 日志：`docker compose logs postgres`
3. 检查磁盘空间：`df -h /data`
4. 检查 PostgreSQL 数据目录权限

**解决方案：**
```bash
# 如果是磁盘空间不足
du -sh /data/database/*
# 清理旧日志
docker compose logs --no-color > /tmp/harbor-logs.txt

# 如果是权限问题
chown -R 999:999 /data/database

# 重启 Harbor
docker compose -f /opt/harbor/docker-compose.yml down
docker compose -f /opt/harbor/docker-compose.yml up -d
```

### 案例 2: docker push 到 Harbor 超时

**现象：**
```
docker push 192.168.1.61/k8s/nginx:latest
# error pushing image: Put "http://192.168.1.61/v2/k8s/nginx/blobs/uploads/": net/http: request canceled
```

**排查步骤：**
1. 测试网络连通性：`curl -v http://192.168.1.61/v2/`
2. 检查 Harbor 磁盘 IO：`iostat -x 1`
3. 检查网络带宽：`iperf3 -c 192.168.1.61`
4. 检查 Docker 日志：`journalctl -u docker --since "10 minutes ago"`

**解决方案：**
```bash
# 如果是网络问题，检查 MTU 设置
ip link show
# 如果 MTU 不一致，调整
ip link set eth0 mtu 1500

# 如果是 Docker 存储驱动问题
docker system df
docker system prune -a

# 如果是 Harbor 存储空间不足
docker compose -f /opt/harbor/docker-compose.yml exec registry du -sh /storage
# 执行垃圾回收释放空间
# 在 Web UI: 系统管理 -> 垃圾回收 -> 立即执行
```

### 案例 3: Trivy 扫描超时或失败

**现象：**
```bash
# 扫描任务一直处于 Pending 状态
# Trivy 日志报错: failed to download DB
```

**排查步骤：**
1. 检查 Trivy 容器状态：`docker compose ps trivy`
2. 检查 Trivy 日志：`docker compose logs trivy`
3. 检查网络（Trivy 需要下载 CVE 数据库）

**解决方案：**
```bash
# 如果是网络问题导致数据库下载失败
# 方案1: 配置代理
docker compose -f /opt/harbor/docker-compose.yml exec trivy \
    env TRIVY_DB_REPOSITORY=ghcr.io/aquasecurity/trivy-db trivy db update

# 方案2: 使用离线模式
# 先在有网络的机器上下载 Trivy DB
trivy db download --output /tmp/trivy-db.tar.gz
# 传输到 Harbor 服务器并导入
docker cp /tmp/trivy-db.tar.gz <trivy-container>:/tmp/
docker compose -f /opt/harbor/docker-compose.yml exec trivy \
    trivy db import /tmp/trivy-db.tar.gz

# 重启 Trivy
docker compose -f /opt/harbor/docker-compose.yml restart trivy
```

### 案例 4: containerd 无法拉取 Harbor 镜像

**现象：**
```bash
crictl pull 192.168.1.61/k8s/nginx:latest
# FATA: pulling image failed: rpc error: code = Unknown desc = failed to pull and unpack image
```

**排查步骤：**
1. 检查 hosts.toml 配置：`cat /etc/containerd/certs.d/192.168.1.61/hosts.toml`
2. 检查 containerd 日志：`journalctl -u containerd --since "10 minutes ago"`
3. 检查 Harbor 是否可达：`curl -v http://192.168.1.61/v2/_catalog`

**解决方案：**
```bash
# 重新配置 containerd 认证
mkdir -p /etc/containerd/certs.d/192.168.1.61

cat > /etc/containerd/certs.d/192.168.1.61/hosts.toml << 'EOF'
server = "http://192.168.1.61"

[host."http://192.168.1.61"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF

# 重启 containerd
systemctl restart containerd

# 使用 ctr 手动测试
ctr -n k8s.io images pull --user "admin:Harbor12345" 192.168.1.61/k8s/nginx:latest
```

### 案例 5: Harbor 数据库连接数耗尽

**现象：**
```
Harbor Web UI 无法访问，Core 日志报错:
# FATAL: sorry, too many clients already
```

**排查步骤：**
1. 检查 PostgreSQL 连接数：`docker compose exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"`
2. 检查 max_connections 设置：`docker compose exec postgres psql -U postgres -c "SHOW max_connections;"`
3. 检查是否有大量空闲连接

**解决方案：**
```bash
# 临时方案：增加 PostgreSQL 最大连接数
# 编辑 docker-compose.yml 中的 postgres 服务
# 添加环境变量: POSTGRES_MAX_CONNECTIONS: 500

# 永久方案：修改 harbor.yml
# database:
#   max_idle_conns: 50  (从 100 降低)
#   max_open_conns: 200  (从 300 降低)

# 重启 Harbor
docker compose -f /opt/harbor/docker-compose.yml down
docker compose -f /opt/harbor/docker-compose.yml up -d
```

### 案例 6: Harbor 升级后镜像列表为空

**现象：**
```
Harbor v2.8 升级到 v2.9 后，Web UI 中所有项目显示 0 个镜像
```

**排查步骤：**
1. 检查 Registry 存储目录：`ls /data/registry/`
2. 检查数据库迁移日志：`docker compose logs core | grep migration`
3. 检查 Harbor 版本：`docker compose exec core cat /harbor/harbor.yml | grep version`

**解决方案：**
```bash
# 1. 确认数据未丢失
ls -la /data/registry/docker/registry/v2/repositories/
# 如果目录有内容，说明数据在

# 2. 重新同步 Registry 数据到数据库
docker compose -f /opt/harbor/docker-compose.yml exec core \
    /harbor/prepare --with-trivy

# 3. 重启 Harbor
docker compose -f /opt/harbor/docker-compose.yml restart

# 4. 如果仍然为空，检查数据库中的项目 ID 是否正确
docker compose exec postgres psql -U postgres -d registry -c \
    "SELECT id, name FROM project;"
```

### 案例 7: Trivy 扫描超时

**现象：**
```bash
# 推送镜像后扫描任务长时间处于 Pending 状态
# Harbor Web UI 显示："扫描进行中" 超过 30 分钟
# Trivy 日志显示：
"error":"context deadline exceeded"
"msg":"scan failed: scan timed out"
```

**排查步骤：**

1. **检查 Trivy 资源使用情况：**
```bash
# 检查 Trivy 容器资源使用
docker stats --no-stream | grep trivy

# 检查系统资源
top -p $(docker inspect -f '{{.State.Pid}}' $(docker compose ps -q trivy-adapter))
free -h
df -h /data
```

2. **检查扫描队列积压：**
```bash
# 查看扫描任务队列
curl -s "http://192.168.1.61/api/v2.0/jobs/scan" \
    -u "admin:Harbor12345" | jq '.[] | {id, status, repository}'

# 统计 Pending 任务数量
curl -s "http://192.168.1.61/api/v2.0/jobs/scan" \
    -u "admin:Harbor12345" | jq '[.[] | select(.status == "Pending")] | length'
```

3. **检查镜像大小和层数：**
```bash
# 检查待扫描镜像的层数
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/large-app/artifacts/latest" \
    -u "admin:Harbor12345" | jq '.layers | length'

# 检查镜像大小
docker images | grep large-app
```

**解决方案：**

```bash
# 方案1：增加 Trivy 扫描超时时间
# 编辑 harbor.yml
trivy:
  timeout: 30m  # 从默认 5m 增加到 30m

# 方案2：增加 Trivy 容器资源限制
# 编辑 docker-compose.yml
services:
  trivy-adapter:
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G

# 方案3：分批处理积压任务
# 取消所有 Pending 状态的扫描任务
curl -s "http://192.168.1.61/api/v2.0/jobs/scan" \
    -u "admin:Harbor12345" | \
    jq -r '.[] | select(.status == "Pending") | .id' | \
    while read job_id; do
        curl -X PUT "http://192.168.1.61/api/v2.0/jobs/scan/${job_id}" \
            -u "admin:Harbor12345" \
            -H "Content-Type: application/json" \
            -d '{"status": "Stopped"}'
    done

# 方案4：优化扫描策略（跳过大型层）
# 在 harbor.yml 中配置
trivy:
  offline_scan: true
  skip_update: true
  ignore_unfixed: true  # 忽略无修复方案的漏洞，减少扫描时间
  security_check: vuln  # 只扫描漏洞，不扫描配置和密钥

# 重启 Harbor 应用配置
docker compose -f /opt/harbor/docker-compose.yml down
docker compose -f /opt/harbor/docker-compose.yml up -d
```

**预防措施：**

```bash
# 配置扫描并发数限制
# 编辑 harbor.yml
jobservice:
  max_job_workers: 5  # 限制并发扫描任务数

# 配置镜像保留策略，避免积压过多待扫描镜像
# 配置自动扫描触发条件
```

### 案例 8: Cosign 签名验证失败

**现象：**
```bash
# 推送已签名镜像到 Harbor
# Kubernetes 部署时 Pod 无法启动，报错：
Failed to pull image "192.168.1.61/k8s/nginx:1.25.3": 
rpc error: code = Unknown desc = failed to pull and unpack image: 
failed to resolve reference "192.168.1.61/k8s/nginx:1.25.3": 
unexpected status code [manifests 1.25.3]: 412 Precondition Failed

# 或者 Cosign 验证时报错：
cosign verify --key cosign.pub 192.168.1.61/k8s/nginx:1.25.3
Error: no matching signatures: error verifying bundle: 
failed to verify signature: invalid signature
```

**排查步骤：**

1. **检查镜像签名状态：**
```bash
# 查看镜像签名信息
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts/1.25.3" \
    -u "admin:Harbor12345" | jq '.accessories'

# 检查签名附件是否存在
curl -s "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts" \
    -u "admin:Harbor12345" | jq '.[] | select(.tags[].name == "1.25.3") | .accessories'
```

2. **检查 Cosign 公钥配置：**
```bash
# 查看 Harbor 项目签名配置
curl -s "http://192.168.1.61/api/v2.0/projects/k8s" \
    -u "admin:Harbor12345" | jq '.metadata.enable_content_trust_cosign'

# 检查使用的公钥是否与签名时一致
cat cosign.pub
```

3. **检查镜像摘要是否匹配：**
```bash
# 获取镜像摘要
docker inspect 192.168.1.61/k8s/nginx:1.25.3 --format='{{index .RepoDigests 0}}'

# 验证签名时指定摘要
cosign verify --key cosign.pub 192.168.1.61/k8s/nginx@sha256:xxx...
```

**解决方案：**

```bash
# 方案1：重新签名镜像
# 删除旧签名（通过 Harbor API 删除签名附件）
curl -X DELETE "http://192.168.1.61/api/v2.0/projects/k8s/repositories/nginx/artifacts/{signature_digest}" \
    -u "admin:Harbor12345"

# 重新签名
cosign sign --key cosign.key 192.168.1.61/k8s/nginx:1.25.3

# 方案2：更新 Harbor 项目公钥配置
# 如果更换了密钥对，需要在 Harbor 中更新公钥
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "metadata": {
            "enable_content_trust_cosign": "true",
            "cosign_public_keys": "'$(cat cosign.pub | base64 -w0)'"
        }
    }'

# 方案3：临时禁用强制签名验证（排查问题）
curl -X PUT "http://192.168.1.61/api/v2.0/projects/k8s/metadatas/enable_content_trust_cosign" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"enable_content_trust_cosign": "false"}'

# 方案4：检查并修复签名数据
# 导出签名信息
cosign verify --key cosign.pub --output json 192.168.1.61/k8s/nginx:1.25.3 2>/dev/null | jq .

# 如果签名损坏，需要重新推送并签名镜像
docker pull 192.168.1.61/k8s/nginx:1.25.3
docker tag 192.168.1.61/k8s/nginx:1.25.3 192.168.1.61/k8s/nginx:1.25.3-resigned
docker push 192.168.1.61/k8s/nginx:1.25.3-resigned
cosign sign --key cosign.key 192.168.1.61/k8s/nginx:1.25.3-resigned
```

**验证修复：**

```bash
# 验证签名是否成功
cosign verify --key cosign.pub 192.168.1.61/k8s/nginx:1.25.3

# 在 Kubernetes 中测试拉取
kubectl run test-nginx --image=192.168.1.61/k8s/nginx:1.25.3 --rm -it --restart=Never -- /bin/sh
```

### 案例 9: 镜像保留策略误删

**现象：**
```bash
# 执行保留策略后，发现重要镜像被误删除
# Harbor Web UI 中生产环境的 v1.2.3 版本镜像消失
# CI/CD 流水线部署失败，提示镜像不存在
```

**排查步骤：**

1. **检查保留策略执行记录：**
```bash
# 查看保留策略执行历史
curl -s "http://192.168.1.61/api/v2.0/projects/production/retentions" \
    -u "admin:Harbor12345" | jq '.'

# 查看最近一次执行详情
RETENTION_ID=$(curl -s "http://192.168.1.61/api/v2.0/projects/production/retentions" \
    -u "admin:Harbor12345" | jq -r '.[0].id')

curl -s "http://192.168.1.61/api/v2.0/projects/production/retentions/${RETENTION_ID}/executions" \
    -u "admin:Harbor12345" | jq '.'

# 查看删除的镜像列表
EXECUTION_ID=$(curl -s "http://192.168.1.61/api/v2.0/projects/production/retentions/${RETENTION_ID}/executions" \
    -u "admin:Harbor12345" | jq -r '.[0].id')

curl -s "http://192.168.1.61/api/v2.0/projects/production/retentions/${RETENTION_ID}/executions/${EXECUTION_ID}/tasks" \
    -u "admin:Harbor12345" | jq '.'
```

2. **检查 Registry 存储层：**
```bash
# 检查 Registry 存储中是否还有数据
ls -la /data/registry/docker/registry/v2/repositories/production/

# 检查垃圾回收是否已执行（如果 GC 已执行，数据可能已物理删除）
docker compose -f /opt/harbor/docker-compose.yml logs jobservice | grep -i "garbage collection"
```

3. **检查数据库记录：**
```bash
# 查询数据库中是否还有记录
docker compose exec postgres psql -U postgres -d registry -c \
    "SELECT repository_name, tag FROM tag WHERE repository_name LIKE 'production/%';"
```

**解决方案：**

```bash
# 方案1：如果 GC 未执行，可以恢复 Tag 引用
# 重新给镜像打 tag（如果 blob 数据还在）
# 查找 manifest 文件
find /data/registry/docker/registry/v2/repositories/production -name "*.txt"

# 手动恢复（高级操作，谨慎使用）
# 1. 找到镜像的 manifest
curl -s "http://192.168.1.61/v2/production/myapp/manifests/v1.2.3" \
    -u "admin:Harbor12345" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json"

# 2. 重新推送 tag
curl -X PUT "http://192.168.1.61/v2/production/myapp/manifests/v1.2.3" \
    -u "admin:Harbor12345" \
    -H "Content-Type: application/vnd.docker.distribution.manifest.v2+json" \
    --data-binary @manifest.json

# 方案2：从备份恢复
# 如果有数据库备份，恢复 PostgreSQL
docker compose -f /opt/harbor/docker-compose.yml down

# 恢复数据库备份
cat /backup/harbor-db-backup.sql | docker exec -i harbor-db psql -U postgres

docker compose -f /opt/harbor/docker-compose.yml up -d

# 方案3：从其他 Harbor 实例复制
# 如果镜像在其他 Harbor 实例存在，执行复制
curl -X POST "http://192.168.1.61/api/v2.0/replication/executions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "policy_id": 1,
        "operation": "copy"
    }'

# 方案4：从 CI/CD 重新构建推送
# 触发 CI/CD 流水线重新构建并推送该版本镜像
```

**预防措施：**

```bash
# 1. 配置更严格的保留策略（使用 excludes）
curl -X POST "http://192.168.1.61/api/v2.0/projects/production/retentions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{
        "algorithm": "latestPushedK",
        "params": {
            "latestPushedK": 20
        },
        "rule_trigger": {
            "kind": "Schedule",
            "cron": "0 2 * * 0"
        },
        "scope_selectors": [
            {
                "kind": "repository",
                "decoration": "repoMatches",
                "pattern": "**"
            }
        ],
        "tag_selectors": [
            {
                "kind": "doublestar",
                "decoration": "excludes",
                "pattern": "{v[0-9]*,latest,stable,release-*,hotfix-*,prod*}"
            }
        ]
    }'

# 2. 启用 dry_run 模式测试策略
curl -X POST "http://192.168.1.61/api/v2.0/projects/production/retentions/{id}/executions" \
    -H "Content-Type: application/json" \
    -u "admin:Harbor12345" \
    -d '{"dry_run": true}'

# 3. 定期备份
cat > /opt/harbor/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/harbor/$(date +%Y%m%d)"
mkdir -p ${BACKUP_DIR}

# 备份数据库
docker exec harbor-db pg_dump -U postgres registry > ${BACKUP_DIR}/harbor-db.sql

# 备份 Registry 存储
tar czf ${BACKUP_DIR}/registry.tar.gz /data/registry

# 保留最近 7 天备份
find /backup/harbor -type d -mtime +7 -exec rm -rf {} \;
EOF

chmod +x /opt/harbor/backup.sh

# 添加到定时任务
echo "0 1 * * * /opt/harbor/backup.sh" | crontab -
```

---

## 11. 多架构镜像构建（进阶）

> 本节介绍多架构（multi-arch）镜像构建，支持arm64/amd64混合环境。
> 
> **适用场景**: ARM节点（AWS Graviton、鲲鹏）、混合架构集群
> **核心工具**: docker buildx、manifest

### 11.1 多架构镜像概述

**什么是多架构镜像**:

多架构镜像（Multi-arch Image）是一个镜像Manifest，包含多个架构的镜像层：

```
镜像仓库: myapp:1.0
    │
    ├── Manifest List (索引)
    │       ├── linux/amd64 -> digest-xxx
    │       ├── linux/arm64 -> digest-yyy
    │       └── linux/arm/v7 -> digest-zzz
    │
    └── 实际镜像层
            ├── amd64层 (digest-xxx)
            ├── arm64层 (digest-yyy)
            └── armv7层 (digest-zzz)
```

**客户端拉取时自动选择匹配架构**:
```bash
# 在amd64节点上
docker pull myapp:1.0  # 自动拉取amd64版本

# 在arm64节点上
docker pull myapp:1.0  # 自动拉取arm64版本
```

### 11.2 架构对比

| 架构 | 常见平台 | 适用场景 |
|------|----------|----------|
| **amd64 (x86_64)** | Intel/AMD服务器、云主机 | 传统x86服务器 |
| **arm64 (aarch64)** | AWS Graviton、华为鲲鹏、Apple M系列 | ARM云实例、边缘设备 |
| **arm/v7** | 树莓派、嵌入式设备 | IoT边缘场景 |
| **ppc64le** | IBM Power | 传统大型机迁移 |
| **s390x** | IBM Z | 主机迁移 |

### 11.3 Docker Buildx实战

#### 11.3.1 启用Buildx

```bash
# 检查buildx是否可用
docker buildx version
# github.com/docker/buildx v0.12.1 ...

# 创建并使用多架构构建器
docker buildx create --name multiarch-builder --driver docker-container --use

# 启动构建器
docker buildx inspect --bootstrap

# 查看构建器支持的架构
docker buildx inspect multiarch-builder
# Platforms: linux/amd64, linux/amd64/v2, linux/arm64, linux/arm/v7, linux/arm/v6, ...
```

#### 11.3.2 构建多架构镜像

**Dockerfile示例**:
```dockerfile
# 多架构基础镜像
FROM --platform=$TARGETPLATFORM golang:1.22-alpine AS builder

ARG TARGETPLATFORM
ARG TARGETARCH

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -o app .

FROM --platform=$TARGETPLATFORM alpine:3.19
COPY --from=builder /app/app /app
ENTRYPOINT ["/app"]
```

**构建命令**:
```bash
# 构建并推送到Harbor（支持多架构）
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag 192.168.1.61:80/library/myapp:1.0 \
  --push \
  .

# 仅构建不推送（用于测试）
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag myapp:1.0 \
  --load \
  .
```

#### 11.3.3 验证多架构镜像

```bash
# 查看镜像Manifest
docker buildx imagetools inspect 192.168.1.61:80/library/myapp:1.0

# 输出示例:
# Name:      192.168.1.61:80/library/myapp:1.0
# MediaType: application/vnd.docker.distribution.manifest.list.v2+json
# Digest:    sha256:xxx...
# 
# Manifests:
#   Name:      sha256:aaa... (amd64)
#   MediaType: application/vnd.docker.distribution.manifest.v2+json
#   Platform:  linux/amd64
#
#   Name:      sha256:bbb... (arm64)
#   MediaType: application/vnd.docker.distribution.manifest.v2+json
#   Platform:  linux/arm64

# 使用skopeo查看（如果安装了）
skopeo inspect docker://192.168.1.61:80/library/myapp:1.0 --raw | jq '.manifests[]'
```

### 11.4 手动Manifest操作

```bash
# 分别构建不同架构
docker build -t myapp:1.0-amd64 --build-arg ARCH=amd64 .
docker build -t myapp:1.0-arm64 --build-arg ARCH=arm64 .

# 推送单架构镜像
docker push 192.168.1.61:80/library/myapp:1.0-amd64
docker push 192.168.1.61:80/library/myapp:1.0-arm64

# 创建Manifest List
docker manifest create 192.168.1.61:80/library/myapp:1.0 \
  192.168.1.61:80/library/myapp:1.0-amd64 \
  192.168.1.61:80/library/myapp:1.0-arm64

# 推送Manifest
docker manifest push 192.168.1.61:80/library/myapp:1.0
```

### 11.5 Harbor多架构支持

Harbor原生支持多架构镜像：

```bash
# 推送多架构镜像到Harbor
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag 192.168.1.61:80/library/nginx:multiarch \
  --push \
  .

# 在Harbor Web UI中查看
# 导航到项目 -> 镜像仓库 -> nginx:multiarch
# 可以看到"Manifests"标签页，列出所有架构
```

### 11.6 常见基础镜像多架构支持

| 基础镜像 | amd64 | arm64 | arm/v7 | 说明 |
|----------|-------|-------|--------|------|
| `alpine:3.19` | ✅ | ✅ | ✅ | 最小化Linux |
| `ubuntu:22.04` | ✅ | ✅ | ❌ | 完整Ubuntu |
| `debian:bookworm` | ✅ | ✅ | ✅ | Debian稳定版 |
| `golang:1.22-alpine` | ✅ | ✅ | ✅ | Go编译环境 |
| `node:20-alpine` | ✅ | ✅ | ✅ | Node.js |
| `python:3.12-slim` | ✅ | ✅ | ✅ | Python |
| `nginx:alpine` | ✅ | ✅ | ✅ | Nginx |
| `redis:7-alpine` | ✅ | ✅ | ✅ | Redis |

### 11.7 注意事项

**构建环境要求**:
```bash
# 本地构建arm64镜像需要QEMU模拟
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# 或使用支持多架构的CI Runner（如GitHub Actions）
```

**离线环境同步**:
```bash
# 同步多架构镜像到Harbor
# 方法1: 使用skopeo copy（保留多架构）
skopeo copy --all docker://docker.io/nginx:alpine docker://192.168.1.61:80/library/nginx:alpine

# 方法2: 使用buildx重新构建推送
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag 192.168.1.61:80/library/nginx:alpine \
  --push \
  --build-arg BASE=nginx:alpine \
  .
```

**K8s调度**:
```yaml
# 确保Pod调度到正确架构节点
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      # 可选：显式指定节点架构
      nodeSelector:
        kubernetes.io/arch: amd64  # 或 arm64
      containers:
        - name: app
          image: myapp:1.0  # 多架构镜像，自动匹配
```

---

## 12. 生产环境建议

### 12.1 安全加固

1. **HTTPS**：生产环境必须启用 HTTPS，使用 Let's Encrypt 或企业 CA 签发证书
2. **密码策略**：修改默认管理员密码，启用密码复杂度要求
3. **RBAC**：遵循最小权限原则，使用机器人账号替代共享密码
4. **漏洞策略**：配置自动扫描 + Critical 级别阻止部署
5. **审计日志**：启用 Harbor 审计日志，记录所有操作

### 12.2 高可用设计

#### 12.2.1 单节点风险说明

单节点 Harbor 部署存在以下风险：

| 风险类型 | 影响 | 概率 | 后果 |
|---------|------|------|------|
| **服务器故障** | 硬件故障导致服务中断 | 中 | 镜像拉取/推送失败，K8s Pod 无法启动 |
| **存储损坏** | 磁盘故障导致数据丢失 | 低 | 镜像数据永久丢失，需重新同步 |
| **网络中断** | 网络设备故障 | 中 | 服务不可达，影响 CI/CD 流水线 |
| **维护窗口** | 升级或维护需要停机 | 高 | 计划内停机，影响业务连续性 |
| **性能瓶颈** | 单节点处理能力有限 | 高 | 高并发场景下响应延迟 |

**单节点架构：**

```
+------------------+
|   Harbor Server  |
|   192.168.1.61   |
|   (单点故障)     |
+------------------+
         |
    +----+----+
    |         |
+---v---+  +--v------+
| 本地   |  | 本地    |
| Postgre|  | Registry|
| SQL    |  | Storage |
+--------+  +---------+
```

#### 12.2.2 共享存储方案（NFS/MinIO）

**方案一：NFS 共享存储**

```
+------------------+     +------------------+     +------------------+
|  Harbor Node 1   |     |  Harbor Node 2   |     |  Harbor Node 3   |
|  192.168.1.61    |     |  192.168.1.62    |     |  192.168.1.63    |
+------------------+     +------------------+     +------------------+
         |                       |                       |
         +-----------------------+-----------------------+
                                 |
                    +------------v-------------+
                    |    NFS Server            |
                    |    192.168.1.70          |
                    |    /data/harbor          |
                    +--------------------------+
                                 |
                    +------------v-------------+
                    |    RAID Storage          |
                    |    (高可用存储)          |
                    +--------------------------+
```

NFS 配置步骤：

```bash
# NFS 服务器配置（192.168.1.70）
apt-get install -y nfs-kernel-server
mkdir -p /data/harbor
chmod 777 /data/harbor

cat >> /etc/exports << 'EOF'
/data/harbor 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

exportfs -a
systemctl restart nfs-kernel-server

# Harbor 节点挂载
apt-get install -y nfs-common
mkdir -p /data
mount -t nfs 192.168.1.70:/data/harbor /data

echo "192.168.1.70:/data/harbor /data nfs defaults 0 0" >> /etc/fstab
```

**方案二：MinIO 对象存储**

```yaml
# harbor.yml - MinIO 配置
storage_service:
  s3:
    accesskey: harbor-access-key
    secretkey: harbor-secret-key
    region: us-east-1
    regionendpoint: http://192.168.1.70:9000
    bucket: harbor-registry
    secure: false
    skipverify: true
    v4auth: true
    chunksize: 5242880
    rootdirectory: /
```

MinIO 部署：

```yaml
# docker-compose.minio.yml
version: '3.8'
services:
  minio:
    image: minio/minio:latest
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: harbor-admin
      MINIO_ROOT_PASSWORD: Harbor12345
    volumes:
      - /data/minio:/data
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  # MinIO 创建 bucket
  createbuckets:
    image: minio/mc:latest
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      sleep 10;
      /usr/bin/mc config host add myminio http://minio:9000 harbor-admin Harbor12345;
      /usr/bin/mc mb myminio/harbor-registry;
      /usr/bin/mc policy set public myminio/harbor-registry;
      exit 0;
      "
```

#### 12.2.3 多 Harbor 实例 + 负载均衡

**高可用架构：**

```
                              +------------------+
                              |   User Request   |
                              +--------+---------+
                                       |
                          +------------v-------------+
                          |    HAProxy / Nginx       |
                          |    (负载均衡器)          |
                          |    192.168.1.60          |
                          +----+------+------+-------+
                               |      |      |
              +----------------+      |      +----------------+
              |                       |                       |
     +--------v---------+  +----------v----------+  +---------v--------+
     |  Harbor Node 1   |  |   Harbor Node 2     |  |  Harbor Node 3   |
     |  192.168.1.61    |  |   192.168.1.62      |  |  192.168.1.63    |
     |  Core/Portal/    |  |   Core/Portal/      |  |  Core/Portal/    |
     |  JobService      |  |   JobService        |  |  JobService      |
     +--------+---------+  +----------+----------+  +---------+--------+
              |                       |                       |
              +-----------------------+-----------------------+
                                      |
                    +-----------------v------------------+
                    |      External Services             |
                    |  +-----------------------------+   |
                    |  |  PostgreSQL (Primary)       |   |
                    |  |  192.168.1.71               |   |
                    |  +-----------------------------+   |
                    |  |  Redis Sentinel             |   |
                    |  |  192.168.1.72-74            |   |
                    |  +-----------------------------+   |
                    |  |  MinIO Cluster              |   |
                    |  |  192.168.1.75-77            |   |
                    |  +-----------------------------+   |
                    +------------------------------------+
```

**HAProxy 负载均衡配置：**

```haproxy
# /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend harbor_frontend
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/harbor.pem
    redirect scheme https if !{ ssl_fc }
    default_backend harbor_backend

backend harbor_backend
    balance roundrobin
    option httpchk GET /api/v2.0/health
    http-check expect status 200
    server harbor1 192.168.1.61:80 check inter 2000 rise 2 fall 3
    server harbor2 192.168.1.62:80 check inter 2000 rise 2 fall 3
    server harbor3 192.168.1.63:80 check inter 2000 rise 2 fall 3 backup
```

**Nginx 负载均衡配置：**

```nginx
# /etc/nginx/conf.d/harbor.conf
upstream harbor_backend {
    least_conn;
    server 192.168.1.61:80 weight=5 max_fails=3 fail_timeout=30s;
    server 192.168.1.62:80 weight=5 max_fails=3 fail_timeout=30s;
    server 192.168.1.63:80 backup;
    
    keepalive 32;
}

server {
    listen 80;
    server_name harbor.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name harbor.example.com;
    
    ssl_certificate /etc/nginx/certs/harbor.crt;
    ssl_certificate_key /etc/nginx/certs/harbor.key;
    
    client_max_body_size 0;
    chunked_transfer_encoding on;
    
    location / {
        proxy_pass http://harbor_backend;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_send_timeout 900;
        proxy_read_timeout 900;
    }
}
```

**Harbor 节点配置（使用外部服务）：**

```yaml
# harbor.yml - 高可用配置
hostname: harbor.example.com

http:
  port: 80

https:
  port: 443
  certificate: /etc/harbor/certs/harbor.crt
  private_key: /etc/harbor/certs/harbor.key

# 外部 PostgreSQL
database:
  type: external
  host: 192.168.1.71
  port: 5432
  db_name: registry
  username: harbor
  password: HarborDB12345
  ssl_mode: disable
  max_idle_conns: 100
  max_open_conns: 300

# 外部 Redis
redis:
  type: external
  host: 192.168.1.72
  port: 6379
  password: Redis12345
  registry_db_index: 1
  jobservice_db_index: 2
  chartmuseum_db_index: 3
  trivy_db_index: 5
  idle_timeout: 30

# 外部存储
storage_service:
  s3:
    accesskey: harbor-access
    secretkey: harbor-secret
    region: us-east-1
    regionendpoint: http://192.168.1.75:9000
    bucket: harbor-registry
    secure: false

data_volume: /data
```

#### 12.2.4 Helm Chart 部署高可用 Harbor

**前提条件：**

```bash
# 添加 Harbor Helm 仓库
helm repo add harbor https://helm.goharbor.io
helm repo update

# 创建命名空间
kubectl create namespace harbor

# 创建存储类（如使用动态存储）
# 或使用现有存储类
```

**values-ha.yaml 配置：**

```yaml
# values-ha.yaml - Harbor 高可用 Helm 配置
expose:
  type: ingress
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-tls
      notarySecretName: notary-tls
  ingress:
    hosts:
      core: harbor.example.com
      notary: notary.example.com
    controller: default
    annotations:
      ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "0"

externalURL: https://harbor.example.com

# 高可用配置：多副本
portal:
  replicas: 3
  resources:
    requests:
      memory: 256Mi
      cpu: 100m

core:
  replicas: 3
  resources:
    requests:
      memory: 256Mi
      cpu: 100m

jobservice:
  replicas: 3
  resources:
    requests:
      memory: 256Mi
      cpu: 100m

registry:
  replicas: 3
  resources:
    requests:
      memory: 512Mi
      cpu: 100m

# 外部数据库
database:
  type: external
  external:
    host: "192.168.1.71"
    port: "5432"
    username: "harbor"
    password: "HarborDB12345"
    coreDatabase: "registry"
    notaryServerDatabase: "notary_server"
    notarySignerDatabase: "notary_signer"
    sslmode: "disable"

# 外部 Redis
redis:
  type: external
  external:
    addr: "192.168.1.72:6379,192.168.1.73:6379,192.168.1.74:6379"
    sentinelMasterSet: "mymaster"
    coreDatabaseIndex: "0"
    jobserviceDatabaseIndex: "1"
    registryDatabaseIndex: "2"
    chartmuseumDatabaseIndex: "3"
    trivyAdapterIndex: "5"
    password: "Redis12345"

# 外部存储
persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry:
      existingClaim: ""
      storageClass: ""
      subPath: ""
      accessMode: ReadWriteMany
      size: 100Gi
    chartmuseum:
      existingClaim: ""
      storageClass: ""
      subPath: ""
      accessMode: ReadWriteMany
      size: 5Gi
    jobservice:
      existingClaim: ""
      storageClass: ""
      subPath: ""
      accessMode: ReadWriteMany
      size: 1Gi
    # 使用 S3 替代本地存储
  imageChartStorage:
    type: s3
    s3:
      region: us-east-1
      bucket: harbor-registry
      accesskey: harbor-access
      secretkey: harbor-secret
      regionendpoint: http://192.168.1.75:9000
      secure: false
      skipverify: true
      v4auth: true
      chunksize: 5242880
      rootdirectory: /

# Trivy 配置
trivy:
  enabled: true
  replicas: 2
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

# 指标监控
metrics:
  enabled: true
  core:
    path: /metrics
    port: 8001
  registry:
    path: /metrics
    port: 8001
  jobservice:
    path: /metrics
    port: 8001
  exporter:
    path: /metrics
    port: 8001
```

**部署命令：**

```bash
# 部署高可用 Harbor
helm install harbor harbor/harbor \
    -n harbor \
    -f values-ha.yaml \
    --wait

# 验证部署
kubectl get pods -n harbor
kubectl get svc -n harbor
kubectl get ingress -n harbor

# 查看 Pod 分布
kubectl get pods -n harbor -o wide
```

**高可用验证：**

```bash
# 测试负载均衡
curl -k https://harbor.example.com/api/v2.0/health

# 测试故障转移
kubectl delete pod -n harbor -l component=core
kubectl get pods -n harbor -w

# 验证服务恢复
curl -k https://harbor.example.com/api/v2.0/health
```

#### 12.2.5 高可用检查清单

| 检查项 | 状态 | 备注 |
|--------|------|------|
| 数据库主从复制正常 | [ ] | 主库可写，从库可读 |
| Redis Sentinel 运行正常 | [ ] | 自动故障转移测试通过 |
| 存储多节点可访问 | [ ] | NFS/MinIO 所有节点挂载正常 |
| 负载均衡健康检查配置 | [ ] | 故障节点自动剔除 |
| Harbor 多实例运行 | [ ] | 至少 2 个实例 Running |
| 会话保持配置 | [ ] | 如使用有状态会话需配置 |
| 备份策略生效 | [ ] | 数据库和存储定期备份 |
| 监控告警配置 | [ ] | 节点故障可及时通知 |

### 12.3 运维管理

1. **监控**：通过 Prometheus 监控 Harbor 核心指标（请求延迟、存储使用、GC 状态）
2. **日志**：集中收集 Harbor 日志到 ELK/Loki
3. **GC 策略**：每周执行一次垃圾回收，配置镜像保留策略自动清理
4. **容量规划**：监控存储增长趋势，提前扩容
5. **版本升级**：跟随 Harbor 社区 LTS 版本，升级前完整备份

### 12.4 CI/CD 集成

1. **镜像构建**：CI 流水线构建镜像后推送到 Harbor
2. **安全扫描**：推送时自动触发 Trivy 扫描
3. **签名**：使用 Cosign 对镜像签名
4. **部署**：CD 流水线从 Harbor 拉取镜像部署到 K8s
5. **回滚**：保留多个版本的镜像 Tag，支持快速回滚

---

> **下一模块：** 03-容器运行时 containerd -- CRI 协议、配置详解与镜像管理
