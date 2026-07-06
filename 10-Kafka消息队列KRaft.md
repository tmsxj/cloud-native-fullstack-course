# 模块10：Kafka消息队列KRaft

---

## 1. 概述与架构图

### 1.1 Kafka KRaft 模式架构

```
+========================================================+
|                Kafka KRaft 集群 (无 ZooKeeper)           |
+========================================================+
|                                                         |
|  +------------------+  +------------------+            |
|  | Broker Node 0    |  | Broker Node 1    |            |
|  | (Controller+     |  | (Controller+     |            |
|  |  Broker 混合)    |  |  Broker 混合)    |            |
|  |                  |  |                  |            |
|  | +--Controller---+|  | +--Controller---+|            |
|  | | 元数据管理     ||  | | 元数据管理     ||            |
|  | | Leader 选举    ||  | | Follower      ||            |
|  | +---------------+|  | +---------------+|            |
|  | +--Broker-------+|  | +--Broker-------+|            |
|  | | 数据存储       ||  | | 数据存储       ||            |
|  | | 生产/消费      ||  | | 生产/消费      ||            |
|  | +---------------+|  | +---------------+|            |
|  +------------------+  +------------------+            |
|           |                    |                        |
|           +--------------------+                        |
|                    KRaft Raft 协议                       |
|                (元数据共识 + Leader 选举)                 |
|                                                         |
|  注意：2 节点 KRaft 集群仅用于学习/测试环境，              |
|  生产环境建议至少 3 节点以保证 Quorum 容错                |
+========================================================+
```

### 1.2 生产者-消费者架构

```
+------------------+                    +------------------+
|  Spring Boot     |                    |  Spring Boot     |
|  Producer        |                    |  Consumer Group  |
|  (Order Service) |                    |  (Inventory Svc) |
+--------+---------+                    +--------+---------+
         |                                       |
         |  Kafka Protocol (PLAINTEXT/SASL)      |
         v                                       v
+========================================================+
|                    Kafka KRaft Cluster                   |
|  +--------------------------------------------------+  |
|  | Topic: orders                                      |  |
|  | +----------+ +----------+ +----------+ +------+|  |
|  | |Partition0| |Partition1| |Partition2| |Part3 ||  |
|  | |Leader:B0 | |Leader:B1 | |Leader:B0 | |L:B1  ||  |
|  | |ISR:B0,B1 | |ISR:B1,B0 | |ISR:B0,B1 | |B0   ||  |
|  | +----------+ +----------+ +----------+ +------+|  |
|  +--------------------------------------------------+  |
+========================================================+
         |                                       |
         +-- Consumer Group: inventory-group ----+
              C1: P0, P1
              C2: P2, P3
```

### 1.3 Strimzi Operator（Kafka 管理） 架构

```
+========================================================+
|                    Kubernetes Cluster                   |
+========================================================+
|                                                         |
|  +------------------+                                  |
|  | Strimzi Operator |  <-- 管理 Kafka 集群生命周期      |
|  | (Deployment)     |                                  |
|  +--------+---------+                                  |
|           | watch CRDs                                  |
|           v                                             |
|  +------------------+  +------------------+  +--------+|
|  | Kafka CR         |  | KafkaTopic CR    |  | KafkaU ||
|  | (集群定义)       |  | (Topic 管理)     |  | ser CR ||
|  +------------------+  +------------------+  +--------+|
|           |                                             |
|           v                                             |
|  +--------------------------------------------------+  |
|  | Kafka Cluster (StatefulSet)                       |  |
|  | kafka-0  kafka-1  (2 Broker + 2 Controller)      |  |
|  +--------------------------------------------------+  |
+========================================================+
```

---

## 2. 理论基础

### 2.1 Kafka 核心概念

| 概念 | 说明 |
|------|------|
| Broker | Kafka 服务节点，存储和转发消息 |
| Topic | 消息的逻辑分类，类似数据库的表 |
| Partition | Topic 的物理分片，实现并行处理和水平扩展 |
| Producer | 消息生产者，将消息发送到 Topic |
| Consumer | 消息消费者，从 Topic 读取消息 |
| Consumer Group | 消费者组，组内每个分区只被一个消费者消费 |
| Offset | 消息在分区中的位置编号 |
| ISR (In-Sync Replicas) | 与 Leader 保持同步的副本集合 |
| LEO (Log End Offset) | 日志末尾偏移量 |
| HW (High Watermark) | 所有 ISR 副本都已复制的最大偏移量 |

### 2.2 KRaft 模式详解

Kafka 4.0 彻底移除了 ZooKeeper 依赖，使用 KRaft（Kafka Raft）协议管理集群元数据。

**KRaft vs ZooKeeper 对比：**

| 维度 | ZooKeeper 模式 | KRaft 模式 |
|------|---------------|-----------|
| 元数据存储 | 外部 ZooKeeper 集群 | Kafka 内部 Raft 日志 |
| 集群组件 | Kafka Broker + ZK Ensemble | 仅 Kafka Broker |
| 元数据延迟 | ZK Watch 机制，秒级延迟 | Raft 协议，毫秒级 |
| 运维复杂度 | 需要独立维护 ZK 集群 | 单一组件，简化运维 |
| Controller | 单一 Controller（Active/Standby） | 多 Controller（Raft 共识） |
| 分区数限制 | 约 20 万分区（受 ZK 性能限制） | 百万级分区 |
| 启动时间 | Controller 需从 ZK 加载元数据 | 直接从 Raft 日志加载，更快 |
| 版本要求 | Kafka 0.x - 3.x | Kafka 3.3+ (Preview), 4.0+ (Production) |

**KRaft 核心组件：**

| 角色 | 说明 |
|------|------|
| Controller | 管理集群元数据（Topic、分区、副本分配、Controller 选举） |
| Active Controller | Raft Leader，处理所有元数据写请求 |
| Standby Controller | Raft Follower，同步元数据，Active 故障时接管 |
| Broker | 处理客户端请求（生产/消费），存储数据 |
| Quorum（法定人数/多数派） | Controller 多数派（3 个 Controller 需要 2 个确认） |

### 2.3 消息投递语义

| 语义 | 说明 | 配置 |
|------|------|------|
| At Most Once | 消息可能丢失，不会重复 | `acks=0` + `enable.idempotence=false` |
| At Least Once | 消息不会丢失，可能重复 | `acks=all` + `enable.idempotence=false` |
| Exactly Once | 消息不丢不重（精确一次） | `acks=all` + `enable.idempotence=true` + 事务 |

**Exactly-Once 实现原理：**
1. **幂等生产者**：Producer 为每条消息分配 PID（Producer ID）和 Sequence Number，Broker 检测并去重
2. **事务**：跨多个 Partition 的原子写入，要么全部成功要么全部失败
3. **事务性消费**：Consumer 只读取已提交的事务消息（`isolation.level=read_committed`）

### 2.4 消费者组与再平衡

```
初始状态:
  Topic: orders (P0, P1, P2)
  Consumer Group: group-A
    C1 -> P0, P1
    C2 -> P2

C2 宕机后 Rebalance:
  Consumer Group: group-A
    C1 -> P0, P1, P2  (C1 承担所有分区)

C3 加入后 Rebalance:
  Consumer Group: group-A
    C1 -> P0, P1
    C3 -> P2

Rebalance 策略 (partition.assignment.strategy):
  - Range: 按范围分配（默认）
  - RoundRobin: 轮询分配
  - Sticky: 尽量保持原有分配，减少分区移动
  - CooperativeSticky: 增量再平衡，减少 Stop-The-World
```

---

## 2.5 离线前置准备

> **环境说明**：6 节点 K8s v1.28.15 离线集群，Harbor 192.168.1.61（HTTP，密码 Harbor12345），
> 无外网，Master 2C4G，Worker 4C8G，已部署 local-path StorageClass。

### 2.5.1 镜像预推送清单

以下镜像需要提前在有外网的机器上下载，推送到 Harbor，然后在所有 K8s 节点上配置 containerd/docker 的 insecure registry。

```bash
# ====== 在有外网的机器上执行 ======

# 1. 登录 Harbor
docker login 192.168.1.61 -u admin -p Harbor12345

# 2. 拉取并推送 Strimzi Operator 相关镜像
# Strimzi 0.39.0 Operator 核心镜像
docker pull quay.io/strimzi/operator:0.39.0
docker tag quay.io/strimzi/operator:0.39.0 192.168.1.61/strimzi/operator:0.39.0
docker push 192.168.1.61/strimzi/operator:0.39.0

# Strimzi Kafka 3.7.0 镜像
docker pull quay.io/strimzi/kafka:0.39.0-kafka-3.7.0
docker tag quay.io/strimzi/kafka:0.39.0-kafka-3.7.0 192.168.1.61/strimzi/kafka:0.39.0-kafka-3.7.0
docker push 192.168.1.61/strimzi/kafka:0.39.0-kafka-3.7.0

# Strimzi Kafka Init 镜像（用于初始化 KRaft 元数据）
docker pull quay.io/strimzi/kafka-init:0.39.0
docker tag quay.io/strimzi/kafka-init:0.39.0 192.168.1.61/strimzi/kafka-init:0.39.0
docker push 192.168.1.61/strimzi/kafka-init:0.39.0

# Strimzi TLS Sidecar 镜像
docker pull quay.io/strimzi/kafka-tls-sidecar:0.39.0
docker tag quay.io/strimzi/kafka-tls-sidecar:0.39.0 192.168.1.61/strimzi/kafka-tls-sidecar:0.39.0
docker push 192.168.1.61/strimzi/kafka-tls-sidecar:0.39.0

# 3. 拉取并推送 Kafka Exporter 监控镜像
docker pull docker.io/danielqsj/kafka-exporter:v1.7.0
docker tag docker.io/danielqsj/kafka-exporter:v1.7.0 192.168.1.61/danielqsj/kafka-exporter:v1.7.0
docker push 192.168.1.61/danielqsj/kafka-exporter:v1.7.0
```

**完整镜像清单（供核对）：**

| 镜像 | 用途 | Harbor 路径 |
|------|------|-------------|
| quay.io/strimzi/operator:0.39.0 | Strimzi Operator | 192.168.1.61/strimzi/operator:0.39.0 |
| quay.io/strimzi/kafka:0.39.0-kafka-3.7.0 | Kafka Broker/Controller | 192.168.1.61/strimzi/kafka:0.39.0-kafka-3.7.0 |
| quay.io/strimzi/kafka-init:0.39.0 | KRaft 初始化 | 192.168.1.61/strimzi/kafka-init:0.39.0 |
| quay.io/strimzi/kafka-tls-sidecar:0.39.0 | TLS Sidecar（边车代理） | 192.168.1.61/strimzi/kafka-tls-sidecar:0.39.0 |
| docker.io/danielqsj/kafka-exporter:v1.7.0 | Kafka 监控 Exporter | 192.168.1.61/danielqsj/kafka-exporter:v1.7.0 |

