# 模块11：Nacos服务注册发现

---

## 1. 概述与架构图

### 1.1 Nacos 在微服务架构中的位置

```
+================================================================+
|                    Spring Cloud Alibaba 微服务架构                |
+================================================================+
|                                                                 |
|  +----------+  +----------+  +----------+  +----------+        |
|  | 用户服务  |  | 订单服务  |  | 库存服务  |  | 支付服务  |        |
|  | User Svc |  | Order Svc|  | Inv  Svc |  | Pay  Svc |        |
|  +----+-----+  +----+-----+  +----+-----+  +----+-----+        |
|       |              |              |              |             |
|       +--------------+--------------+--------------+             |
|                      |                                      |
|              服务注册/发现 + 配置中心                         |
|                      |                                      |
|              +-------+-------+                              |
|              |    Nacos      |                              |
|              |  (AP/CP 双模) |                              |
|              +-------+-------+                              |
|                      |                                      |
|              +-------+-------+                              |
|              |   MySQL 8.0   |  (外部存储)                   |
|              +---------------+                              |
|                                                                 |
|  +----------+  +----------+  +----------+                      |
|  | Sentinel |  |  Kafka   |  | Seata    |                      |
|  | (流控)   |  | (消息)   |  | (分布式事务)|                     |
|  +----------+  +----------+  +----------+                      |
+================================================================+
```

### 1.2 Nacos 集群架构

```
+================================================================+
|                    Nacos 集群 (3 节点)                          |
+================================================================+
|                                                                 |
|  +------------------+  +------------------+  +------------------+|
|  | Nacos Server 1   |  | Nacos Server 2   |  | Nacos Server 3   ||
|  | (192.168.1.54)   |  | (192.168.1.55)   |  | (192.168.1.56 <!-- NOTE: verify this IP exists in your environment -->)   ||
|  |                  |  |                  |  |                  ||
|  | +--NamingService+|  | +--NamingService+|  | +--NamingService+||
|  | | 服务注册/发现  ||  | | 服务注册/发现  ||  | | 服务注册/发现  ||
|  | +---------------+|  | +---------------+|  | +---------------+||
|  | +--ConfigService+|  | +--ConfigService+|  | +--ConfigService+||
|  | | 配置管理       ||  | | 配置管理       ||  | | 配置管理       ||
|  | +---------------+|  | +---------------+|  | +---------------+||
|  | +--Consistency  +|  | +--Consistency  +|  | +--Consistency  +||
|  | | AP(Distro)     ||  | | AP(Distro)     ||  | | AP(Distro)     ||
|  | | CP(Raft)       ||  | | CP(Raft)       ||  | | CP(Raft)       ||
|  | +---------------+|  | +---------------+|  | +---------------+||
|  +--------+---------+  +--------+---------+  +--------+---------+|
|           |                    |                    |              |
|           +--------------------+--------------------+              |
|                    Raft 协议 (CP 模式)                         |
|                    Distro 协议 (AP 模式)                        |
+================================================================+
           |
     +-----+-----+
     |  MySQL 8.0 |  (外部数据存储)
     +-----------+
```

### 1.3 服务注册与发现流程

```
服务注册流程:
  Order Svc                Nacos Server              User Svc
     |                          |                        |
     |--1. POST /nacos/v1/ns/instance-->|               |
     |   (ip, port, serviceName,       |               |
     |    metadata, weight)             |               |
     |                          |                        |
     |<--2. 200 OK (注册成功)---|               |
     |                          |                        |
     |                          |<--3. POST /nacos/v1/ns/instance
     |                          |   (User Svc 注册)      |
     |                          |                        |
     |                          |--4. 200 OK------------>|
     |                          |                        |
     |                          |<--5. GET /nacos/v1/ns/instance/list
     |                          |   (查询 Order Svc 地址) |
     |                          |                        |
     |                          |--6. 返回 Order Svc 实例列表->|

服务发现流程:
  Consumer                  Nacos Server              Provider
     |                          |                        |
     |--1. GET /nacos/v1/ns/instance/list-->|           |
     |   (serviceName=order-service)        |           |
     |                          |                        |
     |<--2. 返回实例列表 (IP:Port + 元数据)--|           |
     |    [192.168.1.10:8080 (healthy),     |           |
     |     192.168.1.11:8080 (healthy)]     |           |
     |                          |                        |
     |--3. 负载均衡选择实例------|-------->              |
     |   (Ribbon/LoadBalancer)  |                        |
     |                          |                        |
     |--4. HTTP RPC 调用-------|-------->              |
     |                          |                        |
     |<--5. 响应----------------|-------->              |
```

---

## 2. 理论基础

### 2.1 Nacos 核心概念

| 概念 | 说明 |
|------|------|
| Namespace | 命名空间，用于隔离不同环境的配置和服务（如 dev/test/prod） |
| Group | 分组，同一命名空间内的逻辑分组（如 DEFAULT_GROUP） |
| Service | 服务名，微服务的唯一标识 |
| Instance | 服务实例，包含 IP、Port、权重、健康状态等 |
| Cluster | 集群，同一服务下按地域或机房分组 |
| Configuration | 配置项，包含 Data ID、Group、Content |
| Data ID | 配置的唯一标识，通常为 `服务名-环境.文件格式`（如 `order-service-dev.yaml`） |

### 2.2 AP/CP 双模一致性

Nacos 支持两种一致性协议，可以根据场景切换：

| 模式 | 协议 | 适用场景 | 特点 |
|------|------|---------|------|
| AP | Distro（临时实例一致性协议） | 服务注册发现 | 最终一致性，高可用，牺牲一致性换可用性 |
| CP | Raft | 配置管理 | 强一致性，牺牲可用性换一致性 |

**Distro 协议（AP 模式）：**
- 每个 Nacos 节点存储全量服务数据
- 节点间通过定时同步（每秒）保持数据最终一致
- 客户端注册到任意节点，该节点负责同步到其他节点
- 适合服务注册场景（临时实例），允许短暂不一致

**Raft 协议（CP 模式）：**
- Leader-Follower 模式，所有写操作通过 Leader
- 多数派确认后写入成功（3 节点需 2 个确认）
- 适合配置管理场景，确保所有节点配置一致
- Leader 选举期间不可写入（约 1-2 秒）

### 2.3 Nacos vs Eureka（Netflix 服务发现） vs Consul（HashiCorp 服务网格） vs ZooKeeper

| 特性 | Nacos | Eureka | Consul | ZooKeeper |
|------|-------|--------|--------|-----------|
| 一致性 | AP/CP 可切换 | AP | CP | CP |
| 健康检查 | TCP/HTTP/MySQL | 心跳 | TCP/HTTP/gRPC（远程调用框架） | 心跳 |
| 配置中心 | 内置 | 不支持 | KV 存储 | 不支持 |
| 服务分组 | Namespace/Group | Region/Zone | Datacenter | Chroot |
| 权重路由 | 支持 | 不支持 | 不支持 | 不支持 |
| 长轮询 | 支持 | 不支持 | 不支持 | Watch |
| Spring Cloud | Alibaba | Netflix | HashiCorp | Apache |
| 维护状态 | 活跃 | 停止维护 | 活跃 | 活跃 |
| K8s 集成 | Helm（K8s 包管理器） | Helm | Helm | Operator |

### 2.4 Nacos 配置中心

```
配置管理流程:
  +----------+     +----------+     +----------+     +----------+
  | Nacos    |     | 应用     |     | 应用     |     | 应用     |
  | Console  |     | (Dev)    |     | (Test)   |     | (Prod)   |
  +----+-----+     +----+-----+     +----+-----+     +----+-----+
       |                |                |                |
       |--发布配置----->|                |                |
       | order-svc.yaml |                |                |
       |                |                |                |
       |                |--长轮询-------->|                |
       |                | (配置变更检测)  |                |
       |                |                |                |
       |<--修改配置------|                |                |
       | (灰度发布)     |                |                |
       |                |                |                |
       |--推送变更------|                |                |
       | (只推送给灰度) |                |                |
       |                |                |                |
       |--全量发布------|------>|-------->|                |
       | (推送给所有)   |       |        |                |
```

**配置加载优先级（从高到低）：**
1. JVM 参数（`-D`）
2. 本地配置文件（`application.yaml`）
3. Nacos 配置中心（`bootstrap.yaml` + Nacos Config）
4. Nacos 共享配置（`shared-configs`）

---

## 3. 离线前置准备

> **说明：** 本节适用于无外网访问的离线 K8s 集群环境。所有镜像和 Helm Chart 需在有网络的机器上提前下载，然后导入到离线环境。

### 3.1 镜像离线准备

```bash
# ===== 在有网络的机器上执行 =====

# 1. 拉取所需镜像
docker pull mysql:8.0
docker pull nacos/nacos-server:v2.4.3
docker pull bladex/sentinel-dashboard:1.8.6

# 2. 重新打标签，推送到 Harbor 私有仓库
# 注意：Harbor 使用 HTTP 协议，需在 docker 客户端配置 insecure-registries
# echo '{ "insecure-registries": ["192.168.1.61"] }' > /etc/docker/daemon.json
# systemctl restart docker

docker tag mysql:8.0 192.168.1.61/library/mysql:8.0
docker tag nacos/nacos-server:v2.4.3 192.168.1.61/nacos/nacos-server:v2.4.3
docker tag bladex/sentinel-dashboard:1.8.6 192.168.1.61/sentinel/sentinel-dashboard:1.8.6

# 3. 登录 Harbor 并推送
docker login 192.168.1.61 -u admin -p Harbor12345

docker push 192.168.1.61/library/mysql:8.0
docker push 192.168.1.61/nacos/nacos-server:v2.4.3
docker push 192.168.1.61/sentinel/sentinel-dashboard:1.8.6

# 4. （备选方案）如果无法直接推送，可导出为 tar 文件后拷贝到离线环境
docker save mysql:8.0 nacos/nacos-server:v2.4.3 bladex/sentinel-dashboard:1.8.6 -o nacos-images.tar
# 拷贝到离线环境后：
# docker load -i nacos-images.tar
# 然后在离线环境中重新打标签并推送到 Harbor
```

