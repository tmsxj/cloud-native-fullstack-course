# 模块20：数据库Operator实战

> 在Kubernetes上管理有状态应用（数据库）的最佳实践，使用Operator模式实现自动化运维。
> 
> **核心价值**: 将DBA运维经验编码为自动化控制器，实现数据库的声明式管理
> **适用场景**: 生产环境数据库部署、主从切换、备份恢复、版本升级
> **离线适配**: 所有镜像支持预推送到Harbor私有仓库

---

## 目录

1. [Operator模式概述](#1-operator模式概述)
2. [MySQL Operator实战](#2-mysql-operator实战)
3. [PostgreSQL Operator实战](#3-postgresql-operator实战)
4. [Redis Operator实战](#4-redis-operator实战)
5. [多数据库统一管理](#5-多数据库统一管理)
6. [备份与灾备策略](#6-备份与灾备策略)
7. [故障排查案例](#7-故障排查案例)
8. [CKA/CKS考点](#8-ckacks考点)
9. [高频面试题](#9-高频面试题)

---

## 1. Operator模式概述

### 1.1 什么是Operator

**Operator = CRD + Controller**

Operator(运维控制器)是Kubernetes的扩展模式，通过自定义资源定义(CRD, Custom Resource Definition)和控制器(Controller)来管理复杂有状态应用。

```
传统运维方式:
  手动部署 → 手动配置 → 手动备份 → 手动主从切换 → 手动故障恢复
  
Operator方式:
  声明期望状态 → Operator自动调谐 → 自动备份 → 自动故障切换 → 自动恢复
```

### 1.2 核心组件

| 组件 | 作用 | 示例 |
|------|------|------|
| **CRD** | 定义自定义资源结构 | `MySQLCluster`、`PostgresCluster` |
| **Controller** | 监控资源状态并调谐(Reconcile) | 检测Pod异常、触发主从切换 |
| **Webhook** | 资源验证和默认值注入(准入控制) | 校验存储大小、设置默认配置 |
| **Sidecar** | 辅助容器(备份、监控) | 定时备份Sidecar、Exporter |

### 1.3 为什么需要数据库Operator

| 场景 | 传统方式痛点 | Operator优势 |
|------|-------------|-------------|
| 主从切换 | 手动修改配置、重启服务、更新VIP | 自动检测故障、自动切换、自动更新Service |
| 备份恢复 | 手动执行mysqldump、异地存储 | 定时自动备份、支持S3/NFS存储、一键恢复 |
| 版本升级 | 停服升级、兼容性测试 | 滚动升级、自动兼容检查、回滚机制 |
| 扩缩容 | 手动修改配置、数据迁移 | 声明式扩容、自动数据同步 |
| 监控告警 | 单独部署Exporter | 内置Exporter、自动注册到Prometheus |

### 1.4 主流数据库Operator对比

| Operator | 维护方 | 成熟度 | 特性 | 推荐场景 |
|----------|--------|--------|------|----------|
| **MySQL Operator** | Oracle官方 | GA(正式发布) | InnoDB Cluster、路由器集成 | 生产MySQL集群 |
| **Vitess** | PlanetScale | GA | 分库分表(Sharding)、水平扩展 | 大规模MySQL分片 |
| **PostgreSQL Operator (PGO)** | CrunchyData | GA | 高可用、备份、监控 | 生产PostgreSQL |
| **Zalando Postgres Operator** | Zalando | GA | Patroni集成、简单易用 | 中小规模PG |
| **Redis Operator** | Spotahome | Beta | Redis Sentinel、Cluster | 缓存集群 |
| **MongoDB Community Operator** | MongoDB | GA | 副本集、分片 | 文档数据库 |

---

## 2. MySQL Operator实战

### 2.1 Oracle MySQL Operator简介

Oracle官方MySQL Operator基于MySQL InnoDB Cluster架构，提供：
- 高可用主从集群（Group Replication）
- 自动故障检测与切换
- MySQL Router作为访问层
- 自动备份与恢复

**架构图**:
```
                    ┌─────────────────────────────────────┐
                    │         MySQL Router                │
                    │   (读写分离、负载均衡、故障转移)      │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │ MySQL-0  │◄──────►│ MySQL-1  │◄──────►│ MySQL-2  │
        │ (Primary)│        │(Secondary)│       │(Secondary)│
        └──────────┘        └──────────┘        └──────────┘
              │                    │                    │
              └────────────────────┴────────────────────┘
                         Group Replication
```

### 2.2 离线部署准备

#### 2.2.1 镜像清单

```bash
# MySQL Operator镜像
mysql/mysql-operator:8.0.35-2.0.8
mysql/mysql-router:8.0.35
mysql/mysql-server:8.0.35

# 推送到Harbor
HARBOR="192.168.1.61:80"

# Operator镜像
docker pull mysql/mysql-operator:8.0.35-2.0.8
docker tag mysql/mysql-operator:8.0.35-2.0.8 ${HARBOR}/library/mysql-operator:8.0.35-2.0.8
docker push ${HARBOR}/library/mysql-operator:8.0.35-2.0.8

# MySQL Server镜像
docker pull mysql/mysql-server:8.0.35
docker tag mysql/mysql-server:8.0.35 ${HARBOR}/library/mysql-server:8.0.35
docker push ${HARBOR}/library/mysql-server:8.0.35

# MySQL Router镜像
docker pull mysql/mysql-router:8.0.35
docker tag mysql/mysql-router:8.0.35 ${HARBOR}/library/mysql-router:8.0.35
docker push ${HARBOR}/library/mysql-router:8.0.35
```

#### 2.2.2 Helm Chart离线准备

```bash
# 添加MySQL Operator Helm仓库（在线环境）
helm repo add mysql-operator https://mysql.github.io/mysql-operator/
helm repo update

# 下载Chart
helm pull mysql-operator/mysql-operator --version 2.0.8
# 得到 mysql-operator-2.0.8.tgz

# 传输到离线环境后安装
helm install mysql-operator ./mysql-operator-2.0.8.tgz \
  --namespace mysql-operator \
  --create-namespace \
  --set image.repo=${HARBOR}/library \
  --set image.tag=8.0.35-2.0.8
```

### 2.3 部署MySQL InnoDB Cluster

#### 2.3.1 创建命名空间和Secret

```yaml
# mysql-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mysql-cluster
---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-root-secret
  namespace: mysql-cluster
type: Opaque
stringData:
  rootUser: root
  rootPassword: MySQLRoot@123
```

```bash
kubectl apply -f mysql-namespace.yaml
```

#### 2.3.2 创建MySQL集群

```yaml
# mysql-cluster.yaml
apiVersion: mysql.oracle.com/v2
kind: InnoDBCluster  # MySQL InnoDB集群CRD
metadata:
  name: mysql-cluster
  namespace: mysql-cluster
spec:
  # 集群实例数（建议3节点，支持自动故障切换）
  instances: 3  # 实例数
  
  # MySQL版本
  version: "8.0.35"
  
  # 镜像配置（使用Harbor私有仓库）
  image: 192.168.1.61:80/library/mysql-server:8.0.35
  routerImage: 192.168.1.61:80/library/mysql-router:8.0.35
  
  # 根用户凭据
  secretRef:
    name: mysql-root-secret
  
  # 存储配置
  datadirVolumeClaimTemplate:
    accessModes:
      - ReadWriteOnce  # 单节点读写
    resources:
      requests:
        storage: 20Gi  # 存储大小
    storageClassName: local-path  # 存储类
  
  # MySQL Server配置
  mycnf: |
    [mysqld]
    max_connections = 1000
    innodb_buffer_pool_size = 1G
    innodb_log_file_size = 256M
    slow_query_log = 1
    long_query_time = 2
  
  # Router配置（读写分离）
  router:
    instances: 1  # Router实例数
    podSpec:
      containers:
        - name: router
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
  
  # Pod资源限制
  podSpec:
    containers:
      - name: mysql
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 2Gi
  
  # 服务配置
  service:
    type: ClusterIP
  
  # 初始化数据库（可选）
  initDB:
    name: init-db
    secretRef:
      name: mysql-root-secret
    # 初始化脚本（ConfigMap）
    configMapRef:
      name: mysql-init-scripts
```

```bash
kubectl apply -f mysql-cluster.yaml

# 查看集群状态
kubectl get innodbcluster -n mysql-cluster
kubectl describe innodbcluster mysql-cluster -n mysql-cluster

# 查看Pod
kubectl get pods -n mysql-cluster
# NAME                        READY   STATUS    RESTARTS   AGE
# mysql-cluster-0             2/2     Running   0          5m
# mysql-cluster-1             2/2     Running   0          4m
# mysql-cluster-2             2/2     Running   0          3m
# mysql-cluster-router-0      1/1     Running   0          2m
```

### 2.4 连接MySQL集群

#### 2.4.1 通过Router连接（推荐）

```bash
# Router提供统一入口，自动读写分离
# 写操作 -> Primary节点
# 读操作 -> Secondary节点（负载均衡）

# 获取Router Service
kubectl get svc -n mysql-cluster
# NAME                      TYPE        CLUSTER-IP      PORT(S)
# mysql-cluster             ClusterIP   10.96.100.10    3306/TCP,33060/TCP
# mysql-cluster-router      ClusterIP   10.96.100.11    6446/TCP,6447/TCP,6448/TCP

# 端口说明:
# 6446 - 读写端口（连接Primary）
# 6447 - 只读端口（连接Secondary，负载均衡）
# 6448 - R/W X端口（MySQL X Protocol）

# 临时Pod连接测试
kubectl run mysql-client --rm -it --restart=Never \
  --namespace=mysql-cluster \
  --image=192.168.1.61:80/library/mysql-server:8.0.35 \
  -- mysql -h mysql-cluster-router -P 6446 -u root -pMySQLRoot@123

# 在MySQL中验证集群状态
mysql> SELECT * FROM performance_schema.replication_group_members;
+---------------------------+--------------------------------------+-------------+-------------+--------------+-------------+----------------+
| CHANNEL_NAME              | MEMBER_ID                            | MEMBER_HOST | MEMBER_PORT | MEMBER_STATE | MEMBER_ROLE | MEMBER_VERSION |
+---------------------------+--------------------------------------+-------------+-------------+--------------+-------------+----------------+
| group_replication_applier | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | mysql-cluster-0.mysql-cluster | 3306 | ONLINE       | PRIMARY     | 8.0.35         |
| group_replication_applier | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | mysql-cluster-1.mysql-cluster | 3306 | ONLINE       | SECONDARY   | 8.0.35         |
| group_replication_applier | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | mysql-cluster-2.mysql-cluster | 3306 | ONLINE       | SECONDARY   | 8.0.35         |
+---------------------------+--------------------------------------+-------------+-------------+--------------+-------------+----------------+
```

#### 2.4.2 应用连接配置

```yaml
# 应用ConfigMap示例
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: default
data:
  # 写库连接（通过Router 6446端口）
  DATABASE_WRITE_URL: "mysql-cluster-router.mysql-cluster.svc.cluster.local:6446"
  # 读库连接（通过Router 6447端口）
  DATABASE_READ_URL: "mysql-cluster-router.mysql-cluster.svc.cluster.local:6447"
  DATABASE_USER: "root"
  DATABASE_PASSWORD: "MySQLRoot@123"
```

### 2.5 主从切换验证

```bash
# 模拟Primary故障
kubectl delete pod mysql-cluster-0 -n mysql-cluster

# 观察自动切换（约30秒内完成）
kubectl get innodbcluster mysql-cluster -n mysql-cluster -w

# 验证新Primary
kubectl exec -it mysql-cluster-1 -n mysql-cluster -- mysql -u root -pMySQLRoot@123 \
  -e "SELECT MEMBER_HOST, MEMBER_ROLE FROM performance_schema.replication_group_members"

# Router自动更新路由，应用无感知
```

### 2.6 备份与恢复

#### 2.6.1 配置自动备份

```yaml
# mysql-backup.yaml
apiVersion: mysql.oracle.com/v1
kind: MySQLBackup  # MySQL备份CRD
metadata:
  name: mysql-backup-daily
  namespace: mysql-cluster
spec:
  cluster:
    name: mysql-cluster
  
  # 备份存储位置
  storage:
    # 使用PVC存储
    persistentVolumeClaim:
      claimName: mysql-backup-pvc
  
  # 备份配置
  backupProfile:
    # 备份类型: physical (物理备份) 或 logical (逻辑备份，使用mysqldump)
    type: logical
    
    # 备份保留策略
    retention:
      keepLast: 7      # 保留最近7个备份
      keepDaily: 7     # 每日备份保留7天
  
  # 定时备份（Cron表达式）
  schedule: "0 2 * * *"  # 每天凌晨2点
```

#### 2.6.2 手动备份

```bash
# 创建一次性备份
kubectl apply -f - <<EOF
apiVersion: mysql.oracle.com/v1
kind: MySQLBackup
metadata:
  name: mysql-backup-manual-$(date +%Y%m%d)
  namespace: mysql-cluster
spec:
  cluster:
    name: mysql-cluster
  storage:
    persistentVolumeClaim:
      claimName: mysql-backup-pvc
  backupProfile:
    type: logical
EOF

# 查看备份状态
kubectl get mysqlbackup -n mysql-cluster
```

#### 2.6.3 恢复数据库

```yaml
# mysql-restore.yaml
apiVersion: mysql.oracle.com/v1
kind: MySQLRestore  # MySQL恢复CRD
metadata:
  name: mysql-restore-from-backup
  namespace: mysql-cluster
spec:
  cluster:
    name: mysql-cluster
  
  # 指定恢复的备份
  backup:
    name: mysql-backup-manual-20250124
```

```bash
kubectl apply -f mysql-restore.yaml
```

---

## 3. PostgreSQL Operator实战

### 3.1 CrunchyData PGO简介

CrunchyData PostgreSQL Operator (PGO) 是生产级PostgreSQL Operator，提供：
- 高可用主从集群（Patroni）
- 自动备份（pgBackRest）
- 连接池（PgBouncer）
- 监控集成（Postgres Exporter）

**架构图**:
```
                    ┌─────────────────────────────────────┐
                    │           PgBouncer                 │
                    │      (连接池、负载均衡)              │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │  PG-0    │◄──────►│  PG-1    │◄──────►│  PG-2    │
        │ (Primary)│        │(Replica) │        │(Replica) │
        └──────────┘        └──────────┘        └──────────┘
              │                    │                    │
              └────────────────────┴────────────────────┘
                      Patroni + pgBackRest
```

### 3.2 离线部署准备

#### 3.2.1 镜像清单

```bash
# PGO Operator镜像
crunchydata/pgo:5.5.0
crunchydata/pgo-event:5.5.0

# PostgreSQL镜像
crunchydata/crunchy-postgres:ubi8-15.5-0
crunchydata/crunchy-pgbackrest:ubi8-15.5-0
crunchydata/crunchy-pgbouncer:ubi8-15.5-0
crunchydata/crunchy-postgres-exporter:ubi8-15.5-0

# 推送到Harbor
HARBOR="192.168.1.80:80"

for img in pgo:5.5.0 pgo-event:5.5.0 \
           crunchy-postgres:ubi8-15.5-0 \
           crunchy-pgbackrest:ubi8-15.5-0 \
           crunchy-pgbouncer:ubi8-15.5-0 \
           crunchy-postgres-exporter:ubi8-15.5-0; do
  docker pull crunchydata/${img}
  docker tag crunchydata/${img} ${HARBOR}/library/${img}
  docker push ${HARBOR}/library/${img}
done
```

### 3.3 安装PGO Operator

```bash
# 下载PGO安装清单（在线环境）
curl -sL https://github.com/CrunchyData/postgres-operator-examples/raw/main/helm/install.yaml -o pgo-install.yaml

# 修改镜像地址为Harbor
sed -i 's|crunchydata/|192.168.1.61:80/library/|g' pgo-install.yaml

# 安装Operator
kubectl apply -f pgo-install.yaml

# 验证安装
kubectl get pods -n postgres-operator
# NAME                   READY   STATUS    RESTARTS   AGE
# pgo-xxxxxx-xxxx        1/1     Running   0          30s
```

### 3.4 创建PostgreSQL集群

```yaml
# postgres-cluster.yaml
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster  # PostgreSQL集群CRD
metadata:
  name: postgres-cluster
  namespace: postgres-cluster
spec:
  # PostgreSQL版本
  postgresVersion: 15
  
  # 镜像配置（使用Harbor）
  image: 192.168.1.61:80/library/crunchy-postgres:ubi8-15.5-0
  imagePullSecrets:
    - name: harbor-registry-secret
  
  # 实例配置
  instances:
    - name: instance1
      replicas: 3
      dataVolumeClaimSpec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
        storageClassName: local-path
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2000m
          memory: 2Gi
      # Sidecar配置
      sidecars:
        - name: exporter
          image: 192.168.1.61:80/library/crunchy-postgres-exporter:ubi8-15.5-0
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
  
  # Patroni高可用配置
  patroni:
    dynamicConfiguration:
      postgresql:
        parameters:
          max_connections: 500  # 最大连接数
          shared_buffers: 256MB  # 共享缓冲区
          work_mem: 4MB
          effective_cache_size: 1GB
      ttl: 30
      loop_wait: 10
      retry_timeout: 10
      maximum_lag_on_failover: 1048576
  
  # PgBouncer连接池(轻量级连接池)
  proxy:
    pgBouncer:
      image: 192.168.1.61:80/library/crunchy-pgbouncer:ubi8-15.5-0
      replicas: 2  # 连接池副本数
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 256Mi
  
  # pgBackRest备份配置(物理备份工具)
  backups:
    pgbackrest:
      image: 192.168.1.61:80/library/crunchy-pgbackrest:ubi8-15.5-0
      repos:
        - name: repo1
          volume:
            volumeClaimSpec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 50Gi
              storageClassName: local-path
      # 全量备份配置
      global:
        repo1-retention-full: "7"
        repo1-retention-diff: "7"
  
  # 用户和数据库
  users:
    - name: appuser
      databases:
        - appdb
      options: "CREATEDB"
  
  # 监控配置
  monitoring:
    pgMonitor:
      exporter:
        image: 192.168.1.61:80/library/crunchy-postgres-exporter:ubi8-15.5-0
```

```bash
# 创建命名空间
kubectl create namespace postgres-cluster

# 创建Harbor镜像拉取Secret
kubectl create secret docker-registry harbor-registry-secret \
  --namespace=postgres-cluster \
  --docker-server=192.168.1.61:80 \
  --docker-username=admin \
  --docker-password=Harbor12345

# 部署集群
kubectl apply -f postgres-cluster.yaml

# 查看状态
kubectl get postgrescluster -n postgres-cluster
kubectl get pods -n postgres-cluster
# NAME                                  READY   STATUS
# postgres-cluster-instance1-xxxx-0     4/4     Running
# postgres-cluster-instance1-xxxx-1     4/4     Running
# postgres-cluster-instance1-xxxx-2     4/4     Running
# postgres-cluster-pgbouncer-xxxx-0     1/1     Running
# postgres-cluster-pgbouncer-xxxx-1     1/1     Running
```

### 3.5 连接PostgreSQL集群

```bash
# 获取连接信息
kubectl get secrets -n postgres-cluster postgres-cluster-pguser-appuser -o yaml

# 连接信息
# host: postgres-cluster-pgbouncer.postgres-cluster.svc
# port: 5432
# user: appuser
# password: <从Secret获取>
# database: appdb

# 临时Pod连接测试
kubectl run pg-client --rm -it --restart=Never \
  --namespace=postgres-cluster \
  --image=192.168.1.61:80/library/crunchy-postgres:ubi8-15.5-0 \
  -- psql -h postgres-cluster-pgbouncer -U appuser -d appdb
```

### 3.6 备份与恢复

```bash
# 手动全量备份
kubectl patch postgrescluster postgres-cluster \
  --namespace=postgres-cluster \
  --type=merge \
  -p '{"spec":{"backups":{"pgbackrest":{"manual":{"repoName":"repo1","type":"full"}}}}}'

# 查看备份状态
kubectl get job -n postgres-cluster

# 恢复到新集群
# 修改PostgresCluster spec，指定restore配置
```

---

## 4. Redis Operator实战

### 4.1 Redis Operator简介

使用Spotahome Redis Operator管理Redis Sentinel或Redis Cluster模式。

### 4.2 离线部署

```bash
# 镜像清单
spotahome/redis-operator:v1.2.4
redis:7.2-alpine

# 推送到Harbor
HARBOR="192.168.1.61:80"
docker pull spotahome/redis-operator:v1.2.4
docker tag spotahome/redis-operator:v1.2.4 ${HARBOR}/library/redis-operator:v1.2.4
docker push ${HARBOR}/library/redis-operator:v1.2.4

docker pull redis:7.2-alpine
docker tag redis:7.2-alpine ${HARBOR}/library/redis:7.2-alpine
docker push ${HARBOR}/library/redis:7.2-alpine
```

### 4.3 安装Operator

```yaml
# redis-operator.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-operator  # Redis Operator控制器
  namespace: redis-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      name: redis-operator
  template:
    metadata:
      labels:
        name: redis-operator
    spec:
      serviceAccountName: redis-operator
      containers:
        - name: redis-operator
          image: 192.168.1.61:80/library/redis-operator:v1.2.4
          imagePullPolicy: Always
          env:
            - name: WATCH_NAMESPACE
              value: ""  # 监控所有命名空间
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: OPERATOR_NAME
              value: "redis-operator"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: redis-operator
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "endpoints", "persistentvolumeclaims", "events", "configmaps", "secrets"]
    verbs: ["*"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["*"]
  - apiGroups: ["redis.spotahome.com"]
    resources: ["redisfailovers", "redisfailovers/finalizers", "redisfailovers/status"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: redis-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: redis-operator
subjects:
  - kind: ServiceAccount
    name: redis-operator
    namespace: redis-operator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: redis-operator
  namespace: redis-operator
```

```bash
kubectl create namespace redis-operator
kubectl apply -f redis-operator.yaml
```

### 4.4 创建Redis Sentinel集群

```yaml
# redis-sentinel.yaml
apiVersion: redis.spotahome.com/v1
kind: RedisFailover  # Redis高可用CRD
metadata:
  name: redis-sentinel
  namespace: redis-cluster
spec:
  # Redis配置
  redis:
    replicas: 3  # Redis实例数
    image: 192.168.1.61:80/library/redis:7.2-alpine
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    storage:
      persistentVolumeClaim:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
        storageClassName: local-path
    # Redis配置
    customConfig:
      - "maxmemory 400mb"
      - "maxmemory-policy allkeys-lru"
      - "save 900 1"
      - "save 300 10"
      - "save 60 10000"
  
  # Sentinel配置(哨兵，负责故障检测和切换)
  sentinel:
    replicas: 3  # Sentinel实例数
    image: 192.168.1.61:80/library/redis:7.2-alpine
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 128Mi
    customConfig:
      - "down-after-milliseconds 5000"
      - "failover-timeout 10000"
      - "parallel-syncs 1"
```

```bash
kubectl create namespace redis-cluster
kubectl apply -f redis-sentinel.yaml

# 查看状态
kubectl get redisfailover -n redis-cluster
kubectl get pods -n redis-cluster
# NAME                              READY   STATUS
# redis-sentinel-redis-0            1/1     Running
# redis-sentinel-redis-1            1/1     Running
# redis-sentinel-redis-2            1/1     Running
# redis-sentinel-sentinel-0         1/1     Running
# redis-sentinel-sentinel-1         1/1     Running
# redis-sentinel-sentinel-2         1/1     Running
```

### 4.5 连接Redis集群

```bash
# Sentinel服务地址
kubectl get svc -n redis-cluster
# NAME                        TYPE        CLUSTER-IP
# redis-sentinel-redis        ClusterIP   10.96.200.10   (Master)
# redis-sentinel-redis-salve  ClusterIP   None           (Headless)
# redis-sentinel-sentinel     ClusterIP   10.96.200.11   (Sentinel)

# 通过Sentinel获取Master地址
kubectl run redis-client --rm -it --restart=Never \
  --namespace=redis-cluster \
  --image=192.168.1.61:80/library/redis:7.2-alpine \
  -- redis-cli -h redis-sentinel-sentinel SENTINEL get-master-addr-by-name mymaster

# 连接Master
kubectl run redis-client --rm -it --restart=Never \
  --namespace=redis-cluster \
  --image=192.168.1.61:80/library/redis:7.2-alpine \
  -- redis-cli -h redis-sentinel-redis
```

---

## 5. 多数据库统一管理

### 5.1 使用Crossplane统一管理

Crossplane可以统一管理多种云资源，包括数据库。

```yaml
# 示例：使用Crossplane管理MySQL和PostgreSQL
apiVersion: database.example.org/v1alpha1
kind: CompositeMySQLInstance
metadata:
  name: production-mysql
spec:
  parameters:
    storageGB: 20
    version: "8.0"
  compositionRef:
    name: mysql-composition
---
apiVersion: database.example.org/v1alpha1
kind: CompositePostgreSQLInstance
metadata:
  name: production-postgres
spec:
  parameters:
    storageGB: 20
    version: "15"
  compositionRef:
    name: postgres-composition
```

### 5.2 数据库服务目录

使用Backstage创建数据库服务目录，实现自助申请。

```yaml
# Backstage Template示例
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: mysql-cluster-template
  title: MySQL Cluster Request
spec:
  parameters:
    - title: Cluster Configuration
      properties:
        clusterName:
          title: Cluster Name
          type: string
        storageGB:
          title: Storage Size (GB)
          type: number
          default: 20
        replicas:
          title: Number of Replicas
          type: number
          default: 3
  steps:
    - id: create-cluster
      name: Create MySQL Cluster
      action: catalog:create
      input:
        entity:
          apiVersion: mysql.oracle.com/v2
          kind: InnoDBCluster
          metadata:
            name: ${{ parameters.clusterName }}
          spec:
            instances: ${{ parameters.replicas }}
            # ... 其他配置
```

---

## 6. 备份与灾备策略

### 6.1 备份策略对比

| 备份类型 | 工具 | 优点 | 缺点 | 适用场景 |
|----------|------|------|------|----------|
| **逻辑备份** | mysqldump/pg_dump | 灵活、可跨版本 | 慢、影响性能 | 小库、迁移 |
| **物理备份** | XtraBackup/pgBackRest | 快、一致性 | 需同版本 | 大库、生产 |
| **快照备份** | CSI Snapshot | 最快、无影响 | 依赖存储 | 云环境 |
| **增量备份** | binlog/WAL | 节省空间 | 恢复复杂 | 高频备份 |

### 6.2 统一备份方案（Velero + Operator）

```yaml
# Velero备份MySQL PVC
apiVersion: velero.io/v1
kind: Schedule  # Velero定时备份
metadata:
  name: mysql-backup-schedule
  namespace: velero
spec:
  schedule: "0 3 * * *"  # 每天凌晨3点
  template:
    includedNamespaces:
      - mysql-cluster
    storageLocation: default
    volumeSnapshotLocations:
      - default
    ttl: 168h0m0s  # 保留7天
    hooks:
      resources:
        - name: mysql-pre-backup-hook
          includedNamespaces:
            - mysql-cluster
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: database
          pre:
            - exec:
                container: mysql
                command:
                  - /bin/bash
                  - -c
                  - |
                    # 刷盘、获取一致性位置
                    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "FLUSH TABLES WITH READ LOCK; SYSTEM sync; SYSTEM sleep 5;"
                onError: Continue
                timeout: 60s
```

### 6.3 跨集群灾备

```yaml
# 使用MySQL Group Replication跨集群复制
# 主集群: cluster-a
# 备集群: cluster-b

# 主集群配置
mysql> CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='cluster-a-router.mysql-cluster-a.svc',
    SOURCE_PORT=3306,
    SOURCE_USER='repl',
    SOURCE_PASSWORD='repl_password',
    SOURCE_AUTO_POSITION=1;

mysql> START REPLICA;
```

---

## 7. 故障排查案例

### 7.1 案例1：MySQL集群脑裂

**现象**:
```
ERROR: Group has multiple primaries detected
```

**排查步骤**:
```bash
# 1. 检查各节点状态
kubectl exec -it mysql-cluster-0 -n mysql-cluster -- \
  mysql -u root -pMySQLRoot@123 \
  -e "SELECT * FROM performance_schema.replication_group_members"

# 2. 检查网络连通性
kubectl exec -it mysql-cluster-0 -n mysql-cluster -- \
  ping mysql-cluster-1.mysql-cluster

# 3. 检查Group Replication配置
kubectl exec -it mysql-cluster-0 -n mysql-cluster -- \
  mysql -u root -pMySQLRoot@123 \
  -e "SHOW VARIABLES LIKE 'group_replication%'"
```

**解决方案**:
```sql
-- 强制设置单Primary
SET GLOBAL group_replication_force_members = '<member1>:33061,<member2>:33061';
-- 或重启Group Replication
STOP GROUP_REPLICATION;
START GROUP_REPLICATION;
```

### 7.2 案例2：PostgreSQL主从延迟过大

**现象**:
```
Replication lag > 10s, queries returning stale data
```

**排查步骤**:
```bash
# 1. 检查复制延迟
kubectl exec -it postgres-cluster-instance1-xxxx-0 -n postgres-cluster -- \
  psql -U postgres -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, 
    (sent_lsn - replay_lsn) AS lag_bytes 
    FROM pg_stat_replication;"

# 2. 检查WAL生成速率
kubectl exec -it postgres-cluster-instance1-xxxx-0 -n postgres-cluster -- \
  psql -U postgres -c "SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());"

# 3. 检查网络带宽
kubectl exec -it postgres-cluster-instance1-xxxx-0 -n postgres-cluster -- \
  curl -o /dev/null -w "Speed: %{speed_download} bytes/sec\n" http://postgres-cluster-instance1-xxxx-1:8008
```

**解决方案**:
```yaml
# 调整Patroni配置，增加复制槽
spec:
  patroni:
    dynamicConfiguration:
      postgresql:
        parameters:
          max_replication_slots: 10
          wal_keep_size: 1GB
```

### 7.3 案例3：Redis Sentinel误判主库下线

**现象**:
```
Master marked as down by Sentinel, but actually running
```

**排查步骤**:
```bash
# 1. 检查Sentinel日志
kubectl logs redis-sentinel-sentinel-0 -n redis-cluster

# 2. 检查网络连通性
kubectl exec -it redis-sentinel-sentinel-0 -n redis-cluster -- \
  redis-cli -h redis-sentinel-redis ping

# 3. 检查Sentinel配置
kubectl exec -it redis-sentinel-sentinel-0 -n redis-cluster -- \
  redis-cli -h redis-sentinel-sentinel sentinel master mymaster
```

**解决方案**:
```yaml
# 调整Sentinel超时配置
spec:
  sentinel:
    customConfig:
      - "down-after-milliseconds 30000"  # 增加到30秒
      - "failover-timeout 60000"
```

---

## 8. CKA/CKS考点

### 8.1 CKA相关考点

| 考点 | 说明 |
|------|------|
| StatefulSet | 有状态应用部署、有序部署/删除、稳定网络标识 |
| Headless Service | StatefulSet关联服务、DNS解析 |
| PersistentVolume | 存储生命周期、回收策略 |
| Init Container | 初始化任务（如数据库初始化） |

### 8.2 CKS相关考点

| 考点 | 说明 |
|------|------|
| Secret管理 | 数据库凭据加密存储 |
| NetworkPolicy | 限制数据库访问来源 |
| Pod Security | 限制特权容器、只读根文件系统 |
| Image Security | 使用签名镜像、私有仓库认证 |

### 8.3 练习题

**题目1**: 创建一个MySQL StatefulSet，要求：
- 3副本
- 每个Pod 10Gi存储
- Headless Service
- 初始化脚本创建test数据库

<details>
<summary>答案</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
    - port: 3306
---
apiVersion: apps/v1
kind: StatefulSet  # 有状态应用部署
metadata:
  name: mysql
spec:
  serviceName: mysql-headless  # 关联Headless Service
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      initContainers:
        - name: init-mysql
          image: mysql:8.0
          command:
            - /bin/bash
            - -c
            - |
              if [ ! -d /var/lib/mysql/mysql ]; then
                mysql_install_db --user=mysql
                mysqld --user=mysql --bootstrap <<EOF
                CREATE DATABASE test;
                EOF
              fi
          volumeMounts:
            - name: data
              mountPath: /var/lib/mysql
      containers:
        - name: mysql
          image: mysql:8.0
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: password
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: data
              mountPath: /var/lib/mysql
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```
</details>

---

## 9. 高频面试题

### Q1: Operator相比Helm有什么优势？

**答案**:
- **生命周期管理**: Helm只负责部署，Operator负责整个生命周期（部署、升级、备份、故障恢复）
- **状态感知**: Operator持续监控资源状态，自动调谐到期望状态
- **领域知识**: Operator编码了DBA运维经验，自动处理主从切换、备份等复杂操作
- **Day-2运维**: Operator原生支持备份恢复、扩缩容、版本升级等运维操作

### Q2: MySQL Operator如何实现高可用？

**答案**:
1. 使用MySQL Group Replication实现主从复制
2. 多数节点在线才能写入（防脑裂）
3. 自动故障检测（心跳超时）
4. 自动主从切换（选举新Primary）
5. MySQL Router自动更新路由

### Q3: PostgreSQL Operator的备份机制是什么？

**答案**:
1. 使用pgBackRest进行物理备份
2. 支持全量、增量、差异备份
3. 备份存储在PVC或S3
4. 支持时间点恢复（PITR）
5. 定时备份通过CronJob实现

### Q4: 如何选择MySQL Operator和Vitess？

**答案**:
| 场景 | 推荐 |
|------|------|
| 单库 < 1TB | MySQL Operator |
| 需要分库分表 | Vitess |
| 水平扩展需求 | Vitess |
| 运维复杂度低 | MySQL Operator |
| 已有MySQL生态 | MySQL Operator |

### Q5: Redis Sentinel和Redis Cluster如何选择？

**答案**:
| 特性 | Sentinel | Cluster |
|------|----------|---------|
| 数据分片 | 不支持 | 支持（16384槽） |
| 高可用 | 支持 | 支持 |
| 客户端改造 | 小 | 大（需支持Cluster协议） |
| 运维复杂度 | 低 | 中 |
| 适用场景 | 缓存、小数据量 | 大数据量、需要分片 |

---

## 附录：资源需求参考

### 测试环境资源规划

| 数据库 | 实例数 | 每实例CPU | 每实例内存 | 存储 | 总计 |
|--------|--------|-----------|------------|------|------|
| MySQL Cluster | 3 | 500m | 1Gi | 20Gi | 1.5C/3Gi/60Gi |
| PostgreSQL Cluster | 3 | 500m | 1Gi | 20Gi | 1.5C/3Gi/60Gi |
| Redis Sentinel | 3+3 | 100m | 256Mi | 5Gi | 0.6C/1.5Gi/15Gi |

### 生产环境资源规划

| 数据库 | 实例数 | 每实例CPU | 每实例内存 | 存储 |
|--------|--------|-----------|------------|------|
| MySQL Cluster | 3 | 4 | 16Gi | 500Gi |
| PostgreSQL Cluster | 3 | 4 | 16Gi | 500Gi |
| Redis Cluster | 6 | 2 | 8Gi | 100Gi |

---

> **提示**: 数据库Operator是云原生数据管理的重要实践，建议在测试环境充分验证后再用于生产。备份恢复演练应定期执行，确保灾备方案有效。