### 2.5.2 K8s 节点配置 insecure registry

所有 K8s 工作节点需要配置 containerd（或 docker）信任 Harbor HTTP 仓库。

```bash
# ====== 在所有 K8s 节点（Master + Worker）上执行 ======

# 如果使用 containerd（K8s 1.28 默认）：
cat >> /etc/containerd/config.toml <<'EOF'
[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.61".tls]
  insecure_skip_verify = true

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.61".auth]
  username = "admin"
  password = "Harbor12345"
EOF

systemctl restart containerd

# 如果使用 docker：
cat >> /etc/docker/daemon.json <<'EOF'
{
  "insecure-registries": ["192.168.1.61"]
}
EOF

systemctl restart docker
```

### 2.5.3 Strimzi Operator YAML 离线化处理

```bash
# ====== 在有外网的机器上执行 ======

# 1. 下载 Strimzi Operator 安装文件
curl -L https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.39.0/strimzi-cluster-operator-0.39.0.yaml \
  -o strimzi-cluster-operator-0.39.0.yaml

# 2. 替换所有 quay.io 镜像为 Harbor 地址
sed -i 's|quay.io/strimzi/|192.168.1.61/strimzi/|g' strimzi-cluster-operator-0.39.0.yaml

# 3. 验证替换结果
grep 'image:' strimzi-cluster-operator-0.39.0.yaml
# 预期：所有镜像地址均以 192.168.1.61/strimzi/ 开头

# 4. 传输到 Master 节点
scp strimzi-cluster-operator-0.39.0.yaml root@<master-ip>:/root/
```

### 2.5.4 Harbor 项目创建

```bash
# 在 Harbor 上创建所需的项目（通过 Harbor API 或 Web UI）
# 项目名称：strimzi（公开或私有均可）
# 项目名称：danielqsj（公开或私有均可）

# 通过 API 创建（在有外网的机器上执行）：
curl -X POST "http://192.168.1.61/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{"project_name":"strimzi","public":true}'

curl -X POST "http://192.168.1.61/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{"project_name":"danielqsj","public":true}'
```

### 2.5.5 离线环境资源说明

| 资源 | 离线环境配置 | 说明 |
|------|-------------|------|
| Kafka Broker | 2 副本 | 仅 2 个 Worker 节点 |
| KRaft Controller | 2 副本 | 与 Broker 混合部署 |
| StorageClass | local-path | 已部署的本地存储 |
| Broker 存储 | 20Gi | 每个节点 |
| Controller 存储 | 10Gi | 每个节点 |
| Broker CPU Request | 250m | 适配 4C8G Worker |
| Broker Memory Request | 512Mi | 适配 4C8G Worker |
| Broker JVM Heap | 512m-1g | 降低内存占用 |
| Controller CPU Request | 150m | Controller 负载较低 |
| Controller Memory Request | 256Mi | Controller 负载较低 |

> **注意**：2 节点 KRaft 集群的 Quorum 为 2（需要全部节点确认），无法容忍节点故障。
> 这是学习/测试环境的妥协配置，生产环境必须使用至少 3 个 Controller 节点。

---

## 3. 部署实战

### 3.1 安装 Strimzi Operator（离线方式）

> **前提**：已完成「离线前置准备」章节中的镜像预推送和 YAML 下载步骤。

```bash
# 创建命名空间
kubectl create namespace kafka

# ====== 以下操作在有外网的机器上完成 ======
# 1. 下载 Strimzi Operator 安装文件（含 CRD + Operator Deployment）
curl -L https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.39.0/strimzi-cluster-operator-0.39.0.yaml \
  -o strimzi-cluster-operator-0.39.0.yaml

# 2. 修改 YAML 中所有镜像地址，替换为 Harbor 地址
# 原始镜像格式：quay.io/strimzi/operator:0.39.0
# 替换为：192.168.1.61/strimzi/operator:0.39.0
sed -i 's|quay.io/strimzi/|192.168.1.61/strimzi/|g' strimzi-cluster-operator-0.39.0.yaml

# 3. （可选）如果需要指定 imagePullSecrets，在 Operator Deployment 中添加：
#    spec.template.spec.imagePullSecrets:
#    - name: harbor-secret

# 4. 将修改后的 YAML 传输到 Master 节点
scp strimzi-cluster-operator-0.39.0.yaml root@<master-ip>:/root/
# ====== 以下操作在 Master 节点上完成 ======

# 5. 应用 Strimzi 安装文件（本地文件，无需外网）
kubectl apply -f /root/strimzi-cluster-operator-0.39.0.yaml -n kafka

# 验证 Operator 安装
kubectl get pods -n kafka
# 预期：strimzi-cluster-operator-xxx Running

# 验证 CRD
kubectl get crd | grep kafka
# 预期：kafkas.kafka.strimzi.io, kafkatopics.kafka.strimzi.io, kafkausers.kafka.strimzi.io 等
```

### 3.2 部署 Kafka KRaft 集群

```bash
# 创建 Kafka 集群（2 节点混合模式：Controller + Broker）
# 注意：以下为旧版 Strimzi 配置（< 0.39），推荐使用下方 KRaft NodePool 配置
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: Kafka  # Kafka 集群
metadata:
  name: demo-cluster
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled  # 启用节点池模式
spec:
  kafka:
    version: 3.7.0
    metadataVersion: 3.7-IV0  # KRaft 元数据版本
    replicas: 2  # 副本数: 2
    listeners:
      - name: plain
        port: 9092
        type: internal  # 集群内部访问
        tls: false
      - name: external
        port: 9094
        type: nodeport  # NodePort 外部访问
        tls: false
        overrides:
          bootstrap:
            nodePort: 31092  # NodePort 端口
          brokers:
          - broker: 0
            nodePort: 31093  # NodePort 端口
          - broker: 1
            nodePort: 31094  # NodePort 端口
    authorization:
      type: simple  # 简单授权
    config:
      offsets.topic.replication.factor: 2  # 偏移量主题副本因子
      transaction.state.log.replication.factor: 2  # 事务日志副本因子
      transaction.state.log.min.isr: 1  # 事务日志最小 ISR
      default.replication.factor: 2  # 默认副本因子
      min.insync.replicas: 1  # 最小同步副本数
      num.partitions: 4  # 默认分区数
      auto.create.topics.enable: false  # 禁止自动创建主题
      log.retention.hours: 168  # 日志保留时间(小时)
      log.segment.bytes: 1073741824
      log.retention.check.interval.ms: 300000
      log.cleanup.policy: delete
      message.max.bytes: 10485760
      compression.type: lz4  # 压缩算法
    storage:
      type: jbod  # JBOD 多磁盘存储
      volumes:
      - id: 0
        type: persistent-claim
        size: 20Gi  # 存储大小: 20Gi
        deleteClaim: false  # 删除时保留数据卷
        class: local-path
    resources:
      requests:
        cpu: 250m  # CPU 250m
        memory: 512Mi  # 内存 512Mi
      limits:
        cpu: 1000m  # CPU 1000m
        memory: 2Gi  # 内存 2Gi
    jvmOptions:
      -Xms: 512m  # JVM 最小堆内存: 512m
      -Xmx: 1g  # JVM 最大堆内存: 1g
    template:
      pod:
        affinity:
          podAntiAffinity:  # Pod 反亲和性
            requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                - key: strimzi.io/cluster
                  operator: In
                  values:
                  - demo-cluster
              topologyKey: kubernetes.io/hostname
      persistentVolumeClaim:
        metadata:
          storageClassName: local-path  # 存储类名称
  zookeeper:
    # KRaft 模式不需要 ZooKeeper，但 Strimzi 0.38 之前版本需要保留此字段为空
    # Strimzi 0.39+ 完全支持 KRaft，可以省略此字段
EOF

# 注意：Strimzi 0.39+ 支持 KRaft 模式
# 如果使用 Strimzi 0.39+，使用以下 KRaft 配置：
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaNodePool  # Kafka 节点池
metadata:
  name: controller
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
    strimzi.io/pool-type: controller  # 控制器节点池
spec:
  replicas: 2  # 副本数: 2
  roles:
    - controller  # 控制器角色
  storage:
    type: persistent-claim
    size: 10Gi  # 存储大小: 10Gi
    deleteClaim: false  # 删除时保留数据卷
    class: local-path
  resources:
    requests:
      cpu: 150m  # CPU 150m
      memory: 256Mi  # 内存 256Mi
    limits:
      cpu: 500m  # CPU 500m
      memory: 512Mi  # 内存 512Mi
  jvmOptions:
    -Xms: 256m  # JVM 最小堆内存: 256m
    -Xmx: 512m  # JVM 最大堆内存: 512m
---
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaNodePool  # Kafka 节点池
metadata:
  name: broker
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
    strimzi.io/pool-type: broker  # 代理节点池
spec:
  replicas: 2  # 副本数: 2
  roles:
    - broker  # 代理角色
  storage:
    type: persistent-claim
    size: 20Gi  # 存储大小: 20Gi
    deleteClaim: false  # 删除时保留数据卷
    class: local-path
  resources:
    requests:
      cpu: 250m  # CPU 250m
      memory: 512Mi  # 内存 512Mi
    limits:
      cpu: 1000m  # CPU 1000m
      memory: 2Gi  # 内存 2Gi
  jvmOptions:
    -Xms: 512m  # JVM 最小堆内存: 512m
    -Xmx: 1g  # JVM 最大堆内存: 1g
---
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: Kafka  # Kafka 集群
metadata:
  name: demo-cluster
  namespace: kafka
spec:
  kafka:
    version: 3.7.0
    metadataVersion: 3.7-IV0  # KRaft 元数据版本
    listeners:
      - name: plain
        port: 9092
        type: internal  # 集群内部访问
        tls: false
      - name: external
        port: 9094
        type: nodeport  # NodePort 外部访问
        tls: false
        overrides:
          bootstrap:
            nodePort: 31092  # NodePort 端口
          brokers:
          - broker: 0
            nodePort: 31093  # NodePort 端口
          - broker: 1
            nodePort: 31094  # NodePort 端口
    authorization:
      type: simple  # 简单授权
    config:
      offsets.topic.replication.factor: 2  # 偏移量主题副本因子
      transaction.state.log.replication.factor: 2  # 事务日志副本因子
      transaction.state.log.min.isr: 1  # 事务日志最小 ISR
      default.replication.factor: 2  # 默认副本因子
      min.insync.replicas: 1  # 最小同步副本数
      num.partitions: 4  # 默认分区数
      auto.create.topics.enable: false  # 禁止自动创建主题
      log.retention.hours: 168  # 日志保留时间(小时)
      log.segment.bytes: 1073741824
      message.max.bytes: 10485760
      compression.type: lz4  # 压缩算法
EOF

# 监控集群状态
kubectl get kafka -n kafka -w
# 预期：demo-cluster -> ClusterOperator -> Provisioning -> Ready

# 检查 Pod 状态（需要等待 2-3 分钟）
kubectl get pods -n kafka
# 预期：demo-cluster-entity-operator-xxx, demo-cluster-kafka-0/1 Running
```