### 3.2 Helm Chart 离线准备

```bash
# ===== 在有网络的机器上执行 =====

# 1. 添加 Helm 仓库并下载 Chart
# helm repo add nacos https://nacos-io.github.io/helm-charts/
# 离线环境: 参考第3节离线前置准备，使用 helm pull + 本地安装
helm repo update
helm pull nacos/nacos

# 2. 将 nacos-<版本号>.tgz 拷贝到离线环境的任意节点

# ===== 在离线 K8s 集群的 Master 节点上执行 =====

# 3. 解压 Helm Chart
tar zxvf nacos-*.tgz

# 4. 验证 Chart 已就绪
ls -l nacos/
# 预期：Chart.yaml  values.yaml  templates/ ...
```

### 3.3 离线环境 K8s 节点镜像拉取配置

```bash
# ===== 在离线 K8s 集群的所有 Worker 和 Master 节点上执行 =====

# 配置 containerd 拉取 Harbor 私有仓库镜像（HTTP 协议）
# 编辑 /etc/containerd/config.toml，添加 Harbor 的 insecure 配置
# 如果使用 Docker 作为容器运行时，需配置 /etc/docker/daemon.json

# containerd 方式（推荐）：
# 在 /etc/containerd/config.toml 中添加：
# [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.61".tls]
#   insecure_skip_verify = true
# [plugins."io.containerd.grpc.v1.cri".registry.auths."192.168.1.61"]
#   auth_type = "basic"
#   username = "admin"
#   password = "Harbor12345"
#
# 然后重启 containerd：
# systemctl restart containerd

# 验证镜像拉取：
# crictl pull 192.168.1.61/library/mysql:8.0
# crictl pull 192.168.1.61/nacos/nacos-server:v2.4.3
```

### 3.4 环境信息确认

```bash
# 确认 K8s 集群版本
kubectl version --short

# 确认节点资源
kubectl top nodes

# 确认 StorageClass 可用
kubectl get sc
# 预期：local-path (default)

# 确认 Harbor 可达
curl -u admin:Harbor12345 http://192.168.1.61/api/v2.0/systeminfo
```

---

## 4. 部署实战

### 4.1 部署 MySQL 8.0（Nacos 外部存储）