### 3.3 Topic 管理

```bash
# 创建 Topic
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaTopic  # Kafka 主题
metadata:
  name: orders
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  partitions: 4  # 分区数
  replicas: 2  # 副本数: 2
  config:
    retention.ms: 604800000  # 消息保留时间(毫秒)
    segment.bytes: 1073741824
    cleanup.policy: delete  # 日志清理策略
    compression.type: lz4  # 压缩算法
    max.message.bytes: 10485760
EOF

# 创建更多 Topic
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaTopic  # Kafka 主题
metadata:
  name: order-events
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  partitions: 3  # 分区数
  replicas: 2  # 副本数: 2
  config:
    retention.ms: 259200000  # 消息保留时间(毫秒)
    cleanup.policy: compact,delete  # 日志清理策略
    compression.type: lz4  # 压缩算法
---
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaTopic  # Kafka 主题
metadata:
  name: payment-events
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  partitions: 3  # 分区数
  replicas: 2  # 副本数: 2
  config:
    retention.ms: 604800000  # 消息保留时间(毫秒)
    compression.type: lz4  # 压缩算法
---
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaTopic  # Kafka 主题
metadata:
  name: inventory-events
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  partitions: 3  # 分区数
  replicas: 2  # 副本数: 2
  config:
    retention.ms: 604800000  # 消息保留时间(毫秒)
    compression.type: lz4  # 压缩算法
EOF

# 查看 Topic 列表
kubectl get kafkatopic -n kafka

# 查看 Topic 详情
kubectl describe kafkatopic orders -n kafka

# 修改分区数（只能增加不能减少）
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaTopic  # Kafka 主题
metadata:
  name: orders
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  partitions: 8  # 分区数
  replicas: 2  # 副本数: 2
  config:
    retention.ms: 604800000  # 消息保留时间(毫秒)
    compression.type: lz4  # 压缩算法
EOF
```

### 3.4 使用 Kafka CLI 验证

```bash
# 进入 Kafka Pod 执行 CLI 命令
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list

# 查看 Topic 详细信息
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic orders

# 发送测试消息
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic orders <<EOF
{"orderId":"ORD-001","userId":"U001","amount":99.99,"items":[{"sku":"SKU-001","qty":2}]}
{"orderId":"ORD-002","userId":"U002","amount":199.99,"items":[{"sku":"SKU-002","qty":1}]}
EOF

# 消费消息
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic orders --from-beginning --max-messages 2

# 查看消费者组
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --list

# 查看消费者组详情
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group order-consumer-group
```

### 3.5 Spring Boot 生产者配置

> **离线构建说明**：Spring Boot 项目需要 Maven 构建，在无外网环境中需配置 Nexus 私服。
> 请确保以下依赖已同步到 Nexus 私服：`spring-kafka`、`kafka-clients`、`jackson-databind`、`spring-boot-starter`。
> 在项目 `pom.xml` 或 `settings.xml` 中配置 `<mirror>` 指向 Nexus 私服地址。
> ```xml
> <!-- settings.xml 示例 -->
> <mirrors>
>   <mirror>
>     <id>nexus</id>
>     <mirrorOf>*</mirrorOf>
>     <url>http://<nexus-ip>:8081/repository/maven-public/</url>
>   </mirror>
> </mirrors>
> ```

```bash
# Spring Boot 生产者 application.yml
cat <<'EOF' > producer-application.yml
spring:
  kafka:
    bootstrap-servers: demo-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092  # Kafka 集群地址
    producer:
      # Exactly-Once 语义配置
      acks: all  # 所有 ISR 确认
      enable-idempotence: true  # 启用幂等生产者
      retries: 3  # 重试次数
      # 性能优化
      batch-size: 16384  # 批量发送大小(字节)
      buffer-memory: 33554432
      compression-type: lz4
      linger-ms: 5  # 等待延迟(毫秒)
      # Key 和 Value 序列化
      key-serializer: org.apache.kafka.common.serialization.StringSerializer  # Key 序列化器
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer  # Value 序列化器
      # 事务配置（跨分区原子写入）
      transaction-id-prefix: order-tx-  # 事务 ID 前缀
    properties:
      # 幂等性相关
      max.in.flight.requests.per.connection: 5
      # 安全配置
      security.protocol: PLAINTEXT  # 明文传输协议
EOF

# Spring Boot 生产者代码示例
cat <<'EOF' > OrderProducer.java
package com.demo.kafka.producer;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.concurrent.CompletableFuture;

@Component
public class OrderProducer {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    public OrderProducer(KafkaTemplate<String, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    // 普通发送（At Least Once）
    public CompletableFuture<SendResult<String, String>> sendOrder(String orderId, Object orderEvent) {
        try {
            String value = objectMapper.writeValueAsString(orderEvent);
            return kafkaTemplate.send("orders", orderId, value)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        // 处理发送失败：记录日志 + 重试 + 告警
                        System.err.println("Failed to send order: " + orderId + ", error: " + ex.getMessage());
                    } else {
                        System.out.println("Sent order: " + orderId +
                            ", partition: " + result.getRecordMetadata().partition() +
                            ", offset: " + result.getRecordMetadata().offset());
                    }
                });
        } catch (Exception e) {
            throw new RuntimeException("Serialization failed", e);
        }
    }

    // 事务发送（Exactly-Once，跨多个 Topic）
    @Transactional
    public void sendOrderTransaction(String orderId, Object orderEvent, Object inventoryEvent) {
        try {
            String orderJson = objectMapper.writeValueAsString(orderEvent);
            String inventoryJson = objectMapper.writeValueAsString(inventoryEvent);

            kafkaTemplate.send("orders", orderId, orderJson);
            kafkaTemplate.send("inventory-events", orderId, inventoryJson);
            // 事务提交时两个 Topic 的消息要么全部成功，要么全部失败
        } catch (Exception e) {
            throw new RuntimeException("Transaction send failed", e);
        }
    }
}
EOF
```

### 3.6 Spring Boot 消费者配置

```bash
# Spring Boot 消费者 application.yml
cat <<'EOF' > consumer-application.yml
spring:
  kafka:
    bootstrap-servers: demo-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092  # Kafka 集群地址
    consumer:
      group-id: order-consumer-group  # 消费者组 ID
      auto-offset-reset: earliest  # 从最早的消息开始消费
      enable-auto-commit: false  # 关闭自动提交偏移量
      # Exactly-Once 消费配置
      isolation-level: read_committed  # 只读已提交事务
      # Key 和 Value 反序列化
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer  # Key 反序列化器
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer  # Value 反序列化器
      properties:
        spring.json.trusted.packages: "*"
        # 手动提交配置
        max.poll.records: 500
        max.poll.interval.ms: 300000
        session.timeout.ms: 30000
        heartbeat.interval.ms: 10000
    listener:
      ack-mode: manual_immediate  # 手动确认模式
      # 并发消费（根据分区数设置）
      concurrency: 3  # 并发消费线程数
EOF

# Spring Boot 消费者代码示例
cat <<'EOF' > OrderConsumer.java
package com.demo.kafka.consumer;

import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class OrderConsumer {

    // 基础消费（手动提交 Offset）
    @KafkaListener(
        topics = "orders",
        groupId = "order-consumer-group",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void consumeOrder(String message, Acknowledgment ack) {
        try {
            // 1. 解析消息
            // 2. 业务处理（创建订单、扣减库存等）
            // 3. 处理成功后手动提交 Offset
            System.out.println("Processing order: " + message);
            ack.acknowledge();
        } catch (Exception e) {
            // 处理失败：不提交 Offset，消息会被重新消费
            // 需要记录错误日志 + 死信队列 + 告警
            System.err.println("Failed to process order: " + e.getMessage());
            throw e;
        }
    }

    // 事务消费（消费 + 发送到另一个 Topic，原子操作）
    @Transactional
    @KafkaListener(
        topics = "orders",
        groupId = "order-processor-group",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void processOrderTransaction(String message, Acknowledgment ack) {
        // 1. 消费 orders Topic 的消息
        // 2. 处理业务逻辑
        // 3. 发送处理结果到 order-events Topic
        // 4. 事务提交：消费 Offset 和发送消息原子完成
        ack.acknowledge();
    }

    // 批量消费（提高吞吐量）
    @KafkaListener(
        topics = "orders",
        groupId = "order-batch-group",
        containerFactory = "batchKafkaListenerContainerFactory"
    )
    public void consumeBatch(List<String> messages, Acknowledgment ack) {
        try {
            // 批量处理消息
            for (String message : messages) {
                System.out.println("Batch processing: " + message);
            }
            ack.acknowledge();
        } catch (Exception e) {
            System.err.println("Batch processing failed: " + e.getMessage());
            throw e;
        }
    }
}
EOF
```

### 3.7 压力测试

```bash
# 使用 Kafka 自带的压力测试工具

# 1. 生产者压力测试
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-producer-perf-test.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --num-records 1000000 \
  --record-size 1024 \
  --throughput -1 \
  --producer-props \
    acks=all \
    compression.type=lz4 \
    linger.ms=5 \
    batch.size=16384

# 预期输出（参考）：
# 1000000 records sent, 50000 records/sec (48.83 MB/sec), 20.00 ms avg latency, 500 ms max latency

# 2. 消费者压力测试
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-perf-test.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --messages 1000000 \
  --group perf-test-group \
  --from-beginning

# 3. 持续压测（后台运行）
kubectl exec -it demo-cluster-kafka-0 -n kafka -- sh -c '
  /opt/kafka/bin/kafka-producer-perf-test.sh \
    --topic orders \
    --bootstrap-server localhost:9092 \
    --num-records 5000000 \
    --record-size 512 \
    --throughput 100000 \
    --producer-props acks=all compression.type=lz4
' &

# 4. 监控 Kafka 指标
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-run-class.sh kafka.tools.JmxTool \
  --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi \
  --object-name kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec \
  --attributes OneMinuteRate
```

---

## 4. 配置详解 / 高级功能

### 4.1 消息积压处理

```bash
# 检查消息积压
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group order-consumer-group

# 输出示例：
# GROUP                TOPIC   PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# order-consumer-group orders  0          10000           50000           40000  <-- 积压
# order-consumer-group orders  1          8000            45000           37000  <-- 积压

# 积压处理方案一：增加消费者实例
# 修改消费者 Deployment 的 replicas 数量
kubectl scale deployment order-consumer -n demo --replicas=6
# 注意：消费者数量不应超过分区数

# 积压处理方案二：增加分区数
# 扩容 Topic 分区（只能增加）
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaTopic  # Kafka 主题
metadata:
  name: orders
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  partitions: 8  # 分区数
  replicas: 2  # 副本数: 2
EOF

# 积压处理方案三：临时消费者（加速消费）
# 启动一个临时消费者组，快速消费积压消息
cat <<'EOF' > catchup-consumer.py
import subprocess
import json
import time

# 使用 kafka-consumer-groups.sh 重置 Offset 到积压起始位置
subprocess.run([
    '/opt/kafka/bin/kafka-consumer-groups.sh',
    '--bootstrap-server', 'localhost:9092',
    '--group', 'catchup-group',
    '--topic', 'orders',
    '--reset-offsets', '--to-earliest',
    '--execute'
])

# 启动多个临时消费者并行消费
for i in range(6):
    subprocess.Popen([
        '/opt/kafka/bin/kafka-console-consumer.sh',
        '--bootstrap-server', 'localhost:9092',
        '--topic', 'orders',
        '--group', 'catchup-group',
        '--max-messages', '100000',
        '--partition', str(i)
    ])
EOF

# 积压处理方案四：调整消费者配置
# max.poll.records: 500 -> 1000（增加每次拉取数量）
# max.poll.interval.ms: 300000 -> 600000（增加处理超时）
# fetch.min.bytes: 1 -> 1024（减少请求次数）
```

### 4.2 Exactly-Once 语义完整配置

```bash
# 生产者端
cat <<'EOF' > exactly-once-producer.yml
spring:
  kafka:
    producer:
      acks: all  # 所有 ISR 确认
      enable-idempotence: true  # 启用幂等生产者
      retries: 2147483647
      max.in.flight.requests.per.connection: 5
      transaction-id-prefix: order-tx-  # 事务 ID 前缀
      key-serializer: org.apache.kafka.common.serialization.StringSerializer  # Key 序列化器
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer  # Value 序列化器
    properties:
      # 事务超时
      transaction.timeout.ms: 900000
      # 幂等超时
      delivery.timeout.ms: 120000
EOF

# 消费者端
cat <<'EOF' > exactly-once-consumer.yml
spring:
  kafka:
    consumer:
      group-id: order-transactional-group  # 消费者组 ID
      auto-offset-reset: earliest  # 从最早的消息开始消费
      enable-auto-commit: false  # 关闭自动提交偏移量
      isolation-level: read_committed  # 只读已提交事务
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer  # Key 反序列化器
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer  # Value 反序列化器
      properties:
        spring.json.trusted.packages: "*"
    listener:
      ack-mode: manual_immediate  # 手动确认模式
EOF

# Kafka Broker 端配置（已在 Kafka CR 中配置）
# min.insync.replicas: 1
# transaction.state.log.replication.factor: 2
# transaction.state.log.min.isr: 1
```

### 4.3 Kafka ACL 授权

```bash
# 创建 Kafka 用户
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaUser  # Kafka 用户
metadata:
  name: order-producer
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  authentication:
    type: tls  # TLS 认证
  authorization:
    type: simple  # 简单授权
    acls:
    - resource:
        type: topic  # 主题资源
        name: orders
        patternType: literal  # 精确匹配
      operations:
      - Write  # 写权限
      - Describe  # 描述权限
      host: "*"
    - resource:
        type: topic  # 主题资源
        name: inventory-events
        patternType: literal  # 精确匹配
      operations:
      - Write
      - Describe
      host: "*"
    - resource:
        type: transactionalId  # 事务 ID 资源
        name: order-tx-
        patternType: prefix  # 前缀匹配
      operations:
      - Write
      - Describe
      host: "*"
---
apiVersion: kafka.strimzi.io/v1beta2  # Strimzi API 版本
kind: KafkaUser  # Kafka 用户
metadata:
  name: order-consumer
  namespace: kafka
  labels:
    strimzi.io/cluster: demo-cluster
spec:
  authentication:
    type: tls  # TLS 认证
  authorization:
    type: simple  # 简单授权
    acls:
    - resource:
        type: topic  # 主题资源
        name: orders
        patternType: literal  # 精确匹配
      operations:
      - Read  # 读权限
      - Describe  # 描述权限
      host: "*"
    - resource:
        type: group  # 消费者组资源
        name: order-consumer-group
        patternType: literal  # 精确匹配
      operations:
      - Read
      host: "*"
EOF

# 查看 ACL 列表
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-acls.sh \
  --bootstrap-server localhost:9092 --list
```

### 4.4 Kafka 监控（Kafka Exporter + Grafana（可视化面板））

```bash
# 部署 Kafka Exporter
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1  # API 版本
kind: Deployment  # K8s 部署
metadata:
  name: kafka-exporter
  namespace: kafka
  labels:
    app: kafka-exporter
spec:
  replicas: 1  # 副本数: 1
  selector:
    matchLabels:
      app: kafka-exporter
  template:
    metadata:
      labels:
        app: kafka-exporter
    spec:
      containers:
      - name: kafka-exporter
        image: 192.168.1.61/danielqsj/kafka-exporter:v1.7.0  # 镜像地址(Harbor)
        ports:
        - containerPort: 9308
        env:
        - name: KAFKA_BROKER  # Kafka Broker 地址
          value: "demo-cluster-kafka-bootstrap:9092"
        - name: KAFKA_VERSION  # Kafka 版本
          value: "3.7.0"
        resources:
          requests:
            cpu: 100m  # CPU 100m
            memory: 128Mi  # 内存 128Mi
          limits:
            cpu: 500m  # CPU 500m
            memory: 512Mi  # 内存 512Mi
---
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: kafka-exporter
  namespace: kafka
  labels:
    app: kafka-exporter
spec:
  selector:
    app: kafka-exporter
  ports:
  - port: 9308
    targetPort: 9308
---
apiVersion: monitoring.coreos.com/v1  # API 版本
kind: ServiceMonitor
metadata:
  name: kafka-exporter
  namespace: kafka
  labels:
    app: kafka-exporter
spec:
  selector:
    matchLabels:
      app: kafka-exporter
  endpoints:
  - port: 9308
    interval: 30s  # 采集间隔
    path: /metrics  # 指标采集路径
EOF

# 验证 Kafka Exporter
kubectl get pods -n kafka -l app=kafka-exporter
curl -s http://kafka-exporter.kafka.svc.cluster.local:9308/metrics | grep kafka_topic | head -10
```

---

## 5. 验证与测试

### 5.1 端到端验证

```bash
# 1. 验证集群状态
kubectl get kafka demo-cluster -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# 预期：True

# 2. 验证 Topic
kubectl get kafkatopic -n kafka
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic orders

# 3. 发送消息
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic orders <<'EOF'
{"orderId":"TEST-001","userId":"U001","amount":99.99}
{"orderId":"TEST-002","userId":"U002","amount":199.99}
{"orderId":"TEST-003","userId":"U003","amount":299.99}
EOF

# 4. 消费消息
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic orders --from-beginning --max-messages 3

# 5. 验证消息积压监控
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group order-consumer-group

# 6. 验证 Kafka Exporter 指标
curl -s http://kafka-exporter.kafka.svc.cluster.local:9308/metrics | grep kafka_topic_partition_current_offset
```

### 5.2 高可用验证

```bash
# 1. 模拟 Broker 故障
kubectl delete pod demo-cluster-kafka-0 -n kafka

# 2. 观察集群状态（应自动恢复）
kubectl get pods -n kafka -w
# 预期：demo-cluster-kafka-0 重新创建并加入集群

# 3. 验证数据完整性
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic orders --from-beginning --max-messages 3

# 4. 检查 Under Replicated Partitions
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic orders | grep "Under Replicated"
# 预期：无 Under Replicated Partitions
```

---

## 6. CKA/CKS 考点融入

### 6.1 CKA 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| StatefulSet（有状态应用部署） | Kafka Pod 的有序部署和稳定网络标识 | 3.2 节 |
| PersistentVolumeClaim | Kafka 数据持久化存储 | 3.2 节 |
| Pod Anti-Affinity | Kafka Broker 分布在不同节点 | 3.2 节 |
| Resource Quotas | Kafka Pod 资源限制 | 3.2 节 |
| ConfigMap（配置映射）/Secret | Kafka 配置和凭证管理 | 3.5/3.6 节 |
| CRD/Operator | Strimzi 自定义资源和 Operator 模式 | 3.1/3.2 节 |

### 6.2 CKS 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| 网络策略 | Kafka 集群网络隔离 | 4.3 节 |
| TLS 加密 | Kafka TLS 监听器配置 | 3.2 节 |
| RBAC（基于角色的访问控制） | Kafka ACL 授权 | 4.3 节 |
| Secret 管理 | Kafka 用户证书管理 | 4.3 节 |
| 镜像安全 | Strimzi 镜像来源验证 | 3.1 节 |

---

## 7. 高频面试题

### Q1: Kafka 如何保证消息不丢失？（难度：中等）

**答案：** Kafka 从三个维度保证消息不丢失：**生产者端**：设置 `acks=all`，确保消息被所有 ISR 副本确认后才返回成功；启用 `enable.idempotence=true` 实现幂等生产，防止网络重试导致消息重复；设置 `retries=INT32_MAX` 和 `delivery.timeout.ms=120000`，确保生产者在遇到可恢复错误时自动重试。**Broker 端**：设置 `min.insync.replicas=2`（或更多），确保写入至少同步到指定数量的副本；设置 `default.replication.factor=2`（或 3），每个分区至少有 2 个副本；配置 `unclean.leader.election.enable=false`，防止非 ISR 副本成为 Leader 导致数据丢失。**消费者端**：关闭自动提交（`enable.auto.commit=false`），改为手动提交 Offset，确保消息处理成功后才提交；使用事务消费（`isolation.level=read_committed`），只读取已提交的消息。三者配合才能实现端到端的消息不丢失。

### Q2: KRaft 模式相比 ZooKeeper 模式有什么优势？（难度：中等）

**答案：** KRaft 模式的核心优势：1）**架构简化**：移除了 ZooKeeper 依赖，减少了外部组件，降低了运维复杂度和故障点；2）**元数据性能提升**：ZooKeeper 的 Watch 机制在元数据量大时性能下降严重，KRaft 使用 Raft 协议直接在 Kafka 内部管理元数据，元数据变更延迟从秒级降到毫秒级；3）**分区数扩展**：ZK 模式下分区数受限于 ZK 的性能瓶颈（约 20 万分区），KRaft 支持百万级分区；4）**Controller 高可用**：ZK 模式下只有一个 Active Controller，故障切换需要从 ZK 重新加载元数据（耗时数十秒），KRaft 模式下多个 Controller 通过 Raft 协议选举，故障切换更快；5）**启动速度**：KRaft Controller 直接从本地 Raft 日志加载元数据，无需从 ZK 全量拉取，集群启动更快。Kafka 4.0 是第一个完全移除 ZK 代码的生产版本。