```bash
# 创建 MySQL 命名空间
kubectl create namespace middleware

# 部署 MySQL 8.0
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1  # API 版本
kind: Deployment  # K8s 部署
metadata:
  name: mysql
  namespace: middleware
  labels:
    app: mysql
spec:
  replicas: 1  # 副本数: 1
  strategy:
    type: Recreate  # 重建更新策略
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: 192.168.1.61/library/mysql:8.0  # 镜像地址(Harbor)
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD  # MySQL root 密码
          value: "Nacos@2024"
        - name: MYSQL_DATABASE  # 数据库名称
          value: "nacos"
        - name: MYSQL_CHARACTER_SET_SERVER
          value: "utf8mb4"
        - name: MYSQL_COLLATION_SERVER
          value: "utf8mb4_unicode_ci"
        resources:
          requests:
            cpu: 250m  # CPU 250m
            memory: 512Mi  # 内存 512Mi
          limits:
            cpu: 1000m  # CPU 1000m
            memory: 2Gi  # 内存 2Gi
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
        livenessProbe:
          exec:
            command:
            - mysqladmin
            - ping
            - -h
            - localhost
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - mysql
            - -h
            - localhost
            - -u
            - root
            - -pNacos@2024
            - -e
            - "SELECT 1"
          initialDelaySeconds: 10
          periodSeconds: 10
      volumes:
      - name: mysql-data
        persistentVolumeClaim:
          claimName: mysql-data
---
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: mysql
  namespace: middleware
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
  type: ClusterIP  # 集群内部访问
---
apiVersion: v1  # API 版本
kind: PersistentVolumeClaim  # PVC 持久卷声明
metadata:
  name: mysql-data
  namespace: middleware
spec:
  accessModes:
  - ReadWriteOnce  # 单节点读写
  storageClassName: local-path  # 存储类名称
  resources:
    requests:
      storage: 20Gi
EOF

# 等待 MySQL 就绪
kubectl rollout status deployment/mysql -n middleware --timeout=120s

# 初始化 Nacos 数据库表
kubectl exec -it deploy/mysql -n middleware -- mysql -u root -p'Nacos@2024' nacos <<'SQL'
-- Nacos 初始化 SQL（从 Nacos GitHub 获取）
-- https://raw.githubusercontent.com/alibaba/nacos/2.4.3/distribution/conf/mysql-schema.sql

CREATE TABLE IF NOT EXISTS `config_info` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT 'id',
  `data_id` varchar(255) NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) DEFAULT NULL COMMENT 'group_id',
  `content` longtext NOT NULL COMMENT 'content',
  `md5` varchar(32) DEFAULT NULL COMMENT 'md5',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '修改时间',
  `src_user` text COMMENT 'source user',
  `src_ip` varchar(50) DEFAULT NULL COMMENT 'source ip',
  `app_name` varchar(128) DEFAULT NULL,
  `tenant_id` varchar(128) DEFAULT '' COMMENT '租户字段',
  `c_desc` varchar(256) DEFAULT NULL,
  `c_use` varchar(64) DEFAULT NULL,
  `effect` varchar(64) DEFAULT NULL,
  `type` varchar(64) DEFAULT NULL,
  `c_schema` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_configinfo_datagrouptenant` (`data_id`,`group_id`,`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='config_info';

CREATE TABLE IF NOT EXISTS `config_info_aggr` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT 'id',
  `data_id` varchar(255) NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) NOT NULL COMMENT 'group_id',
  `datum_id` varchar(255) NOT NULL COMMENT 'datum_id',
  `content` longtext NOT NULL COMMENT '内容',
  `gmt_modified` datetime NOT NULL COMMENT '修改时间',
  `app_name` varchar(128) DEFAULT NULL,
  `tenant_id` varchar(128) DEFAULT '' COMMENT '租户字段',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_configinfoaggr_datagrouptenantdatum` (`data_id`,`group_id`,`tenant_id`,`datum_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='增加租户字段';

CREATE TABLE IF NOT EXISTS `config_info_beta` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT 'id',
  `data_id` varchar(255) NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) NOT NULL COMMENT 'group_id',
  `app_name` varchar(128) DEFAULT NULL COMMENT 'app_name',
  `content` longtext NOT NULL COMMENT 'content',
  `beta_ips` varchar(1024) DEFAULT NULL COMMENT 'betaIps',
  `md5` varchar(32) DEFAULT NULL COMMENT 'md5',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '修改时间',
  `src_user` text COMMENT 'source user',
  `src_ip` varchar(50) DEFAULT NULL COMMENT 'source ip',
  `tenant_id` varchar(128) DEFAULT '' COMMENT '租户字段',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_configinfobeta_datagrouptenant` (`data_id`,`group_id`,`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='config_info_beta';

CREATE TABLE IF NOT EXISTS `config_info_tag` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT 'id',
  `data_id` varchar(255) NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) NOT NULL COMMENT 'group_id',
  `tenant_id` varchar(128) DEFAULT '' COMMENT 'tenant_id',
  `tag_id` varchar(128) NOT NULL COMMENT 'tag_id',
  `app_name` varchar(128) DEFAULT NULL COMMENT 'app_name',
  `content` longtext NOT NULL COMMENT 'content',
  `md5` varchar(32) DEFAULT NULL COMMENT 'md5',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '修改时间',
  `src_user` text COMMENT 'source user',
  `src_ip` varchar(50) DEFAULT NULL COMMENT 'source ip',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_configinfotag_datagrouptenanttag` (`data_id`,`group_id`,`tenant_id`,`tag_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='config_info_tag';

CREATE TABLE IF NOT EXISTS `config_tags_relation` (
  `id` bigint(20) NOT NULL COMMENT 'id',
  `tag_name` varchar(128) NOT NULL COMMENT 'tag_name',
  `tag_type` varchar(64) DEFAULT NULL COMMENT 'tag_type',
  `data_id` varchar(255) NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) NOT NULL COMMENT 'group_id',
  `tenant_id` varchar(128) DEFAULT '' COMMENT 'tenant_id',
  `nid` bigint(20) NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`nid`),
  UNIQUE KEY `uk_configtagsrelation_configidtag` (`id`,`tag_name`,`tag_type`),
  KEY `idx_tenant_id` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='config_tag_relation';

CREATE TABLE IF NOT EXISTS `group_capacity` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `group_id` varchar(128) NOT NULL DEFAULT '' COMMENT 'Group ID',
  `quota` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '配额，0表示使用默认值',
  `usage` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '使用量',
  `max_size` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '单个配置大小上限，单位为字节，0表示使用默认值',
  `max_aggr_count` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '最大聚合配置数',
  `max_aggr_size` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '单个聚合数据的子配置大小上限，单位为字节，0表示使用默认值',
  `max_history_count` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '最大变更历史数量',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '修改时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_group_id` (`group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='集群、各Group容量信息表';

CREATE TABLE IF NOT EXISTS `his_config_info` (
  `id` bigint(20) unsigned NOT NULL,
  `nid` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `data_id` varchar(255) NOT NULL,
  `group_id` varchar(128) NOT NULL,
  `app_name` varchar(128) DEFAULT NULL,
  `content` longtext NOT NULL,
  `md5` varchar(32) DEFAULT NULL,
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `src_user` text,
  `src_ip` varchar(50) DEFAULT NULL,
  `op_type` char(10) DEFAULT NULL,
  `tenant_id` varchar(128) DEFAULT '' COMMENT '租户字段',
  `nav_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`nid`),
  KEY `idx_gmt_create` (`gmt_create`),
  KEY `idx_gmt_modified` (`gmt_modified`),
  KEY `idx_did` (`data_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='多租户改造';

CREATE TABLE IF NOT EXISTS `tenant_capacity` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `tenant_id` varchar(128) NOT NULL DEFAULT '' COMMENT 'Tenant ID',
  `quota` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '配额，0表示使用默认值',
  `usage` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '使用量',
  `max_size` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '单个配置大小上限，单位为字节，0表示使用默认值',
  `max_aggr_count` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '最大聚合配置数',
  `max_aggr_size` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '单个聚合数据的子配置大小上限，单位为字节，0表示使用默认值',
  `max_history_count` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '最大变更历史数量',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '修改时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_tenant_id` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='租户容量信息表';

CREATE TABLE IF NOT EXISTS `tenant_info` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT 'id',
  `kp` varchar(128) NOT NULL COMMENT 'kp',
  `tenant_id` varchar(128) default '' COMMENT 'tenant_id',
  `tenant_name` varchar(128) default '' COMMENT 'tenant_name',
  `tenant_desc` varchar(256) DEFAULT NULL COMMENT 'tenant_desc',
  `create_source` varchar(32) DEFAULT NULL COMMENT 'create_source',
  `gmt_create` bigint(20) NOT NULL COMMENT '创建时间',
  `gmt_modified` bigint(20) NOT NULL COMMENT '修改时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_tenant_info_kptenantid` (`kp`,`tenant_id`),
  KEY `idx_tenant_id` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='tenant_info';

CREATE TABLE IF NOT EXISTS `users` (
  `username` varchar(50) NOT NULL PRIMARY KEY,
  `password` varchar(500) NOT NULL,
  `enabled` boolean NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `roles` (
  `username` varchar(50) NOT NULL,
  `role` varchar(50) NOT NULL,
  UNIQUE INDEX `idx_user_role` (`username` ASC, `role` ASC) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `permissions` (
  `role` varchar(50) NOT NULL,
  `resource` varchar(255) NOT NULL,
  `action` varchar(8) NOT NULL,
  UNIQUE INDEX `uk_role_permission` (`role`,`resource`,`action`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- 初始化管理员账号
INSERT INTO users (username, password, enabled) VALUES ('nacos', '$2a$10$EuWPZHzz32dJN7jexM34MOeYirDdFAZm2kuWj7VEOJhhZkDrxfvUu', TRUE);
INSERT INTO roles (username, role) VALUES ('nacos', 'ROLE_ADMIN');
SQL

# 验证 MySQL 初始化
kubectl exec -it deploy/mysql -n middleware -- mysql -u root -p'Nacos@2024' nacos -e "SHOW TABLES;"
```

### 4.2 Helm 部署 Nacos 集群

```bash
# 离线安装 Helm Chart（在有网络的机器上提前下载）
# helm pull nacos/nacos --version <对应版本号>
# 将 nacos-<版本号>.tgz 传到离线环境中

# 解压 Helm Chart
tar zxvf nacos-*.tgz

# 创建 Nacos 配置
cat <<'EOF' > nacos-values.yaml
global:
  mode: cluster  # 集群模式

# 集群配置
cluster:
  enabled: true
  replicas: 3  # 副本数: 3

# Nacos Server 配置
nacos:
  image:
    repository: 192.168.1.61/nacos/nacos-server
    tag: v2.4.3
  env:
    # 数据源配置
    SPRING_DATASOURCE_PLATFORM: "mysql"
    MYSQL_SERVICE_HOST: "mysql.middleware.svc.cluster.local"
    MYSQL_SERVICE_PORT: "3306"
    MYSQL_SERVICE_DB_NAME: "nacos"
    MYSQL_SERVICE_USER: "root"
    MYSQL_SERVICE_PASSWORD: "Nacos@2024"
    # 集群配置
    NACOS_SERVERS: "nacos-0.nacos-headless.middleware.svc.cluster.local:8848 nacos-1.nacos-headless.middleware.svc.cluster.local:8848 nacos-2.nacos-headless.middleware.svc.cluster.local:8848"
    # JVM 配置
    JAVA_XMS: "512m"
    JAVA_XMX: "512m"
    JAVA_XMN: "256m"
    # 持久化配置
    PREFER_HOST_MODE: "hostname"
    MODE: "cluster"
  # 资源配置（适配 Worker 4C8G 节点）
  resources:
    requests:
      cpu: 250m  # CPU 250m
      memory: 512Mi  # 内存 512Mi
    limits:
      cpu: 1000m  # CPU 1000m
      memory: 1Gi  # 内存 1Gi

# Service 配置
service:
  type: NodePort
  port: 8848  # 服务端口
  nodePort: 30848  # NodePort 端口

# 持久化
persistence:
  enabled: false  # 关闭持久化

# RBAC
rbac:
  create: true  # 创建 RBAC 权限

# Pod 反亲和性（使用软反亲和性，适配小规模集群）
podAntiAffinity:  # Pod 反亲和性
  type: soft  # 软反亲和性

# 容忍 Master 节点污点（允许调度到 Master 节点，适配小规模集群）
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
EOF

# 安装 Nacos（使用本地离线 Chart）
helm install nacos ./nacos \
  --namespace middleware \
  --values nacos-values.yaml \
  --wait --timeout 300s

# 验证安装
kubectl get pods -n middleware -l app=nacos
# 预期：nacos-0, nacos-1, nacos-2 Running

kubectl get svc -n middleware
# 预期：nacos NodePort 8848:30848

# 访问 Nacos 控制台
# http://192.168.1.54:30848/nacos
# 默认账号：nacos / nacos
```

### 4.3 Spring Boot 服务注册到 Nacos

```bash
# Spring Boot 应用配置（bootstrap.yml）
cat <<'EOF' > bootstrap.yml
spring:
  application:
    name: order-service
  cloud:
    nacos:
      # 服务注册发现配置
      discovery:
        server-addr: nacos.middleware.svc.cluster.local:8848  # Nacos 服务地址
        namespace: production  # 生产环境命名空间
        group: DEFAULT_GROUP
        cluster-name: SH-BJ
        weight: 1.0  # 实例权重
        # 健康检查
        heart-beat-interval: 5000  # 心跳间隔(毫秒)
        heart-beat-timeout: 15000  # 心跳超时(毫秒)
        ip-delete-timeout: 30000
        # 元数据
        metadata:
          version: v1.0.0
          region: cn-east
          env: production
          protocol: grpc
        # 命名空间自动注册
        register-enabled: true
      # 配置中心
      config:
        server-addr: nacos.middleware.svc.cluster.local:8848  # Nacos 服务地址
        namespace: production  # 生产环境命名空间
        group: DEFAULT_GROUP
        file-extension: yaml  # 配置文件格式
        # 共享配置
        shared-configs:
          - data-id: common.yaml
            group: DEFAULT_GROUP
            refresh: true
          - data-id: redis-config.yaml
            group: DEFAULT_GROUP
            refresh: true
        # 长轮询超时
        timeout: 30000  # 长轮询超时(毫秒)
        # 配置刷新
        refresh-enabled: true  # 启用配置热刷新
EOF

# Spring Boot 主类
cat <<'EOF' > OrderServiceApplication.java
package com.demo.order;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;
import org.springframework.cloud.client.loadbalancer.LoadBalanced;
import org.springframework.context.annotation.Bean;
import org.springframework.web.client.RestTemplate;

@SpringBootApplication
@EnableDiscoveryClient
public class OrderServiceApplication {

    @Bean
    @LoadBalanced
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }

    public static void main(String[] args) {
        SpringApplication.run(OrderServiceApplication.class, args);
    }
}
EOF

# 服务调用示例（通过 Nacos 服务名调用）
cat <<'EOF' > OrderController.java
package com.demo.order.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cloud.client.discovery.DiscoveryClient;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    @Autowired
    private RestTemplate restTemplate;

    @Autowired
    private DiscoveryClient discoveryClient;

    // 通过服务名调用用户服务
    @GetMapping("/{orderId}")
    public Map<String, Object> getOrder(@PathVariable String orderId) {
        // 使用服务名 + LoadBalancer 调用
        String userUrl = "http://user-service/api/users/current";
        Map<String, Object> user = restTemplate.getForObject(userUrl, Map.class);

        // 获取服务实例列表
        var instances = discoveryClient.getInstances("user-service");
        System.out.println("User service instances: " + instances.size());

        return Map.of("orderId", orderId, "user", user);
    }
}
EOF
```

### 4.4 配置中心 -- 配置管理

```bash
# 通过 Nacos Open API 创建配置
# 1. 创建公共配置
curl -X POST "http://192.168.1.54:30848/nacos/v1/cs/configs" \
  -d "dataId=common.yaml&group=DEFAULT_GROUP&content=$(cat <<'YAML'
spring:
  jackson:
    date-format: yyyy-MM-dd HH:mm:ss
    time-zone: Asia/Shanghai
  servlet:
    multipart:
      max-file-size: 50MB
      max-request-size: 50MB

logging:
  level:
    root: INFO
    com.demo: DEBUG
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] [%X{traceId}/%X{spanId}] %-5level %logger{36} - %msg%n"

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics
  endpoint:
    health:
      show-details: always
YAML
)"

# 2. 创建 Redis 配置
curl -X POST "http://192.168.1.54:30848/nacos/v1/cs/configs" \
  -d "dataId=redis-config.yaml&group=DEFAULT_GROUP&content=$(cat <<'YAML'
spring:
  redis:
    host: redis.middleware.svc.cluster.local
    port: 6379
    password: Redis12345
    database: 0
    lettuce:
      pool:
        max-active: 50
        max-idle: 20
        min-idle: 5
        max-wait: 3000ms
      timeout: 5000ms
YAML
)"

# 3. 创建订单服务配置
curl -X POST "http://192.168.1.54:30848/nacos/v1/cs/configs" \
  -d "dataId=order-service.yaml&group=DEFAULT_GROUP&content=$(cat <<'YAML'
server:
  port: 8080  # 服务端口

order:
  max-retry: 3
  timeout: 5000
  inventory-check-enabled: true

spring:
  datasource:
    url: jdbc:mysql://mysql.middleware.svc.cluster.local:3306/order_db
    username: order_user
    password: Order@2024
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000
YAML
)"

# 4. 创建命名空间
curl -X POST "http://192.168.1.54:30848/nacos/v1/console/namespaces" \
  -d "customNamespaceId=production&namespaceName=生产环境&namespaceDesc=生产环境命名空间"

curl -X POST "http://192.168.1.54:30848/nacos/v1/console/namespaces" \
  -d "customNamespaceId=staging&namespaceName=预发环境&namespaceDesc=预发环境命名空间"

curl -X POST "http://192.168.1.54:30848/nacos/v1/console/namespaces" \
  -d "customNamespaceId=dev&namespaceName=开发环境&namespaceDesc=开发环境命名空间"

# 5. 验证配置
curl -X GET "http://192.168.1.54:30848/nacos/v1/cs/configs?dataId=common.yaml&group=DEFAULT_GROUP"
```

### 4.5 配置热更新与 Beta 灰度

```bash
# 1. 发布 Beta 灰度配置（只推送给指定 IP）
curl -X POST "http://192.168.1.54:30848/nacos/v1/cs/configs" \
  -d "dataId=order-service.yaml&group=DEFAULT_GROUP&betaIps=192.168.1.100&content=$(cat <<'YAML'
server:
  port: 8080  # 服务端口

order:
  max-retry: 5
  timeout: 8000
  inventory-check-enabled: true
  new-feature-enabled: true
YAML
)"

# 2. 验证 Beta 配置（只有指定 IP 能看到）
curl -X GET "http://192.168.1.54:30848/nacos/v1/cs/configs?dataId=order-service.yaml&group=DEFAULT_GROUP&beta=true"

# 3. 确认无误后全量发布
curl -X POST "http://192.168.1.54:30848/nacos/v1/cs/configs" \
  -d "dataId=order-service.yaml&group=DEFAULT_GROUP&content=$(cat <<'YAML'
server:
  port: 8080  # 服务端口

order:
  max-retry: 5
  timeout: 8000
  inventory-check-enabled: true
  new-feature-enabled: true
YAML
)"

# Spring Boot 中使用 @RefreshScope 实现热更新
cat <<'EOF' > OrderConfig.java
package com.demo.order.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.stereotype.Component;

@Component
@RefreshScope
@ConfigurationProperties(prefix = "order")
public class OrderConfig {
    private int maxRetry;
    private int timeout;
    private boolean inventoryCheckEnabled;
    private boolean newFeatureEnabled;

    // getters and setters
    public int getMaxRetry() { return maxRetry; }
    public void setMaxRetry(int maxRetry) { this.maxRetry = maxRetry; }
    public int getTimeout() { return timeout; }
    public void setTimeout(int timeout) { this.timeout = timeout; }
    public boolean isInventoryCheckEnabled() { return inventoryCheckEnabled; }
    public void setInventoryCheckEnabled(boolean inventoryCheckEnabled) { this.inventoryCheckEnabled = inventoryCheckEnabled; }
    public boolean isNewFeatureEnabled() { return newFeatureEnabled; }
    public void setNewFeatureEnabled(boolean newFeatureEnabled) { this.newFeatureEnabled = newFeatureEnabled; }
}
EOF
```

### 4.6 K8s Service 与 Nacos 协同

```bash
# 场景：K8s 内部服务通过 Nacos 发现，外部服务通过 K8s Service 发现

# 创建 K8s Service（作为 Nacos 的补充）
cat <<'EOF' | kubectl apply -f -
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: order-service
  namespace: demo
  labels:
    app: order-service
  annotations:
    # Nacos 服务发现注解（可选，用于 Nacos 同步 K8s Service）
    nacos.io/service-name: order-service
    nacos.io/namespace: production
    nacos.io/group: DEFAULT_GROUP
    nacos.io/weight: "1.0"
spec:
  selector:
    app: order-service
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP  # 集群内部访问
---
# ExternalName Service（将 K8s 外部服务引入集群）
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: legacy-payment-service
  namespace: demo
spec:
  type: ExternalName  # 外部服务 DNS 名称
  externalName: payment-service.legacy.svc.cluster.local
EOF

# Nacos 同步 K8s Service 的方案：
# 1. 使用 Nacos Sync 组件同步 K8s Service 到 Nacos
# 2. 使用 Spring Cloud Kubernetes 同时支持 K8s Service 发现和 Nacos 发现
# 3. 使用 Nacos 的 ServiceEntry 注册 K8s Service

# Spring Cloud Kubernetes + Nacos 混合发现配置
cat <<'EOF' > mixed-discovery.yml
spring:
  cloud:
    discovery:
      # 多注册中心
      composite:
        discovery-clients:
          - type: nacos
            order: 1
          - type: kubernetes
            order: 2
      # Nacos 配置
      nacos:
        discovery:
          server-addr: nacos.middleware.svc.cluster.local:8848  # Nacos 服务地址
          namespace: production  # 生产环境命名空间
      # K8s 配置
      kubernetes:
        enabled: true
        all-namespaces: false
        namespaces:
          - demo
          - middleware
EOF
```

### 4.7 Sentinel（流量防护组件） 流控集成

```bash
# Spring Boot 集成 Sentinel
# 1. 添加依赖（pom.xml）
# spring-cloud-starter-alibaba-sentinel

# 2. 配置 Sentinel
cat <<'EOF' > sentinel-config.yaml
spring:
  cloud:
    sentinel:
      transport:
        dashboard: sentinel.middleware.svc.cluster.local:8858  # Sentinel 控制台地址
        port: 8719
      # 热点参数限流
      hot-rules:
        - resource: getOrder
          paramIdx: 0
          count: 100
          grade: 1
          durationInSec: 1
          paramFlowItemList:
            - paramIdx: 0
              classType: java.lang.String
              count: 5
              ruleType: 0
              value: VIP_USER
      # 熔断降级
      degrade:
        rules:
          - resource: orderService
            grade: 0
            count: 50
            timeWindow: 10
            minRequestAmount: 10
            statIntervalMs: 1000
            slowRatioThreshold: 1.0
EOF

# 3. 使用 Sentinel 注解
cat <<'EOF' > OrderControllerWithSentinel.java
package com.demo.order.controller;

import com.alibaba.csp.sentinel.annotation.SentinelResource;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/orders")
public class OrderControllerWithSentinel {

    @GetMapping("/{orderId}")
    @SentinelResource(
        value = "getOrder",
        blockHandler = "getOrderBlockHandler",
        fallback = "getOrderFallback"
    )
    public String getOrder(@PathVariable String orderId) {
        // 业务逻辑
        return "Order: " + orderId;
    }

    // 流控处理
    public String getOrderBlockHandler(String orderId, BlockException ex) {
        return "请求过于频繁，请稍后再试";
    }

    // 异常降级
    public String getOrderFallback(String orderId, Throwable ex) {
        return "服务暂时不可用: " + ex.getMessage();
    }
}
EOF

# 4. 部署 Sentinel Dashboard
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1  # API 版本
kind: Deployment  # K8s 部署
metadata:
  name: sentinel-dashboard
  namespace: middleware
spec:
  replicas: 1  # 副本数: 1
  selector:
    matchLabels:
      app: sentinel-dashboard
  template:
    metadata:
      labels:
        app: sentinel-dashboard
    spec:
      containers:
      - name: sentinel-dashboard
        image: 192.168.1.61/sentinel/sentinel-dashboard:1.8.6  # 镜像地址(Harbor)
        ports:
        - containerPort: 8858
        resources:
          requests:
            cpu: 200m  # CPU 200m
            memory: 512Mi  # 内存 512Mi
          limits:
            cpu: 1000m  # CPU 1000m
            memory: 1Gi  # 内存 1Gi
---
apiVersion: v1  # API 版本
kind: Service  # K8s 服务
metadata:
  name: sentinel
  namespace: middleware
spec:
  selector:
    app: sentinel-dashboard
  ports:
  - port: 8858
    targetPort: 8858
  type: NodePort
EOF
```

### 4.8 权重路由

```bash
# 1. 注册不同权重的服务实例
# 实例 1：权重 1.0（正常流量）
curl -X POST "http://192.168.1.54:30848/nacos/v1/ns/instance" \
  -d "serviceName=order-service&ip=192.168.1.100&port=8080&weight=1.0&namespaceId=production&enabled=true&healthy=true&metadata=version=v1"

# 实例 2：权重 0.1（少量流量，用于灰度测试）
curl -X POST "http://192.168.1.54:30848/nacos/v1/ns/instance" \
  -d "serviceName=order-service&ip=192.168.1.101&port=8080&weight=0.1&namespaceId=production&enabled=true&healthy=true&metadata=version=v2"

# 2. 查询实例列表
curl -X GET "http://192.168.1.54:30848/nacos/v1/ns/instance/list?serviceName=order-service&namespaceId=production"
# 预期：两个实例，权重分别为 1.0 和 0.1
# 流量分配：约 91% 到 v1，约 9% 到 v2

# 3. 动态调整权重（全量切换到 v2）
curl -X PUT "http://192.168.1.54:30848/nacos/v1/ns/instance" \
  -d "serviceName=order-service&ip=192.168.1.100&port=8080&weight=0.0&namespaceId=production&enabled=true"
curl -X PUT "http://192.168.1.54:30848/nacos/v1/ns/instance" \
  -d "serviceName=order-service&ip=192.168.1.101&port=8080&weight=1.0&namespaceId=production&enabled=true"

# 4. Spring Cloud LoadBalancer 自定义权重策略
cat <<'EOF' > NacosWeightLoadBalancerConfig.java
package com.demo.order.config;

import com.alibaba.cloud.nacos.loadbalancer.NacosRule;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@LoadBalancerClient(name = "user-service", configuration = NacosWeightConfig.class)
public class NacosWeightLoadBalancerConfig {

    // 使用 Nacos 权重策略
    @Bean
    public NacosRule nacosRule() {
        return new NacosRule();
    }
}
EOF
```

---

## 5. 配置详解 / 高级功能

### 5.1 Nacos 健康检查机制

```
Nacos 支持两种健康检查模式：

1. 临时实例（默认，AP 模式）：
   - 客户端主动发送心跳（默认每 5 秒）
   - 服务端 15 秒未收到心跳标记为不健康
   - 30 秒未收到心跳剔除实例
   - 适合微服务场景，快速感知实例变化

2. 持久实例（CP 模式）：
   - 服务端主动探测（TCP/HTTP）
   - 不会自动剔除实例
   - 适合传统应用、数据库等需要保持注册的场景

配置方式：
# 临时实例（默认）
spring.cloud.nacos.discovery.ephemeral=true

# 持久实例
spring.cloud.nacos.discovery.ephemeral=false
```

### 5.2 Nacos 配置监听与动态刷新

```
配置变更推送流程：

1. 客户端发起长轮询请求（默认 30 秒超时）
2. Nacos Server 收到请求后挂起
3. 配置变更时，Nacos Server 立即返回变更的 Data ID
4. 客户端收到响应后拉取最新配置
5. 客户端更新本地缓存并触发 @RefreshScope Bean 刷新

长轮询优势：
- 实时性好（配置变更后秒级推送）
- 服务端资源消耗低（相比 WebSocket）
- 客户端实现简单
- 天然支持断线重连
```

### 5.3 多环境配置管理

```
推荐的多环境配置方案：

Namespace 隔离：
  dev (开发环境)
  staging (预发环境)
  production (生产环境)

每个 Namespace 中的配置：
  common.yaml          -- 公共配置（日志、Jackson、监控）
  redis-config.yaml    -- Redis 配置
  mysql-config.yaml    -- MySQL 配置
  order-service.yaml   -- 订单服务专属配置
  user-service.yaml    -- 用户服务专属配置

配置加载顺序（优先级从高到低）：
  1. JVM 参数 (-D)
  2. 本地 application.yaml
  3. Nacos order-service.yaml (服务专属)
  4. Nacos common.yaml (共享配置)
  5. Nacos redis-config.yaml (扩展共享)
```

---

## 6. 验证与测试

### 6.1 服务注册验证

```bash
# 1. 检查 Nacos 集群状态
curl -s "http://192.168.1.54:30848/nacos/v1/ns/operator/leaders" | jq .

# 2. 查看已注册的服务列表
curl -s "http://192.168.1.54:30848/nacos/v1/ns/service/list?pageNo=1&pageSize=100&namespaceId=production" | jq .

# 3. 查看服务实例详情
curl -s "http://192.168.1.54:30848/nacos/v1/ns/instance/list?serviceName=order-service&namespaceId=production" | jq .

# 4. 健康检查
curl -s "http://192.168.1.54:30848/nacos/v1/ns/health/instance?serviceName=order-service&namespaceId=production&ip=10.244.1.10&port=8080" | jq .

# 5. 发送心跳（手动测试）
curl -X PUT "http://192.168.1.54:30848/nacos/v1/ns/instance/beat" \
  -d "serviceName=order-service&namespaceId=production&ip=10.244.1.10&port=8080"
```

### 6.2 配置中心验证

```bash
# 1. 获取配置
curl -s "http://192.168.1.54:30848/nacos/v1/cs/configs?dataId=order-service.yaml&group=DEFAULT_GROUP"

# 2. 监听配置变更
curl -X POST "http://192.168.1.54:30848/nacos/v1/cs/configs/listener" \
  -d "Listening-Configs=1%02order-service.yaml%01DEFAULT_GROUP%01production%02"

# 3. 查询配置历史
curl -s "http://192.168.1.54:30848/nacos/v1/cs/history?dataId=order-service.yaml&group=DEFAULT_GROUP&pageNo=1&pageSize=10" | jq .

# 4. 查询 Beta 配置
curl -s "http://192.168.1.54:30848/nacos/v1/cs/configs?dataId=order-service.yaml&group=DEFAULT_GROUP&beta=true"
```

### 6.3 权重路由验证

```bash
# 发送 100 次请求，统计流量分配
for i in $(seq 1 100); do
  curl -s http://192.168.1.54:31080/api/orders/test -H "Host: api.demo.local" | grep -o "instance=[^ ]*"
done | sort | uniq -c

# 预期输出（权重 1.0:0.1）：
#   91 instance=192.168.1.100:8080
#    9 instance=192.168.1.101:8080
```

---

## 7. CKA/CKS 考点融入

### 7.1 CKA 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Service | ClusterIP/NodePort/ExternalName（外部名称服务） | 4.6 节 |
| ConfigMap（配置映射）/Secret | Nacos 配置管理、数据库密码 | 4.1/4.4 节 |
| StatefulSet（有状态应用部署） | Nacos 集群有序部署 | 4.2 节 |
| PVC | MySQL/Nacos 数据持久化 | 4.1 节 |
| Helm | Nacos Helm 部署 | 4.2 节 |

### 7.2 CKS 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Secret 管理 | MySQL 密码、Nacos 认证 | 4.1 节 |
| NetworkPolicy（网络策略） | Nacos 集群网络隔离 | 4.2 节 |
| RBAC（基于角色的访问控制） | Nacos 控制台权限控制 | 4.4 节 |
| 镜像安全 | Nacos 镜像来源验证 | 4.2 节 |

---

## 8. 高频面试题

### Q1: Nacos 的 AP 和 CP 模式分别适用于什么场景？（难度：中等）

**答案：** Nacos 的 AP 模式使用 Distro 协议，适用于**服务注册发现**场景。在 AP 模式下，服务实例注册为临时实例，通过客户端心跳维持健康状态，Nacos 节点间通过定时同步实现最终一致性。AP 模式优先保证可用性，即使部分节点间网络分区，各节点仍能独立提供服务注册和发现功能。CP 模式使用 Raft 协议，适用于**配置管理**场景。在 CP 模式下，所有写操作通过 Leader 节点处理，需要多数派确认后才能成功，保证强一致性。CP 模式在网络分区时会牺牲可用性（无法写入），但保证所有节点看到的配置是一致的。Nacos 2.x 中，临时实例默认使用 gRPC 长连接替代 HTTP 心跳，提升了性能和实时性。生产环境建议：服务注册使用 AP 模式（临时实例），配置管理使用 CP 模式（Nacos 默认行为）。

### Q2: Nacos 服务注册的流程是什么？（难度：中等）

**答案：** Nacos 服务注册流程分为以下几个步骤：1）客户端启动时读取 bootstrap.yml 中的 Nacos 配置（server-addr、namespace、group 等）；2）客户端向 Nacos Server 发送 POST /nacos/v1/ns/instance 请求，携带 serviceName、ip、port、weight、metadata 等信息；3）Nacos Server 接收注册请求后，将实例信息写入本地内存和服务列表；4）在 AP 模式下，Nacos Server 通过 Distro 协议将注册信息同步到其他节点（异步同步，最终一致）；5）客户端建立 gRPC 长连接（Nacos 2.x）或启动心跳任务（Nacos 1.x），定期发送心跳维持注册状态；6）其他服务通过 GET /nacos/v1/ns/instance/list 查询服务实例列表，Nacos 返回所有健康实例的 IP:Port 列表；7）客户端使用 LoadBalancer（负载均衡器） 根据权重策略选择实例发起调用。Nacos 2.x 使用 gRPC 替代 HTTP，减少了心跳请求次数，提升了注册和发现的性能。

### Q3: Nacos 配置中心如何实现配置热更新？（难度：中等）

**答案：** Nacos 配置热更新通过长轮询（Long Polling（长轮询））机制实现。流程：1）客户端启动时从 Nacos 拉取配置并缓存到本地；2）客户端发起长轮询请求到 Nacos Server，请求中携带已配置的 Data ID、Group 和 MD5 值；3）Nacos Server 收到请求后，将请求挂起（默认 30 秒超时）；4）如果 30 秒内配置发生变更，Nacos Server 立即返回变更的 Data ID；5）客户端收到响应后，重新拉取最新配置并更新本地缓存；6）客户端触发 Spring 的 Environment 更新事件，标记了 @RefreshScope 的 Bean 会被重新创建，新的配置值生效。如果 30 秒内没有配置变更，Nacos Server 返回空响应，客户端立即发起新的长轮询。这种机制实现了配置的秒级推送，同时服务端资源消耗极低。Nacos 2.x 使用 gRPC 推送替代长轮询，进一步降低了延迟。

### Q4: Nacos 如何实现服务权重路由？（难度：中等）

**答案：** Nacos 服务权重路由通过实例的 weight 属性实现。每个注册到 Nacos 的服务实例都有一个权重值（默认 1.0），Nacos 客户端在选择实例时会根据权重进行加权随机选择。权重越大，被选中的概率越高。实现方式：1）注册时指定权重：`curl -X POST .../instance -d "weight=0.1"`；2）动态修改权重：通过 Nacos Open API 或控制台修改实例权重，实时生效无需重启；3）客户端集成：Spring Cloud Alibaba Nacos Discovery 默认使用 NacosRule（继承自 Ribbon 的 AbstractLoadBalancerRule），根据 Nacos 返回的实例权重进行负载均衡。权重路由的典型应用场景：灰度发布（新版本实例权重设为 0.1，逐步增加到 1.0）；金丝雀发布（特定实例接收少量流量验证）；机房路由（同机房实例权重高，跨机房权重低）；故障降级（异常实例权重设为 0，不再接收流量）。

### Q5: Nacos 与 K8s Service 如何协同工作？（难度：困难）

**答案：** Nacos 和 K8s Service 在微服务架构中各有优势，可以协同使用。**K8s Service** 适合 K8s 集群内部的服务发现，通过 DNS（`service-name.namespace.svc.cluster.local`）进行服务发现，支持 L4 负载均衡。**Nacos** 适合跨集群、跨环境的服务发现，提供更丰富的功能（权重路由、元数据、配置中心）。协同方案：1）**Spring Cloud Kubernetes + Nacos**：使用 composite discovery 同时注册到 K8s Service 和 Nacos，K8s 内部服务通过 K8s Service 发现，外部服务通过 Nacos 发现；2）**Nacos Sync**：使用 Nacos Sync 组件将 K8s Service 自动同步到 Nacos，实现统一的服务注册中心；3）**ExternalName Service**：将 Nacos 中的外部服务通过 K8s ExternalName Service 引入集群；4）**Istio + Nacos**：使用 Istio ServiceEntry 注册 Nacos 中的服务到 Istio 服务网格。推荐方案：在 K8s 内部使用 K8s Service + Istio，跨集群/跨环境使用 Nacos，通过 Nacos Sync 保持同步。

### Q6: Nacos 的命名空间（Namespace）有什么作用？（难度：简单）

**答案：** Nacos 的命名空间用于实现多租户和多环境的配置隔离。不同命名空间下的服务和配置完全隔离，互不可见。典型用途：1）**环境隔离**：创建 dev、staging、production 三个命名空间，每个环境的服务注册和配置管理完全独立，避免开发环境配置误操作影响生产环境；2）**多租户隔离**：不同团队或业务线使用不同的命名空间，实现资源隔离和权限控制；3）**多集群管理**：不同 K8s 集群使用不同的命名空间，便于统一管理。命名空间的设计类似于 K8s 的 Namespace 概念。配置方式：在 bootstrap.yml 中通过 `spring.cloud.nacos.discovery.namespace=production` 和 `spring.cloud.nacos.config.namespace=production` 指定命名空间。注意：命名空间 ID 是全局唯一的，建议使用有意义的 ID（如 dev、staging、production）而非自动生成的 ID。

### Q7: Nacos 集群如何保证高可用？（难度：中等）

**答案：** Nacos 集群高可用从多个层面保障：1）**节点数量**：至少 3 个节点（Raft 协议需要 2n+1 个节点容忍 n 个故障），推荐 3 或 5 个节点；2）**数据持久化**：配置数据存储在外部 MySQL 中，即使所有 Nacos 节点故障，数据不丢失；3）**AP 模式**：服务注册使用 Distro 协议（AP），每个节点存储全量数据，任意节点故障不影响服务注册和发现；4）**CP 模式**：配置管理使用 Raft 协议（CP），Leader 故障时自动选举新 Leader，选举期间（约 1-2 秒）配置不可写入但可读；5）**负载均衡**：客户端配置多个 Nacos Server 地址（逗号分隔），客户端自动选择可用节点；6）**健康检查**：Nacos 2.x 使用 gRPC 长连接，连接断开时自动重连到其他节点。生产环境建议：3 个 Nacos 节点分布在不同物理机/可用区，MySQL 使用主从复制或 MHA 保证数据库高可用。

### Q8: 如何实现 Nacos 配置的灰度发布？（难度：中等）

**答案：** Nacos 提供了 Beta 灰度发布功能，可以将配置变更先推送给指定的 IP 地址进行验证。实现步骤：1）通过 Nacos Open API 或控制台发布 Beta 配置，指定 betaIps 参数（如 `192.168.1.100,192.168.1.101`）；2）只有指定 IP 的客户端会收到新配置，其他客户端仍使用旧配置；3）验证新配置在灰度实例上的效果（功能正确性、性能影响等）；4）确认无误后，点击"全量发布"将配置推送给所有客户端；5）如果发现问题，点击"停止 Beta"回滚到旧配置。注意事项：Beta 发布时需要客户端 IP 在 Nacos 注册列表中；Beta 配置不会持久化到 MySQL，全量发布后才写入数据库；Beta 发布期间，非 Beta 客户端的长轮询请求不会被提前返回（等待全量发布）。除了 Beta 发布，还可以通过 Namespace 隔离实现环境级别的灰度。

### Q9: Sentinel 与 Nacos 如何集成实现动态流控？（难度：中等）

**答案：** Sentinel 与 Nacos 集成实现流控规则的动态管理。集成方式：1）Sentinel 客户端连接到 Sentinel Dashboard 和 Nacos；2）流控规则配置在 Nacos 配置中心（如 `sentinel-order-service-rules.json`）；3）Sentinel 客户端启动时从 Nacos 拉取流控规则；4）在 Sentinel Dashboard 中修改流控规则后，规则自动推送到 Nacos；5）Nacos 配置变更后，通过长轮询推送给所有 Sentinel 客户端，实时生效。优势：规则持久化到 Nacos，Sentinel Dashboard 重启不丢失规则；多实例规则自动同步，无需逐个配置；支持动态更新，无需重启应用。配置方式：在 Spring Boot 中添加 `sentinel-datasource-nacos` 依赖，配置 `spring.cloud.sentinel.datasource.ds.nacos.server-addr` 和规则类型。支持的规则类型：流控规则（FlowRule）、熔断降级规则（DegradeRule）、热点参数规则（ParamFlowRule）、系统保护规则（SystemRule）、授权规则（AuthorityRule）。

### Q10: Nacos 如何实现服务优雅上下线？（难度：困难）

**答案：** Nacos 服务优雅上下线需要客户端和服务端配合。**优雅上线**：1）应用启动完成后才向 Nacos 注册（Spring Boot 的 `SmartLifecycle` 或 `@PostConstruct`），避免流量打到未就绪的实例；2）配合 K8s 的 readinessProbe，确保 Pod 就绪后才接收流量；3）Nacos 2.x 使用 gRPC 连接，连接建立后才注册。**优雅下线**：1）应用收到 SIGTERM 信号后，先从 Nacos 注销（发送 DELETE /nacos/v1/ns/instance）；2）等待正在处理的请求完成（配置 `spring.lifecycle.timeout-per-shutdown-phase=30s`）；3）关闭服务器端口，停止接收新请求；4）K8s 的 preStop hook 中执行 sleep 等待（`sleep 10`），确保 Nacos 注销完成和负载均衡更新。注意事项：Nacos 的 IP 删除有延迟（默认 30 秒），下线后短时间内仍可能有少量流量路由到已下线的实例；建议配合 Spring Cloud LoadBalancer 的缓存刷新时间（默认 35 秒）和 K8s 的 terminationGracePeriodSeconds（建议 60 秒）。

### Q11: Nacos 2.x 相比 1.x 有哪些重大改进？（难度：中等）

**答案：** Nacos 2.x 的核心改进：1）**gRPC 替代 HTTP**：服务注册、发现和配置推送从 HTTP 短连接升级为 gRPC 长连接，大幅降低了网络开销和延迟。注册性能提升约 2 倍，配置推送延迟从秒级降到毫秒级。2）**连接模型优化**：每个客户端与 Nacos Server 建立两条 gRPC 连接（一条用于服务注册/发现，一条用于配置管理），替代了 1.x 的高频心跳和长轮询。3）**推送模型**：配置变更从客户端拉取（长轮询）升级为服务端推送（gRPC Stream），实时性更好。4）**内存优化**：2.x 重写了服务发现模块的内存结构，使用 ConcurrentHashMap 替代 CopyOnWriteArrayList，减少了内存占用和 GC 压力。5）**平滑升级**：2.x Server 兼容 1.x Client，可以逐步升级。注意事项：2.x 默认使用 9848 端口（gRPC），需要确保防火墙开放该端口。

### Q12: 如何排查 Nacos 服务注册失败？（难度：中等）

**答案：** Nacos 服务注册失败的排查步骤：1）检查 Nacos Server 连通性：`curl http://nacos.middleware.svc.cluster.local:8848/nacos/v1/ns/operator/leaders`，确认 Nacos Server 可达；2）检查命名空间配置：确认 bootstrap.yml 中的 namespace ID 与 Nacos 控制台一致（注意是 namespace ID 而非名称）；3）检查网络策略：确认应用 Pod 到 Nacos Server 的 8848 和 9848 端口网络通畅；4）检查 Nacos Server 日志：`kubectl logs nacos-0 -n middleware --tail=50`，查看注册请求是否到达 Server；5）检查应用日志：搜索 `nacos` 或 `discovery` 关键字，查看注册异常信息；6）检查 Nacos 集群状态：如果 Nacos 集群 Leader 选举未完成，注册请求可能被拒绝；7）检查 MySQL 连接：Nacos Server 无法连接 MySQL 时，CP 模式的配置注册会失败；8）检查 gRPC 端口：Nacos 2.x 需要 9848 端口，如果被防火墙阻止，gRPC 连接会失败并回退到 HTTP 模式。

### Q13: Nacos 的配置回滚机制是什么？（难度：简单）

**答案：** Nacos 内置了配置变更历史记录功能，支持配置回滚。每次配置变更都会记录在 `his_config_info` 表中，包含变更时间、操作类型、变更内容等。回滚操作：1）在 Nacos 控制台中进入配置详情页，点击"历史版本"标签；2）选择需要回滚的版本；3）点击"回滚"按钮，确认后配置恢复到历史版本；4）回滚操作本身也会被记录为一次新的变更。通过 API 回滚：`POST /nacos/v1/cs/history?dataId=xxx&group=xxx&nid=xxx`。注意事项：回滚是立即生效的，所有订阅该配置的客户端都会收到新配置；回滚操作不可撤销（但可以再次回滚到更早的版本）；建议在生产环境回滚前先在预发环境验证。最佳实践：配置变更前记录当前配置的 MD5 值，回滚时对比确认；配置变更使用 Beta 灰度发布降低风险。

### Q14: Nacos 如何实现多数据中心的跨区域服务发现？（难度：困难）

**答案：** Nacos 多数据中心服务发现有几种方案：1）**Nacos 同步**：使用 Nacos Sync 组件在多个 Nacos 集群间同步服务数据，每个数据中心部署独立的 Nacos 集群，Nacos Sync 负责跨集群同步。2）**单集群多 Region**：使用 Nacos 的 Cluster 概念，同一服务在不同 Region 注册不同的 Cluster（如 SH-BJ、SH-SH），客户端通过 `cluster-name` 配置优先访问同 Region 的实例。3）**跨 Region 负载均衡**：自定义 Spring Cloud LoadBalancer 规则，优先选择同 Region 的实例，同 Region 无可用实例时跨 Region 调用。4）**DNS + Nacos**：使用 CoreDNS 的自定义插件，将 Nacos 服务发现与 DNS 结合，实现跨 Region 的服务路由。推荐方案：中小规模使用方案二（单集群多 Cluster），大规模使用方案一（Nacos Sync 多集群同步）。注意事项：跨 Region 调用需要考虑网络延迟、数据一致性、故障隔离等问题。

### Q15: 如何监控 Nacos 集群的健康状态？（难度：中等）

**答案：** Nacos 监控的关键维度：1）**集群状态**：Leader 选举状态（`/nacos/v1/ns/operator/leaders`）、节点数量、Raft 日志索引一致性；2）**服务注册**：注册实例数、注销实例数、心跳失败次数、服务列表变更频率；3）**配置管理**：配置变更次数、长轮询连接数、配置推送延迟、Beta 发布状态；4）**性能指标**：API QPS、响应延迟 P99、gRPC 连接数、内存使用率；5）**JVM 指标**：堆内存使用、GC 频率和耗时、线程数。监控工具：Nacos 内置 Prometheus metrics 端点（`/nacos/actuator/prometheus`），部署 Prometheus + Grafana（可视化面板） 采集和展示；Nacos 控制台的服务管理页面展示注册实例数和健康状态。告警规则：Leader 变更、节点宕机、API 错误率 > 1%、配置推送延迟 > 5s、JVM 内存使用率 > 80%。Nacos 2.x 还提供了 gRPC 连接数的监控指标。

---

## 9. 故障排查案例

### 案例 1：服务注册到 Nacos 失败

**现象：**
```
应用启动日志：
2024-01-15 10:00:00 [main] ERROR c.a.n.c.d.NacosServiceRegistry - nacos registry, order-service register failed...
com.alibaba.nacos.api.exception.NacosException: failed to req API:/nacos/v1/ns/instance after all servers([nacos.middleware.svc.cluster.local:8848]) tried
```

**排查步骤：**
```bash
# 1. 检查 Nacos Server 状态
kubectl get pods -n middleware -l app=nacos
# 发现：nacos-0 Running, nacos-1 Running, nacos-2 Running

# 2. 检查 Nacos gRPC 端口
kubectl exec -it nacos-0 -n middleware -- ss -tlnp | grep -E "8848|9848"
# 发现：8848 端口正常，9848 端口未监听

# 3. 检查 Nacos 日志
kubectl logs nacos-0 -n middleware --tail=30 | grep -i error
# 发现：Failed to start gRPC server on port 9848

# 4. 检查网络策略
kubectl get networkpolicy -n middleware
# 发现：NetworkPolicy 阻止了 9848 端口
```

**解决方案：**
```bash
# 方案一：修复 NetworkPolicy，开放 9848 端口
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1  # API 版本
kind: NetworkPolicy
metadata:
  name: allow-nacos-grpc
  namespace: middleware
spec:
  podSelector:
    matchLabels:
      app: nacos
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 8848
    - protocol: TCP
      port: 9848
    - protocol: TCP
      port: 9849
EOF

# 方案二：降级到 HTTP 模式（临时方案）
# 在 bootstrap.yml 中添加：
# spring.cloud.nacos.discovery.port=8848
```

### 案例 2：Nacos 配置热更新不生效

**现象：**
```
在 Nacos 控制台修改了 order-service.yaml 的配置，但应用中 @RefreshScope 标注的 Bean 未刷新。
```

**排查步骤：**
```bash
# 1. 检查配置 Data ID 是否正确
# 应用期望：order-service.yaml
# Nacos 中实际：order-service.yml（后缀不同）

# 2. 检查 Namespace 是否匹配
kubectl exec -it deploy/order-service -n demo -- env | grep namespace
# 发现：应用配置的 namespace=production
# Nacos 控制台：配置在 public 命名空间

# 3. 检查 Group 是否匹配
# 应用配置：group=DEFAULT_GROUP
# Nacos 中配置：group=ORDER_GROUP

# 4. 检查 @RefreshScope 注解
# 发现：Bean 上缺少 @RefreshScope 注解
```

**解决方案：**
```bash
# 1. 修正 Data ID 后缀（yaml vs yml）
# 确保 bootstrap.yml 中 file-extension: yaml 与 Nacos 中 Data ID 后缀一致

# 2. 修正 Namespace
# bootstrap.yml 中 namespace: production 与 Nacos 控制台一致

# 3. 添加 @RefreshScope 注解
@Component
@RefreshScope
@ConfigurationProperties(prefix = "order")
public class OrderConfig { ... }

# 4. 手动触发刷新（验证）
curl -X POST "http://order-service.demo.svc.cluster.local:8080/actuator/refresh"
```

### 案例 3：Nacos 集群 Leader 选举失败

**现象：**
```bash
kubectl logs nacos-0 -n middleware --tail=50
# ERROR: Raft leader election failed, no leader available
# ERROR: Cannot find leader for config data
```

**排查步骤：**
```bash
# 1. 检查所有 Nacos 节点状态
for i in 0 1 2; do
  echo "=== nacos-$i ==="
  kubectl logs nacos-$i -n middleware --tail=10 | grep -i "raft\|leader"
done

# 2. 检查节点间网络连通性
kubectl exec -it nacos-0 -n middleware -- ping nacos-1.nacos-headless.middleware.svc.cluster.local
kubectl exec -it nacos-0 -n middleware -- ping nacos-2.nacos-headless.middleware.svc.cluster.local

# 3. 检查 MySQL 连接
kubectl exec -it nacos-0 -n middleware -- nc -zv mysql.middleware.svc.cluster.local 3306

# 4. 检查 NACOS_SERVERS 配置
kubectl exec -it nacos-0 -n middleware -- env | grep NACOS_SERVERS
# 发现：NACOS_SERVERS 配置错误（使用了错误的 Service 名称）
```

**解决方案：**
```bash
# 修正 NACOS_SERVERS 配置
helm upgrade nacos ./nacos \
  --namespace middleware \
  --reuse-values \
  --set nacos.env.NACOS_SERVERS="nacos-0.nacos-headless.middleware.svc.cluster.local:8848 nacos-1.nacos-headless.middleware.svc.cluster.local:8848 nacos-2.nacos-headless.middleware.svc.cluster.local:8848"

# 等待集群恢复
kubectl rollout restart statefulset/nacos -n middleware
kubectl rollout status statefulset/nacos -n middleware --timeout=120s
```

### 案例 4：Nacos 控制台无法登录

**现象：**
```
访问 http://192.168.1.54:30848/nacos，输入 nacos/nacos 后提示"用户名或密码错误"。
```

**排查步骤：**
```bash
# 1. 检查 MySQL 中的用户数据
kubectl exec -it deploy/mysql -n middleware -- mysql -u root -p'Nacos@2024' nacos \
  -e "SELECT username, password FROM users;"

# 2. 检查 Nacos 认证配置
kubectl exec -it nacos-0 -n middleware -- env | grep -i auth
# 发现：nacos.core.auth.enabled=true（启用了认证）

# 3. 检查 Nacos 版本
kubectl exec -it nacos-0 -n middleware -- env | grep NACOS_VERSION
# 发现：v2.4.3（默认启用认证）

# 4. 检查 token 过期
# Nacos 2.x 引入了 token 机制，默认 token 过期时间 18000 秒
```

**解决方案：**
```bash
# 方案一：重置管理员密码
kubectl exec -it deploy/mysql -n middleware -- mysql -u root -p'Nacos@2024' nacos \
  -e "UPDATE users SET password='\$2a\$10\$EuWPZHzz32dJN7jexM34MOeYirDdFAZm2kuWj7VEOJhhZkDrxfvUu' WHERE username='nacos';"

# 方案二：临时关闭认证（仅开发环境）
helm upgrade nacos ./nacos \
  --namespace middleware \
  --reuse-values \
  --set nacos.env.NACOS_AUTH_ENABLE=false

# 方案三：检查 Nacos Server 时间同步
# token 验证依赖服务器时间，时间不同步会导致 token 验证失败
kubectl exec -it nacos-0 -n middleware -- date
kubectl exec -it nacos-1 -n middleware -- date
```

### 案例 5：服务实例被 Nacos 误剔除

**现象：**
```
服务运行正常，但 Nacos 控制台显示实例为空，服务调用报错 "No instances available"。
```

**排查步骤：**
```bash
# 1. 检查实例列表
curl -s "http://192.168.1.54:30848/nacos/v1/ns/instance/list?serviceName=order-service&namespaceId=production"
# 发现：hosts 列表为空

# 2. 检查应用日志
kubectl logs deploy/order-service -n demo --tail=50 | grep -i "nacos\|heartbeat\|deregister"
# 发现：心跳发送失败

# 3. 检查 Nacos Server 日志
kubectl logs nacos-0 -n middleware --tail=100 | grep "order-service"
# 发现：IP delete timeout, remove instance

# 4. 检查心跳超时配置
kubectl exec -it deploy/order-service -n demo -- env | grep -i "heart"
# 发现：heart-beat-timeout 未配置（默认 15 秒）
```

**解决方案：**
```bash
# 问题原因：应用 GC 停顿或网络抖动导致心跳超时被剔除

# 方案一：增大心跳超时时间
# bootstrap.yml:
spring:
  cloud:
    nacos:
      discovery:
        heart-beat-timeout: 30000  # 心跳超时(毫秒)
        ip-delete-timeout: 60000

# 方案二：升级到 Nacos 2.x gRPC 模式（自动维护连接，无需心跳）
# Nacos 2.x 使用 gRPC 长连接替代 HTTP 心跳

# 方案三：优化应用 JVM 参数，减少 GC 停顿
# -XX:+UseG1GC -XX:MaxGCPauseMillis=200

# 方案四：使用持久实例（不自动剔除）
spring.cloud.nacos.discovery.ephemeral=false
```

### 案例 6：Nacos 配置冲突导致应用启动失败

**现象：**
```
应用启动报错：
org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'dataSource'
Caused by: java.lang.IllegalArgumentException: invalid url: ${spring.datasource.url}
```

**排查步骤：**
```bash
# 1. 检查 Nacos 配置内容
curl -s "http://192.168.1.54:30848/nacos/v1/cs/configs?dataId=order-service.yaml&group=DEFAULT_GROUP"
# 发现：配置中使用了 ${} 占位符，但引用的变量未定义

# 2. 检查共享配置加载顺序
# 发现：order-service.yaml 中引用了 common.yaml 的变量，但 common.yaml 未加载

# 3. 检查 bootstrap.yml 配置
# 发现：shared-configs 中缺少 common.yaml

# 4. 检查配置优先级
# 发现：本地 application.yml 和 Nacos 配置存在冲突
```

**解决方案：**
```bash
# 1. 在 bootstrap.yml 中添加共享配置
spring:
  cloud:
    nacos:
      config:
        shared-configs:
          - data-id: common.yaml
            group: DEFAULT_GROUP
            refresh: true

# 2. 检查配置中变量引用是否正确
# 使用 ${variable:defaultValue} 提供默认值

# 3. 使用 Nacos 配置导入功能
# 在 Nacos 控制台中使用"导入配置"功能，将依赖的配置一并导入
```

### 案例 7：Nacos 内存溢出

**现象：**
```bash
kubectl get pods -n middleware -l app=nacos
# nacos-0   0/1 OOMKilled
# nacos-1   1/1 Running
# nacos-2   1/1 Running

kubectl describe pod nacos-0 -n middleware
# Last State: Terminated, Reason: OOMKilled
```

**排查步骤：**
```bash
# 1. 检查注册服务数量
curl -s "http://192.168.1.54:30848/nacos/v1/ns/service/list?pageNo=1&pageSize=1000" | jq '.doms | length'
# 发现：注册了 5000+ 个服务实例

# 2. 检查 JVM 堆内存配置
kubectl exec -it nacos-0 -n middleware -- env | grep -i "xmx\|xms"
# 发现：JAVA_XMX=512m（太小）

# 3. 检查 Nacos 版本
# 发现：Nacos 1.x 版本（内存效率较低）
```

**解决方案：**
```bash
# 方案一：增大 JVM 堆内存
helm upgrade nacos ./nacos \
  --namespace middleware \
  --reuse-values \
  --set nacos.env.JAVA_XMS=1g \
  --set nacos.env.JAVA_XMX=2g \
  --set nacos.resources.limits.memory=4Gi

# 方案二：升级到 Nacos 2.x（内存优化）
# Nacos 2.x 重写了内存结构，同等规模下内存使用减少约 50%

# 方案三：清理无效的服务实例
# 使用 Nacos Open API 批量注销无效实例

# 方案四：开启服务过期清理
# nacos.naming.empty-service.auto-clean=true
# nacos.naming.empty-service.clean.initial-delay-ms=50000
# nacos.naming.empty-service.clean.period-time-ms=30000
```

### 案例 8：Spring Cloud LoadBalancer 未使用 Nacos 权重

**现象：**
```
配置了 Nacos 权重路由（实例 A 权重 1.0，实例 B 权重 0.1），但实际流量分配接近 50/50。
```

**排查步骤：**
```bash
# 1. 检查 LoadBalancer 配置
# 发现：使用的是默认的 RoundRobinLoadBalancer，而非 NacosRule

# 2. 检查依赖
# pom.xml 中缺少 spring-cloud-starter-loadbalancer 依赖

# 3. 检查 NacosRule 配置
# 发现：未配置 @LoadBalancerClient 注解
```

**解决方案：**
```bash
# 1. 确保依赖正确
# pom.xml:
# <dependency>
#   <groupId>com.alibaba.cloud</groupId>
#   <artifactId>spring-cloud-starter-alibaba-nacos-discovery</artifactId>
# </dependency>
# <dependency>
#   <groupId>org.springframework.cloud</groupId>
#   <artifactId>spring-cloud-starter-loadbalancer</artifactId>
# </dependency>

# 2. 配置全局使用 Nacos 权重策略
# application.yml:
spring:
  cloud:
    nacos:
      discovery:
        loadbalancer:
          enabled: true

# 3. 或者针对特定服务配置
@LoadBalancerClient(name = "user-service", configuration = NacosWeightConfig.class)
public class NacosWeightConfig {
    @Bean
    public NacosRule nacosRule() {
        return new NacosRule();
    }
}
```

---

## 10. 生产环境建议

### 10.1 生产级 Nacos 配置清单

```yaml
# Helm Values 生产配置
nacos:
  image:
    tag: v2.4.3
  env:
    # JVM
    JAVA_XMS: "1g"
    JAVA_XMX: "1g"
    JAVA_XMN: "512m"
    # 认证
    NACOS_AUTH_ENABLE: "true"
    NACOS_AUTH_TOKEN_EXPIRE_SECONDS: "18000"
    NACOS_AUTH_TOKEN: "generated-token-example"
    # 安全
    SERVER_SERVLET_CONTEXT_PATH: "/nacos"
    # 性能
    NACOS_SERVER_DEBUG: "false"
    NACOS_LOG_LEVEL: "WARN"
  resources:
    requests:
      cpu: 500m  # CPU 500m
      memory: 1Gi  # 内存 1Gi
    limits:
      cpu: 2000m  # CPU 2000m
      memory: 2Gi  # 内存 2Gi

cluster:
  replicas: 3  # 副本数: 3

persistence:
  enabled: true
  storageClass: local-path
  size: 5Gi  # 存储大小: 5Gi

# MySQL 高可用
# 使用 RDS 或 MySQL 主从复制
# 定期备份 nacos 数据库
```

### 10.2 生产最佳实践

| 领域 | 建议 |
|------|------|
| **集群规模** | 至少 3 节点，分布在不同物理机/可用区 |
| **数据库** | MySQL 8.0 主从复制或云 RDS，定期备份 |
| **认证** | 启用 Nacos 认证（nacos.auth.enabled=true） |
| **命名空间** | dev/staging/production 严格隔离 |
| **配置管理** | 使用 Beta 灰度发布，禁止直接修改生产配置 |
| **监控** | Prometheus（指标监控系统） 采集 Nacos metrics，配置告警 |
| **JVM** | 堆内存 1-2GB，使用 G1GC（垃圾回收器） |
| **网络** | 开放 8848（HTTP）、9848（gRPC）、9849（gRPC） |
| **升级** | 先升级 Nacos Server，再升级客户端 |
| **备份** | 定期备份 MySQL 数据库和配置历史 |
| **安全** | 配置防火墙，限制 Nacos 控制台访问 IP |
| **日志** | 日志级别设为 WARN，定期清理旧日志 |