### Q3: 什么是 ISR？ISR 缩小对 Kafka 有什么影响？（难度：中等）

**答案：** ISR（In-Sync Replicas）是与 Leader 副本保持同步的副本集合。一个副本要加入 ISR 需要满足：与 Leader 的差距在 `replica.lag.time.max.ms`（默认 30 秒）之内。ISR 的作用是保证数据一致性：当 `acks=all` 时，消息需要写入所有 ISR 副本才算成功；当 Leader 故障时，只有 ISR 中的副本才有资格被选为新 Leader。ISR 缩小的影响：1）写入性能下降：ISR 副本减少意味着需要等待的副本变少，但 `min.insync.replicas` 可能无法满足，导致写入被拒绝；2）可用性风险：如果 ISR 缩小到只剩 Leader 一个副本，此时如果 Leader 故障，且 `unclean.leader.election.enable=false`，则分区将不可用；3）数据丢失风险：如果启用了 unclean leader election，非 ISR 副本成为 Leader 会导致部分消息丢失。ISR 缩小通常是由于 Follower 副本负载过高或网络延迟导致同步跟不上。

### Q4: Kafka 如何实现 Exactly-Once 语义？（难度：困难）

**答案：** Kafka 的 Exactly-Once 语义需要生产者、Broker 和消费者三方配合。**生产者端**：启用 `enable.idempotence=true`，Kafka 为每个 Producer 分配 PID（Producer ID），每条消息携带 Sequence Number，Broker 检测重复消息并去重（同一 PID + Sequence Number 的消息只保留一条）。对于跨分区原子写入，使用 Kafka 事务：生产者通过 `transactional.id` 开启事务，调用 `beginTransaction()`、`commitTransaction()`、`abortTransaction()` 管理事务边界。**Broker 端**：事务协调器（Transaction Coordinator）管理事务状态机，事务日志记录在内部 Topic `__transaction_state` 中；设置 `min.insync.replicas >= 2` 和 `transaction.state.log.min.isr >= 2` 确保事务日志不丢失。**消费者端**：设置 `isolation.level=read_committed`，消费者只读取已提交事务的消息，未提交的事务消息对消费者不可见。Exactly-Once 的局限性：只保证 Kafka 内部的精确一次，如果消费端将消息写入外部系统（如数据库），需要配合外部系统的事务或幂等性实现端到端的精确一次。

### Q5: 如何处理 Kafka 消息积压？（难度：中等）

**答案：** 消息积压的处理需要根据原因和场景选择方案。**紧急处理**：1）增加消费者实例数量（不超过分区数），提高消费并行度；2）增加分区数（KafkaTopic CR 修改 partitions），然后增加消费者，注意扩分区后已有消息不会重新分布；3）临时启动一个独立的消费者组加速消费积压消息。**配置优化**：增大 `max.poll.records`（每次拉取更多消息）、增大 `fetch.min.bytes`（减少请求次数）、调整 `max.poll.interval.ms`（给处理更多时间）。**根因分析**：1）消费者处理速度慢 -> 优化业务逻辑、异步处理、批量处理；2）生产者突然流量激增 -> 限流、背压、消息降级；3）消费者频繁 Rebalance -> 检查消费超时配置、使用 CooperativeSticky（协作粘性策略） 策略；4）外部依赖慢（如数据库、API）-> 引入缓存、异步写入、连接池优化。**预防措施**：设置积压告警（Lag > 阈值）、定期压测确定系统吞吐量上限、设计合理的降级策略。

### Q6: Kafka 的分区分配策略有哪些？（难度：中等）

**答案：** Kafka 消费者组的分区分配策略决定了分区如何分配给组内的消费者。**Range**（默认）：按 Topic 维度将分区按范围分配，每个消费者获得连续的分区范围。例如 3 分区 2 消费者：C1 获得 P0、P1，C2 获得 P2。**RoundRobin**：所有 Topic 的分区轮询分配给消费者。例如 2 Topic 各 3 分区，2 消费者：C1 获得 T1-P0、T1-P2、T2-P1，C2 获得 T1-P1、T2-P0、T2-P2。**Sticky**：尽量保持原有分配不变，只在必要时移动分区，减少 Rebalance 时的分区移动。**CooperativeSticky**（推荐）：增量式 Sticky 分配，Rebalance 时先停止不需要的分区消费，再分配给新消费者，避免 Stop-The-World。选择建议：生产环境推荐 CooperativeSticky，它在 Rebalance 时不会暂停所有分区的消费，减少了 Rebalance 对业务的影响。配置方式：`partition.assignment.strategy=org.apache.kafka.clients.consumer.CooperativeStickyAssignor`。

### Q7: Kafka 消费者 Rebalance 的触发条件是什么？如何减少 Rebalance？（难度：困难）

**答案：** Rebalance 在以下情况触发：1）新消费者加入消费者组；2）消费者离开消费者组（宕机、主动退出）；3）消费者被踢出组（心跳超时 `session.timeout.ms` 或处理超时 `max.poll.interval.ms`）；4）订阅的 Topic 分区数变化；5）消费者订阅的 Topic 变化。Rebalance 的影响：Rebalance 期间所有消费者停止消费（Stop-The-World），影响吞吐量；频繁 Rebalance 导致消息处理延迟增加。减少 Rebalance 的方法：1）增大 `session.timeout.ms`（默认 10s -> 30s），避免因网络抖动触发 Rebalance；2）增大 `max.poll.interval.ms`（默认 5min -> 10min），避免因处理时间过长触发 Rebalance；3）使用 CooperativeSticky 分配策略，增量 Rebalance；4）合理设置 `heartbeat.interval.ms`（通常为 session.timeout.ms 的 1/3）；5）避免消费者 GC 停顿过长（调整 JVM 参数）；6）避免频繁部署/重启消费者。

### Q8: Kafka 如何保证消息顺序？（难度：困难）

**答案：** Kafka 只保证**单个分区内的消息顺序**，不保证跨分区的全局顺序。实现顺序性的方法：1）**单分区方案**：将需要保证顺序的消息发送到同一个分区，通过指定相同的 Key（如订单ID）确保相关消息路由到同一分区，Kafka 根据消息 Key 的 Hash 值选择分区。2）**分区有序消费**：每个分区只被一个消费者消费（消费者组内），消费者单线程顺序处理分区内的消息。3）**多线程消费方案**：消费者拉取消息后，按分区分配给不同的处理线程，每个分区的消息在各自线程内顺序处理。注意事项：使用 Key 路由可能导致数据倾斜（某些分区消息量远大于其他分区）；如果需要全局顺序，只能使用单分区单消费者，这会严重限制吞吐量，实际生产中通常通过业务设计避免全局顺序的需求（如按订单ID分区，每个订单的操作有序即可）。

### Q9: Spring Boot 中如何实现 Kafka 消费者的幂等性？（难度：中等）

**答案：** 消费者幂等性是指同一条消息被多次消费不会产生副作用。实现方式：1）**数据库唯一约束**：利用消息的唯一标识（如消息ID或业务ID）作为数据库唯一约束，重复消费时数据库会拒绝插入，消费者捕获异常后跳过；2）**Redis 去重**：消费前检查 Redis 中是否已处理过该消息ID（`SETNX`），已处理则跳过；3）**状态机**：将业务操作设计为幂等的状态转换，如订单状态从 "待支付" 变为 "已支付"，重复消费时状态已经是 "已支付" 则跳过；4）**版本号/CAS**：使用乐观锁，每次更新携带版本号，版本不匹配则跳过。Spring Boot 实现示例：使用 `@KafkaListener` 的 `ackMode = MANUAL_IMMEDIATE` 手动提交 Offset，在业务处理成功后才提交；配合 `@Transactional` 确保数据库操作和 Offset 提交的原子性。推荐使用数据库唯一约束 + 状态机组合方案，最可靠。

### Q10: Kafka 的日志清理策略有哪些？（难度：简单）

**答案：** Kafka 提供两种日志清理策略：**delete**（默认）：基于时间或大小清理旧日志段。配置参数：`log.retention.hours=168`（保留 7 天）、`log.retention.bytes=-1`（不限大小）、`log.segment.bytes=1073741824`（1GB 一个日志段）、`log.retention.check.interval.ms=300000`（每 5 分钟检查一次）。当日志段超过保留时间或总大小超过限制时，删除最旧的日志段。**compact**：基于 Key 压缩，保留每个 Key 的最新值。适用于事件溯源（Event Sourcing（事件溯源））场景，如用户最新状态、配置最新值。配置：`cleanup.policy=compact`，还可以组合使用 `cleanup.policy=compact,delete`，先压缩再按时间删除。压缩策略的注意事项：需要 Key 不为 null；压缩是异步的，不保证实时性；活跃的日志段不会被压缩。选择建议：普通消息队列使用 delete，状态类数据使用 compact。

### Q11: Kafka 如何实现延迟消息？（难度：困难）

**答案：** Kafka 原生不支持延迟消息（Delayed Message），但可以通过以下方案实现：1）**多级 Topic 方案**：创建不同延迟级别的 Topic（如 `orders-delay-5s`、`orders-delay-30s`、`orders-delay-5m`），消费者根据延迟级别消费对应 Topic。缺点是需要多个 Topic 和消费者。2）**时间轮 + 定时检查**：生产者将消息发送到延迟 Topic，消息中携带期望投递时间戳；消费者消费后检查是否到达投递时间，未到达则重新发送到延迟 Topic 或暂存内存。3）**外部定时任务**：使用定时任务（如 Spring @Scheduled）定期扫描延迟消息表，到达时间后发送到目标 Topic。4）**Kafka Streams + Window**：使用 Kafka Streams 的窗口操作处理时间窗口内的消息。生产环境推荐方案一（多级 Topic）或方案三（外部定时任务），方案一实现简单但 Topic 数量多，方案三灵活但依赖外部存储。如果延迟级别固定且较少，方案一是最佳选择。

### Q12: Strimzi Operator 的工作原理是什么？（难度：中等）

**答案：** Strimzi Operator 遵循 Kubernetes Operator 模式，通过 CRD（自定义资源定义）（Custom Resource Definition）管理 Kafka 集群的生命周期。核心 CRD 包括：**Kafka**：定义 Kafka 集群（Broker 配置、存储、监听器、授权等）；**KafkaTopic**：管理 Topic（分区数、副本数、配置）；**KafkaUser**：管理用户认证和 ACL；**KafkaNodePool**：定义 Controller/Broker 节点池。Operator 的工作流程：1）Watch API Server 中 Kafka 相关 CRD 的变化；2）当用户创建/修改 Kafka CR 时，Operator 的 Reconcile 循环被触发；3）Operator 根据期望状态（Spec）和当前状态（Status）计算差异；4）Operator 创建/更新/删除对应的 K8s 资源（StatefulSet、Service、ConfigMap、Secret 等）；5）Operator 持续监控资源状态直到达到期望状态。Strimzi 的优势：声明式管理、自动故障恢复、滚动升级、配置热更新。

### Q13: Kafka 事务的底层原理是什么？（难度：困难）

**答案：** Kafka 事务的底层实现涉及多个组件协作。**Transaction Coordinator**：每个 Producer 对应一个 Transaction Coordinator（从 `__transaction_state` Topic 的分区中选取），负责管理事务状态机。**事务状态机**：Empty -> Ongoing -> PrepareCommit -> CompleteCommit（成功路径）；Empty -> Ongoing -> PrepareAbort -> CompleteAbort（回滚路径）。**事务流程**：1）Producer 调用 `initTransactions()`，向 Coordinator 注册 `transactional.id`，获取/恢复 PID 和 Epoch；2）Producer 调用 `beginTransaction()`，Coordinator 将事务状态设为 Ongoing；3）Producer 发送消息到各分区，每个消息携带 PID、Epoch 和 Control Batch 标记；4）Producer 调用 `commitTransaction()`，Coordinator 写入 PREPARE_COMMIT 到事务日志，等待所有分区 Leader 确认消息已写入（写入 Marker 消息），然后写入 COMPLETE_COMMIT；5）消费者设置 `isolation.level=read_committed`，只读取 LEO <= Last Stable Offset 的消息（LSO 是所有未完成事务中最早的消息位置）。事务的隔离通过 Marker 消息和 LSO 实现。

### Q14: 如何监控 Kafka 集群的健康状态？（难度：中等）

**答案：** Kafka 监控的关键指标分为三类：**Broker 级别**：BytesInPerSec/BytesOutPerSec（吞吐量）、UnderReplicatedPartitions（未充分复制分区数，应始终为 0）、OfflinePartitionsCount（离线分区数，应始终为 0）、ActiveControllerCount（应为 1）、RequestLatencyMs（请求延迟）。**Topic 级别**：MessagesInPerSec（消息生产速率）、BytesInPerSec（字节生产速率）、LogSize（日志大小）、Partition 数量。**消费者级别**：ConsumerLag（消费延迟/积压量，最关键指标）、ConsumerOffset（当前消费位置）、TotalConsumerLag（组总积压量）。监控工具：1）Kafka Exporter（导出消费者 Lag 指标到 Prometheus）；2）JMX Exporter（导出 Broker JMX 指标到 Prometheus）；3）Grafana Dashboard（Kafka Overview Dashboard ID 7589、Kafka Consumers Dashboard ID 7589）。告警规则：UnderReplicatedPartitions > 0、OfflinePartitionsCount > 0、ConsumerLag > 10000、RequestLatency P99 > 1s。

### Q15: Kafka 在微服务架构中的典型应用场景有哪些？（难度：简单）

**答案：** Kafka 在微服务架构中的典型应用场景：1）**异步解耦**：订单服务创建订单后发送消息到 Kafka，库存服务、通知服务、积分服务异步消费处理，避免同步调用链路过长。2）**流量削峰**：秒杀/抢购场景，请求先写入 Kafka，后端服务按自身处理能力消费，防止系统被瞬时流量压垮。3）**事件驱动架构（EDA）**：服务间通过事件通信，如 OrderCreated、PaymentCompleted、InventoryDeducted 事件，实现最终一致性。4）**数据同步**：将数据库变更事件（CDC（变更数据捕获））通过 Kafka 分发到搜索引擎、缓存、数据仓库等。5）**日志收集**：应用日志写入 Kafka，下游 Logstash/Flink 消费处理。6）**流式计算**：Kafka Streams 或 Flink 消费 Kafka 数据进行实时计算（实时推荐、风控、ETL）。选择 Kafka 的核心原因是高吞吐、持久化、支持重放、多消费者组独立消费。

---

## 8. 故障排查案例

### 案例 1：Kafka Broker 无法启动

**现象：**
```bash
kubectl get pods -n kafka
# demo-cluster-kafka-0   0/1 CrashLoopBackOff
# demo-cluster-kafka-1   1/1 Running
```

**排查步骤：**
```bash
# 1. 查看 Pod 日志
kubectl logs demo-cluster-kafka-0 -n kafka --tail=50
# 发现：java.io.IOException: No space left on device

# 2. 检查 PVC 状态
kubectl get pvc -n kafka
# 发现：data-0-demo-cluster-kafka-0 Bound

# 3. 检查节点磁盘
kubectl describe pvc data-0-demo-cluster-kafka-0 -n kafka | grep "Volume:"
# 发现：磁盘空间不足

# 4. 检查日志段大小
kubectl exec -it demo-cluster-kafka-1 -n kafka -- du -sh /var/lib/kafka/data
```

**解决方案：**
```bash
# 方案一：清理旧日志段（调整 retention）
# 修改 Kafka CR 的 log.retention.hours 从 168 降到 72

# 方案二：扩容 PVC（如果 StorageClass 支持）
kubectl patch pvc data-0-demo-cluster-kafka-0 -n kafka \
  --type merge -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# 方案三：迁移到有更多空间的节点
# 使用 local-path 时，需要手动迁移 PV 数据
```

### 案例 2：生产者发送超时

**现象：**
```
Spring Boot 应用日志：
org.apache.kafka.common.errors.TimeoutException: Expiring 1 record(s) for orders-0: 30001 ms has passed since batch creation plus linger time
```

**排查步骤：**
```bash
# 1. 检查 Kafka Broker 状态
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server localhost:9092 | head -5

# 2. 检查 Under Replicated Partitions
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --under-replicated-partitions

# 3. 检查 min.insync.replicas 配置
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-configs.sh \
  --bootstrap-server localhost:9092 --entity-type topics --entity-name orders --describe

# 4. 检查 ISR 状态
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic orders
# 发现：Partition 0 的 ISR 只有 1 个副本（min.insync.replicas=1）
```

**解决方案：**
```bash
# 问题原因：ISR 副本数 < min.insync.replicas，acks=all 的写入被拒绝

# 方案一：等待 Follower 追上 Leader（检查 Follower 是否正常）
kubectl logs demo-cluster-kafka-1 -n kafka --tail=20

# 方案二：临时降低 min.insync.replicas（仅紧急情况）
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-configs.sh \
  --bootstrap-server localhost:9092 --entity-type topics --entity-name orders \
  --alter --add-config min.insync.replicas=1

# 方案三：检查网络和磁盘 IO
kubectl exec -it demo-cluster-kafka-1 -n kafka -- iostat -x 1 3
```

### 案例 3：消费者频繁 Rebalance

**现象：**
```
消费者日志频繁出现：
Group coordinator rebalance for group order-consumer-group
Revoking previously assigned partitions
Assigning new partitions
```

**排查步骤：**
```bash
# 1. 检查消费者组状态
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group order-consumer-group
# 发现：consumer-id 和 client-id 不断变化

# 2. 检查消费者 Pod 状态
kubectl get pods -n demo -l app=order-consumer
# 发现：Pod 频繁重启

# 3. 检查消费者 OOM
kubectl describe pod -n demo -l app=order-consumer | grep -A 5 "Last State"
# 发现：OOMKilled

# 4. 检查处理时间
kubectl logs deploy/order-consumer -n demo | grep "Processing took"
# 发现：部分消息处理时间超过 max.poll.interval.ms
```

**解决方案：**
```bash
# 方案一：增大消费者内存限制
kubectl set resources deployment order-consumer -n demo \
  --limits=memory=2Gi --requests=memory=1Gi

# 方案二：增大 max.poll.interval.ms
# 在 application.yml 中调整：
# max.poll.interval.ms: 600000 (10 分钟)

# 方案三：减少 max.poll.records
# max.poll.records: 100 (减少每次拉取数量)

# 方案四：优化业务处理逻辑（异步处理、批量入库）
```

### 案例 4：Topic 分区分布不均

**现象：**
```bash
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic orders
# Partition 0: Leader 0, ISR [0,1]  -- Broker 0
# Partition 1: Leader 1, ISR [1,0]  -- Broker 1
# Partition 2: Leader 0, ISR [0,1]  -- Broker 0
# Partition 3: Leader 1, ISR [1,0]  -- Broker 1
# Broker 0 承担了 2 个分区的 Leader，Broker 1 也是 2 个
```

**排查步骤：**
```bash
# 1. 检查 Broker 磁盘使用
kubectl exec -it demo-cluster-kafka-0 -n kafka -- df -h /var/lib/kafka/data
kubectl exec -it demo-cluster-kafka-1 -n kafka -- df -h /var/lib/kafka/data

# 2. 检查 Broker 负载
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-run-class.sh kafka.tools.JmxTool \
  --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi \
  --object-name "kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec" \
  --attributes OneMinuteRate
```

**解决方案：**
```bash
# 使用 kafka-reassign-partitions.sh 重新分配分区
# 1. 生成当前分配
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-reassign-partitions.sh \
  --bootstrap-server localhost:9092 \
  --topics-to-move-json-file /tmp/topics.json \
  --broker-list "0,1" \
  --generate > /tmp/reassign.json

# 2. 执行重新分配
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-reassign-partitions.sh \
  --bootstrap-server localhost:9092 \
  --reassignment-json-file /tmp/reassign.json \
  --execute

# 3. 验证
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-reassign-partitions.sh \
  --bootstrap-server localhost:9092 \
  --reassignment-json-file /tmp/reassign.json \
  --verify
```

### 案例 5：Kafka 集群升级后消费者报错

**现象：**
```
升级 Strimzi Operator 后，消费者报错：
org.apache.kafka.common.errors.UnsupportedVersionException: The broker does not support the request
```

**排查步骤：**
```bash
# 1. 检查 Kafka 版本
kubectl get kafka demo-cluster -n kafka -o jsonpath='{.spec.kafka.version}'
# 发现：3.5.0

# 2. 检查 Strimzi Operator 版本
kubectl get deployment strimzi-cluster-operator -n kafka -o jsonpath='{.spec.template.spec.containers[0].image}'
# 发现：0.39.0（最新版）

# 3. 检查消费者客户端版本
# 发现：Spring Boot 使用的 kafka-clients 版本为 3.3.x

# 4. 检查 API 版本兼容性
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server localhost:9092 | grep "AlterIsr"
```

**解决方案：**
```bash
# 方案一：升级 Spring Boot Kafka 客户端版本
# 在 pom.xml 中升级 spring-kafka 到匹配版本

# 方案二：升级 Kafka Broker 版本
kubectl patch kafka demo-cluster -n kafka --type merge \
  -p '{"spec":{"kafka":{"version":"3.7.0"}}}'

# 注意：Kafka 不支持跨大版本降级，升级前请备份并测试
```

### 案例 6：消息消费后 Offset 未提交导致重复消费

**现象：**
```
消费者日志显示同一条消息被多次处理：
Processing order: {"orderId":"ORD-001",...}
Processing order: {"orderId":"ORD-001",...}
Processing order: {"orderId":"ORD-001",...}
```

**排查步骤：**
```bash
# 1. 检查消费者配置
kubectl exec -it deploy/order-consumer -n demo -- env | grep -i kafka
# 发现：enable.auto.commit=true（自动提交）

# 2. 检查消费者处理时间
kubectl logs deploy/order-consumer -n demo | grep "Processing took"
# 发现：部分消息处理时间超过 5 秒

# 3. 检查自动提交间隔
# 发现：auto.commit.interval.ms=1000（默认 1 秒）

# 4. 分析原因
# 消费者在 1 秒自动提交间隔内处理完消息前，Poll 返回了相同的消息
```

**解决方案：**
```bash
# 关闭自动提交，改为手动提交
# application.yml:
spring:
  kafka:
    consumer:
      enable-auto-commit: false  # 关闭自动提交偏移量
    listener:
      ack-mode: manual_immediate  # 手动确认模式

# 消费者代码中手动提交
@KafkaListener(topics = "orders", groupId = "order-consumer-group")
public void consume(String message, Acknowledgment ack) {
    try {
        processMessage(message);
        ack.acknowledge();  // 处理成功后手动提交
    } catch (Exception e) {
        log.error("Processing failed, will retry", e);
        throw e;  // 不提交 Offset，消息会被重新消费
    }
}
```

### 案例 7：Kafka 集群脑裂（Split Brain）

**现象：**
```bash
kubectl get pods -n kafka
# 所有 Broker Running，但集群行为异常

kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic orders
# Error: This server is not the leader for that topic partition

# 多个 Broker 都认为自己是 Controller
```

**排查步骤：**
```bash
# 1. 检查 Controller 状态
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-metadata-shell.sh \
  --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log \
  --command "controller"

# 2. 检查网络连通性
kubectl exec -it demo-cluster-kafka-0 -n kafka -- ping demo-cluster-kafka-1.demo-cluster-kafka-brokers.kafka.svc.cluster.local

# 3. 检查 ZooKeeper/KRaft 元数据
kubectl logs demo-cluster-kafka-0 -n kafka | grep -i "controller"
# 发现：多个 Broker 声称自己是 Active Controller
```

**解决方案：**
```bash
# KRaft 模式下脑裂恢复：
# 1. 停止所有 Broker
kubectl scale statefulset demo-cluster-kafka -n kafka --replicas=0

# 2. 检查哪个 Broker 有最新的元数据
# 3. 逐个启动 Broker，确保同一时间只有一个 Controller 候选者
kubectl scale statefulset demo-cluster-kafka -n kafka --replicas=1
# 等待第一个 Broker 完全启动
kubectl scale statefulset demo-cluster-kafka -n kafka --replicas=2

# 预防措施：确保 controller.quorum.voters 配置正确
# 确保 broker.id 唯一且持久化
```

### 案例 8：Spring Boot 消费者反序列化失败

**现象：**
```
消费者日志：
org.apache.kafka.common.errors.SerializationException: Error deserializing key/value for partition orders-0 at offset 12345
Caused by: com.fasterxml.jackson.databind.exc.InvalidDefinitionException: Cannot construct instance of `com.demo.OrderEvent`
```

**排查步骤：**
```bash
# 1. 检查消费者配置
kubectl exec -it deploy/order-consumer -n demo -- env | grep "spring.json.trusted.packages"
# 发现：未配置 trusted.packages

# 2. 查看原始消息内容
kubectl exec -it demo-cluster-kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic orders --from-beginning --max-messages 1 \
  --property print.key=true --property key.separator=","

# 3. 检查生产者和消费者的类版本是否一致
# 发现：生产者发送的 OrderEvent 新增了字段，消费者类未更新
```

**解决方案：**
```bash
# 方案一：配置 Jackson 信任包
# application.yml:
spring:
  kafka:
    consumer:
      properties:
        spring.json.trusted.packages: "*"
        spring.json.type.mapping: "order:com.demo.OrderEvent"

# 方案二：配置 Jackson 忽略未知属性
# 在 ObjectMapper 中配置：
# objectMapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)

# 方案三：使用 JsonDeserializer 自定义反序列化
@Configuration
public class KafkaConfig {
    @Bean
    public ConsumerFactory<String, OrderEvent> consumerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);
        props.put(JsonDeserializer.TRUSTED_PACKAGES, "*");
        props.put(JsonDeserializer.VALUE_DEFAULT_TYPE, "com.demo.OrderEvent");
        return new DefaultKafkaConsumerFactory<>(props, new StringDeserializer(),
            new JsonDeserializer<>(OrderEvent.class, false));
    }
}
```

---

## 9. 事件驱动技术选型（进阶）

### 9.1 消息中间件对比分析

在云原生架构中，消息中间件是事件驱动架构的核心组件。以下是主流消息中间件的对比分析：

| 特性 | Kafka | NATS JetStream | RabbitMQ | Redis Streams |
|------|-------|----------------|----------|---------------|
| **定位** | 分布式事件流平台 | 云原生消息系统 | 传统消息队列 | 内存数据结构 |
| **吞吐量** | 100万+/秒 | 100万+/秒 | 5万/秒 | 50万+/秒 |
| **延迟** | 毫秒级 | 微秒级 | 微秒级 | 亚毫秒级 |
| **持久化** | 磁盘顺序写 | 可配置 | 内存+磁盘 | 内存+可选AOF |
| **消息顺序** | 分区内有序 | 全局有序 | 队列内有序 | 流内有序 |
| **消费者模型** | 拉取模型 | 推拉结合 | 推送模型 | 拉取模型 |
| **协议支持** | 自定义协议 | NATS协议 | AMQP | RESP |
| **运维复杂度** | 高（ZooKeeper/KRaft） | 低 | 中 | 低 |
| **资源占用** | 高（JVM） | 低（Go） | 中（Erlang） | 低（C） |
| **云原生支持** | Strimzi Operator | Helm（K8s 包管理器）/K8s原生 | Operator | Helm |
| **适用场景** | 大数据流处理 | 微服务通信 | 传统企业集成 | 轻量缓存+消息 |

**选型决策树：**

```
+================================================================+
|                   消息中间件选型决策树                           |
+================================================================+
|                                                                 |
|  开始选型                                                       |
|      |                                                          |
|      v                                                          |
|  +----------------+                                             |
|  | 需要数据持久化? |                                             |
|  +-------+--------+                                             |
|     Yes  |   No                                                  |
|          |    +---> NATS Core (轻量级、超低延迟)                  |
|          v                                                       |
|  +----------------+                                             |
|  | 吞吐量 > 10万/秒?|                                            |
|  +-------+--------+                                             |
|     Yes  |   No                                                  |
|          |    +---> RabbitMQ (传统企业应用)                       |
|          v                                                       |
|  +----------------+                                             |
|  | 需要流处理能力? |                                             |
|  +-------+--------+                                             |
|     Yes  |   No                                                  |
|          |    +---> NATS JetStream (云原生微服务)                 |
|          v                                                       |
|  +----------------+                                             |
|  | 大数据生态集成? |                                             |
|  +-------+--------+                                             |
|     Yes  |   No                                                  |
|          |    +---> NATS JetStream 或 RabbitMQ                   |
|          v                                                       |
|     选择 Kafka                                                  |
|     (Flink/Spark/Kafka Connect 生态)                             |
|                                                                 |
+================================================================+
```

### 9.2 NATS JetStream 简介

**NATS** 是 CNCF 毕业项目，定位为云原生消息系统。NATS JetStream 是其持久化消息存储引擎，提供类似 Kafka 的功能但更轻量。

**核心特性：**

| 特性 | 说明 |
|------|------|
| **超低延迟** | 微秒级延迟，比 Kafka 快 10 倍以上 |
| **轻量部署** | 单二进制文件，内存占用 < 100MB |
| **流式消费** | 支持 Consumer 模型，类似 Kafka Consumer |
| **持久化** | 支持 Memory/File/SQL 三种存储后端 |
| **ACK 机制** | 支持 Ack/NAck/InFlight 消息确认 |
| **流量控制** | 内置背压和限流机制 |

**NATS JetStream vs Kafka 架构对比：**

```
+================================================================+
|            NATS JetStream vs Kafka 架构对比                      |
+================================================================+
|                                                                 |
|  Kafka 架构:                     NATS JetStream 架构:           |
|                                                                 |
|  +-------------+                +-------------+                 |
|  |  Producer   |                |  Producer   |                 |
|  +------+------+                +------+------+                 |
|         |                              |                        |
|         v                              v                        |
|  +-------------+                +-------------+                 |
|  | Kafka Broker|                | NATS Server |                 |
|  | (JVM, 1GB+) |                | (Go, 50MB)  |                 |
|  +------+------+                +------+------+                 |
|         |                              |                        |
|         v                              v                        |
|  +-------------+                +-------------+                 |
|  |  ZooKeeper  |                |  JetStream  |                 |
|  |  或 KRaft   |                |  (内置存储)  |                 |
|  +-------------+                +-------------+                 |
|         |                              |                        |
|         v                              v                        |
|  +-------------+                +-------------+                 |
|  |  Consumer   |                |  Consumer   |                 |
|  +-------------+                +-------------+                 |
|                                                                 |
|  运维复杂度: 高                   运维复杂度: 低                  |
|  资源占用: 高                     资源占用: 低                    |
|                                                                 |
+================================================================+
```

**NATS JetStream 快速部署（离线）：**

```bash
# 镜像准备
docker pull nats:2.10-alpine
docker tag nats:2.10-alpine 192.168.1.61:80/nats/nats:2.10-alpine
docker push 192.168.1.61:80/nats/nats:2.10-alpine

# 部署 NATS Server（启用 JetStream）
cat > nats-server.yaml << 'EOF'
apiVersion: apps/v1  # API 版本
kind: Deployment  # K8s 部署
metadata:
  name: nats-server
  namespace: messaging
spec:
  replicas: 1  # 副本数: 1
  selector:
    matchLabels:
      app: nats-server
  template:
    metadata:
      labels:
        app: nats-server
    spec:
      containers:
      - name: nats
        image: 192.168.1.61:80/nats/nats:2.10-alpine  # 镜像地址(Harbor)
        args:
        - "--jetstream"
        - "--store_dir=/data"
        - "-m=8222"  # 监控端口
        ports:
        - containerPort: 4222  # 客户端端口
          name: client
        - containerPort: 8222  # 监控端口
          name: monitor
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            cpu: 100m  # CPU 100m
            memory: 128Mi  # 内存 128Mi
          limits:
            cpu: 500m  # CPU 500m
            memory: 512Mi  # 内存 512Mi
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: nats-server
  namespace: messaging
spec:
  ports:
  - port: 4222
    name: client
  - port: 8222
    name: monitor
  selector:
    app: nats-server
EOF

kubectl create namespace messaging
kubectl apply -f nats-server.yaml
```

**NATS JetStream Stream 配置：**

```yaml
# 使用 nats CLI 创建 Stream
# nats stream add ORDERS \
#   --subjects "orders.*" \
#   --retention limits \
#   --max-msgs=100000 \
#   --max-bytes=1GB \
#   --max-age=7d

# 或通过 API 创建
# Stream 定义
{
  "name": "ORDERS",
  "subjects": ["orders.*"],
  "retention": "limits",
  "max_msgs": 100000,
  "max_bytes": 1073741824,  # 1GB
  "max_age": 604800000000000,  # 7 天（纳秒）
  "storage": "file",
  "replicas": 1
}
```

### 9.3 CloudEvents 标准

**CloudEvents** 是 CNCF（云原生计算基金会） 毕业项目，定义了事件描述的标准化规范，解决不同事件系统之间的互操作性问题。

**CloudEvents 规范结构：**

```json
{
  "specversion": "1.0",
  "type": "com.example.order.created",
  "source": "/orders/service",
  "id": "A234-1234-1234",
  "time": "2024-01-15T10:30:00Z",
  "datacontenttype": "application/json",
  "data": {
    "orderId": "ORD-12345",
    "customerId": "CUST-67890",
    "amount": 99.99,
    "items": [
      {"productId": "PROD-001", "quantity": 2}
    ]
  }
}
```

**CloudEvents 必需属性：**

| 属性 | 类型 | 说明 |
|------|------|------|
| specversion | String | 规范版本，当前为 "1.0" |
| type | String | 事件类型，如 "order.created" |
| source | URI | 事件来源，如 "/services/orders" |
| id | String | 事件唯一标识 |

**CloudEvents 可选属性：**

| 属性 | 类型 | 说明 |
|------|------|------|
| time | Timestamp | 事件发生时间 |
| datacontenttype | String | 数据 MIME 类型 |
| subject | String | 事件主题 |
| data | Object | 事件数据负载 |

**Kafka CloudEvents 集成：**

```java
// Java 示例：发送 CloudEvents 格式消息
import io.cloudevents.CloudEvent;
import io.cloudevents.core.builder.CloudEventBuilder;

CloudEvent event = CloudEventBuilder.v1()
    .withId("order-123")
    .withSource(URI.create("/orders/service"))
    .withType("com.mall.order.created")
    .withDataContentType("application/json")
    .withData(objectMapper.writeValueAsBytes(order))
    .build();

// 发送到 Kafka
ProducerRecord<String, byte[]> record = new ProducerRecord<>(
    "orders",
    event.getId(),
    cloudEventToBytes(event)
);
kafkaProducer.send(record);
```

**NATS CloudEvents 集成：**

```go
// Go 示例：发送 CloudEvents 格式消息
import cloudevents "github.com/cloudevents/sdk-go/v2"

event := cloudevents.NewEvent()
event.SetID("order-123")
event.SetSource("/orders/service")
event.SetType("com.mall.order.created")
event.SetDataContentType(cloudevents.ApplicationJSON)
event.SetData(order)

// 发送到 NATS
nc.Publish("orders.created", event.Bytes())
```

### 9.4 技术选型决策指南

**场景一：微服务事件驱动架构**

```yaml
# 推荐：NATS JetStream
# 原因：
# - 低延迟、高吞吐
# - 轻量部署、运维简单
# - 云原生设计、K8s 友好
# - 资源占用低（适合离线集群）

# 适用场景：
# - 服务间异步通信
# - 事件溯源（Event Sourcing）
# - CQRS 架构
# - 实时通知推送
```

**场景二：大数据流处理平台**

```yaml
# 推荐：Kafka
# 原因：
# - 与 Flink/Spark 原生集成
# - Kafka Connect 生态丰富
# - 数据持久化可靠
# - 支持数据回放

# 适用场景：
# - 日志收集（ELK 替代）
# - 点击流分析
# - 实时数据仓库
# - 事件驱动 ETL
```

**场景三：传统企业应用集成**

```yaml
# 推荐：RabbitMQ
# 原因：
# - AMQP 标准协议
# - 丰富的路由规则
# - 事务支持
# - 企业级特性

# 适用场景：
# - ERP/CRM 系统集成
# - 复杂路由需求
# - 需要事务保证
# - 异构系统集成
```

### 9.5 离线部署考量

**各中间件离线部署复杂度对比：**

| 中间件 | 镜像数量 | 外部依赖 | Helm Chart | 离线难度 |
|--------|----------|----------|------------|----------|
| Kafka (Strimzi) | 3-5 个 | 无（KRaft） | 有 | 中 |
| NATS JetStream | 1 个 | 无 | 有 | 低 |
| RabbitMQ | 1 个 | 无 | 有 | 低 |
| Redis | 1 个 | 无 | 有 | 低 |

**离线集群推荐配置：**

```yaml
# 离线集群（6 节点，资源有限）推荐方案

# 方案一：NATS JetStream（推荐）
# - 单实例即可运行
# - 内存占用 < 200MB
# - 吞吐量足够（10万+/秒）

# 方案二：Kafka KRaft（如需大数据生态）
# - 最少 3 节点 Controller
# - 内存占用 1-2GB/节点
# - 需要更多资源

# 方案三：RabbitMQ（如需传统协议）
# - 单实例即可运行
# - 内存占用 512MB-1GB
# - 支持 AMQP 协议
```

**NATS vs Kafka 资源占用对比（离线集群）：**

```
+================================================================+
|           离线集群资源占用对比（6节点 K8s）                       |
+================================================================+
|                                                                 |
|  NATS JetStream:                                                |
|  +----------------------------------------------------------+  |
|  |  组件        |  CPU   |  内存    |  存储    |  实例数    |  |
|  |  NATS Server |  0.1   |  256MB   |  1GB     |  1         |  |
|  |  总计        |  0.1   |  256MB   |  1GB     |  1 Pod     |  |
|  +----------------------------------------------------------+  |
|                                                                 |
|  Kafka KRaft:                                                  |
|  +----------------------------------------------------------+  |
|  |  组件        |  CPU   |  内存    |  存储    |  实例数    |  |
|  |  Kafka       |  1     |  2GB     |  10GB    |  3         |  |
|  |  总计        |  3     |  6GB     |  30GB    |  3 Pods    |  |
|  +----------------------------------------------------------+  |
|                                                                 |
|  结论：NATS 资源占用仅为 Kafka 的 1/20                           |
|                                                                 |
+================================================================+
```

### 9.6 CKA/CKS 考点关联

| 考点 | 关联内容 |
|------|----------|
| **Service 类型** | 理解消息中间件暴露方式（ClusterIP/NodePort） |
| **持久化存储** | PV/PVC 配置，StorageClass 选择 |
| **资源限制** | 理解 JVM 应用 vs Go 应用的资源特性 |
| **健康检查** | Liveness/Readiness Probe 配置 |
| **安全** | TLS 加密、SASL（简单认证与安全层） 认证配置 |

**高频面试题：**

1. **Q: Kafka 和 RabbitMQ 的主要区别是什么？**
   - A: Kafka 是分布式事件流平台，采用拉取模型，适合大数据场景；RabbitMQ 是传统消息队列，采用推送模型，适合企业集成。Kafka 吞吐量更高但延迟更大，RabbitMQ 功能更丰富但吞吐量较低。

2. **Q: 什么时候选择 NATS 而不是 Kafka？**
   - A: 当需要低延迟（微秒级）、轻量部署、云原生架构时选择 NATS。当需要大数据生态集成、数据回放、高吞吐量持久化时选择 Kafka。

3. **Q: CloudEvents 解决了什么问题？**
   - A: CloudEvents 提供了事件描述的标准化规范，解决了不同事件系统之间的互操作性问题。通过统一的事件格式，不同系统可以无缝交换事件数据。

---

## 10. 生产环境建议

### 10.1 生产级 Kafka 配置清单

```yaml
# Kafka CR 生产配置（适配 2 节点离线集群）
spec:
  kafka:
    config:
      # 可靠性
      default.replication.factor: 2  # 默认副本因子
      min.insync.replicas: 1  # 最小同步副本数
      unclean.leader.election.enable: false
      auto.create.topics.enable: false  # 禁止自动创建主题

      # 性能
      num.io.threads: 4
      num.network.threads: 3
      socket.send.buffer.bytes: 102400
      socket.receive.buffer.bytes: 102400
      socket.request.max.bytes: 104857600
      num.recovery.threads.per.data.dir: 1

      # 日志
      log.retention.hours: 168  # 日志保留时间(小时)
      log.segment.bytes: 1073741824
      log.retention.check.interval.ms: 300000
      log.cleanup.policy: delete
      log.flush.interval.messages: null
      log.flush.interval.ms: null

      # 压缩
      compression.type: lz4  # 压缩算法

      # 事务
      transaction.state.log.replication.factor: 2  # 事务日志副本因子
      transaction.state.log.min.isr: 1  # 事务日志最小 ISR
      transaction.max.timeout.ms: 900000

    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 1Gi  # 内存 1Gi
      limits:
        cpu: 2000m  # CPU 2000m
        memory: 4Gi  # 内存 4Gi
    jvmOptions:
      -Xms: 1g  # JVM 最小堆内存: 1g
      -Xmx: 2g  # JVM 最大堆内存: 2g
      -XX:+UseG1GC
      -XX:MaxGCPauseMillis: 200
      -XX:InitiatingHeapOccupancyPercent: 35
```

### 9.2 生产最佳实践

| 领域 | 建议 |
|------|------|
| **集群规模** | 生产环境至少 3 Broker + 3 Controller（KRaft 模式）；本离线环境 2 节点仅供学习测试 |
| **副本因子** | 生产 Topic replication.factor=3；本离线环境 replication.factor=2 |
| **min.insync.replicas** | 生产环境设为 2（与 replication.factor 配合）；本离线环境设为 1 |
| **监控告警** | UnderReplicatedPartitions > 0、OfflinePartitions > 0、ConsumerLag > 阈值 |
| **磁盘** | 使用 SSD 或 NVMe，独立磁盘用于日志存储 |
| **JVM** | 使用 G1GC（垃圾回收器），堆内存不超过 6GB（避免 GC 停顿） |
| **网络** | Broker 间使用万兆网络，减少复制延迟 |
| **备份** | 定期备份 Kafka 配置和 Topic 元数据 |
| **升级** | 先升级 Controller，再滚动升级 Broker |
| **安全** | 启用 TLS 加密 + SASL 认证 + ACL 授权 |
| **容量规划** | 预留 30% 磁盘空间用于日志段切换和故障恢复 |
| **消费者** | 使用 CooperativeSticky 分配策略，关闭自动提交 |
| **离线部署** | 所有镜像需预推送到 Harbor，YAML 文件需提前下载并修改镜像地址 |
