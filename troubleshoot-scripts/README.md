# 运维一键排查脚本集

> 40+ Shell脚本，覆盖 K8S、中间件、Linux系统、网络协议、内核、部署、告警、日常巡检八大模块
> 对应课程模块：29-K8S故障排查、30-中间件故障排查、31-Linux系统故障排查、32-网络协议深度解析、33-计算机基础与内核、34-部署发布、35-告警处置、36-日常运维

---

## 脚本总览

| 模块 | 脚本数量 | 覆盖场景 |
|------|---------|---------|
| [29-k8s](#29-k8s--k8s故障排查-9-个) | 9个 | Pod状态、服务超时、节点健康、conntrack/inotify/iptables/PID资源 |
| [30-middleware](#30-middleware--中间件故障排查-5-个) | 5个 | MySQL、Redis、Elasticsearch、Kafka、Nginx |
| [31-linux](#31-linux--系统基础诊断-9-个) | 9个 | CPU、内存、磁盘IO、进程、文件系统、FD、日志、安全、启动故障 |
| [32-network](#32-network--网络诊断-5-个) | 5个 | TCP连接、TIME_WAIT、网络延迟、TLS、DNS |
| [33-kernel](#33-kernel--内核服务诊断-6-个) | 6个 | 调度器、缺页中断、PageCache、系统调用、内核健康、systemd服务 |
| [34-deploy](#34-deploy--部署发布-5-个) | 5个 | 蓝绿部署、金丝雀、滚动发布、回滚、预检 |
| [35-alert](#35-alert--告警处置-5-个) | 5个 | 告警签收、分诊、自动修复、事后复盘、企业微信通知 |
| [36-daily](#36-daily--日常巡检-2-个) | 2个 | 一键日常健康巡检（手动+自动企业微信通知） |

---

## 测试验证报告

| 项目 | 结果 |
|------|------|
| 测试版本 | v4 (2026-06-26) |
| 测试平台 | Ubuntu 22.04 (t1: 192.168.1.71) |
| 诊断脚本 | 全部通过 ✅ |
| 修复脚本 | dry-run 全部通过 ✅ |
| 语法错误 | 0 |
| integer expression 警告 | 0 |

### 已修复 Bug 清单

| Bug | 脚本 | 根因 | 修复 |
|-----|------|------|------|
| `integer expression expected: wa,` | check-cpu.sh | `grep -E '%Cpu\|%CPU'` 同时匹配了 `%Cpu(s)` 行和 PID 表头 `%CPU` 列，`_cpu_extract` sed 多行处理导致值包含非数字字符 | `grep '%Cpu(s)'` 精确匹配 + `_cpu_extract` 添加数字验证守卫 |
| `integer expression expected: OutSegs` | check-network-latency.sh | `grep "^Tcp:" /proc/net/snmp` 返回表头+数据两行，awk 取到表头文字而非数值 | 分离表头/数据行，按列名动态定位字段索引 |
| `unexpected EOF while looking for matching ''` | check-syscall.sh | awk 正则中的 `/'` 被 bash 解析为字符串结束符 | 拆分为 `$1 !~ /total/ && $1 !~ /---/` |

---

## 快速开始

```bash
# 1. 安装依赖
# RHEL/CentOS:
sudo yum install -y sysstat iotop traceroute bind-utils curl strace nmap ethtool

# Debian/Ubuntu:
sudo apt install -y sysstat iotop traceroute dnsutils curl strace nmap ethtool

# 2. 运行全部诊断
cd troubleshoot-scripts
bash run-all.sh

# 3. 按模块运行
bash run-all.sh --module linux       # 系统诊断 (module 31)
bash run-all.sh --module network     # 网络诊断 (module 32)
bash run-all.sh --module kernel      # 内核诊断 (module 33)
bash run-all.sh --module k8s         # K8s诊断 (module 29)
bash run-all.sh --module middleware  # 中间件诊断 (module 30)
bash run-all.sh --module daily       # 日常巡检 (module 36)

# 4. 运行单个脚本
bash run-all.sh --script check-cpu
bash run-all.sh --script daily-check

# 5. 操作类模块 (仅限 --module, 需传参)
bash run-all.sh --module deploy      # ⚠️ 版本发布 (有副作用)
bash run-all.sh --module alert       # 告警处置 (需配置webhook)
```

---

## 脚本目录

### 29-k8s — K8S故障排查 (9 个)

| 脚本 | 功能 | 用法 | 典型场景 | 关键指标 |
|------|------|------|---------|----------|
| `check-node-health.sh` | 节点健康检查 | `./check-node-health.sh` | 节点NotReady，Pod调度失败 | Node conditions, 资源使用率, 磁盘/网络/进程状态 |
| `check-pod-pending.sh` | Pod Pending 诊断 | `./check-pod-pending.sh [namespace]` | Pod一直处于Pending，无法调度 | 调度失败原因、资源不足、PVC/PV 绑定、节点亲和性 |
| `check-pod-restart.sh` | Pod 重启分析 | `./check-pod-restart.sh [namespace]` | Pod反复CrashLoopBackOff | OOMKilled、重启次数、退出码 |
| `check-ingress.sh` | Ingress 诊断 | `./check-ingress.sh [ingress-name] [namespace]` | 域名访问404/502/503 | Ingress/Service/Endpoint 链路连通性 |
| `check-service-timeout.sh` | Service 超时诊断 | `./check-service-timeout.sh [service-name] [namespace]` | 服务访问超时，连接不上 | Service/Endpoint/Pod 全链路连通性测试 |
| `node/check-conntrack.sh` | conntrack 诊断 | `./node/check-conntrack.sh` | 连接数满、NAT转换失败 | 连接跟踪表使用率、nf_conntrack_max 阈值 |
| `node/check-inotify.sh` | inotify 诊断 | `./node/check-inotify.sh` | 文件监控失败、Pod挂载事件丢失 | 文件监控句柄使用率、max_user_watches 阈值 |
| `node/check-iptables.sh` | iptables 诊断 | `./node/check-iptables.sh` | Service规则丢失、转发异常 | 规则数量及 K8s Service 转发规则状态 |
| `node/check-pid.sh` | PID 诊断 | `./node/check-pid.sh` | PID耗尽无法创建进程 | PID 使用率、kernel.pid_max 阈值 |

> **排查思路**：Pod状态 → Service连通 → Ingress路由 → 节点资源

---

### 30-middleware — 中间件故障排查 (5 个)

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `check-mysql.sh` | MySQL 连接/慢查询/主从复制诊断 | `./check-mysql.sh [host] [port] [user] [password]` | 连接超时、慢查询、锁等待 |
| `check-redis.sh` | Redis 内存/连接/持久化诊断 | `./check-redis.sh [host] [port] [password]` | 内存不足、主从延迟、连接满 |
| `check-elasticsearch.sh` | ES 集群/索引/分片诊断 | `./check-elasticsearch.sh [host] [port]` | 集群变红/黄、分片未分配 |
| `check-kafka.sh` | Kafka 消费者组/分区/积压诊断 | `./check-kafka.sh [bootstrap-server]` | 消息消费延迟、Broker宕机 |
| `check-nginx.sh` | Nginx 连接/性能/错误日志诊断 | `./check-nginx.sh` | 502/504错误、连接数满 |

> **排查思路**：连接层 → 服务端状态 → 存储层 → 集群健康

---

### 31-linux — 系统基础诊断 (9 个)

| 脚本 | 功能 | 用法 | 典型场景 | 关键指标 |
|------|------|------|---------|----------|
| `check-cpu.sh` | CPU 瓶颈诊断 | `./check-cpu.sh [pid]` | CPU使用率100%、负载过高 | us/sy/wa/id 使用率、上下文切换、系统负载 |
| `check-memory.sh` | 内存泄漏与OOM排查 | `./check-memory.sh [pid]` | 内存不足、OOM Killer触发 | 总内存、可用内存、Swap 使用、OOM 检测 |
| `check-diskio.sh` | 磁盘IO瓶颈分析 | `./check-diskio.sh [device]` | 磁盘IO wait高、读写慢 | iostat 吞吐量、IOPS、等待时间 |
| `check-process.sh` | 僵尸进程与D状态进程 | `./check-process.sh` | 僵尸进程累积、进程卡死 | 僵尸进程、CPU/内存 TOP 进程、线程数 |
| `check-boot.sh` | 系统启动故障排查 | `./check-boot.sh` | 开机卡住、服务启动失败 | 启动时间、失败服务、内核日志错误 |
| `check-filesystem.sh` | **文件系统诊断** ⭐ | `./check-filesystem.sh` | inode耗尽、磁盘满、挂载异常 | inode/磁盘使用率、NFS/CIFS、已删除文件句柄 |
| `check-fd.sh` | **FD/资源限制** ⭐ | `./check-fd.sh [pid]` | too many open files | 系统/进程FD使用、PID耗尽、ulimit |
| `check-log.sh` | **日志异常扫描** ⭐ | `./check-log.sh` | dmesg错误、认证失败攻击 | dmesg异常、journalctl错误、auth安全日志 |
| `check-security.sh` | **安全审计** ⭐ | `./check-security.sh` | 端口异常监听、可疑进程 | 端口监听、SUID文件、外部连接、crontab |

> **排查思路**：CPU → 内存 → 磁盘 → 进程 → 文件系统 → FD → 日志 → 安全 → 启动链路

---

### 32-network — 网络诊断 (5 个)

| 脚本 | 功能 | 用法 | 典型场景 | 关键指标 |
|------|------|------|---------|----------|
| `check-tcp-conn.sh` | TCP连接状态与端口占用 | `./check-tcp-conn.sh [port]` | 端口被占、连接数满、SYN Flood | ESTABLISHED/CLOSE_WAIT 计数、连接数阈值 |
| `check-time-wait.sh` | TIME_WAIT过多排查 | `./check-time-wait.sh` | TIME_WAIT堆积、端口耗尽 | TW 数量、端口耗尽风险评估、内核参数建议 |
| `check-network-latency.sh` | 网络延迟与丢包排查 | `./check-network-latency.sh [target-host]` | 网络慢、ping不通、丢包 | ping 延迟、TCP 重传率、网卡错误 |
| `check-tls.sh` | TLS/SSL证书与握手排查 | `./check-tls.sh [host] [port]` | 证书过期、TLS握手失败 | 证书有效期、协议版本、OpenSSL 版本 |
| `check-dns.sh` | DNS解析故障排查 | `./check-dns.sh [domain]` | 域名解析失败、DNS劫持 | 解析延迟、DNS 服务器可达性、/etc/resolv.conf |

> **排查思路**：TCP连接 → 端口状态 → 网络延迟 → TLS握手 → DNS解析

---

### 33-kernel — 内核/服务诊断 (6 个)

| 脚本 | 功能 | 用法 | 典型场景 | 关键指标 |
|------|------|------|---------|----------|
| `check-scheduler.sh` | CPU调度器与上下文切换 | `./check-scheduler.sh [pid]` | 上下文切换过高、调度延迟 | 进程状态分布、调度延迟 |
| `check-pagefault.sh` | 缺页中断与内存访问 | `./check-pagefault.sh [pid]` | 大量Minor/Major Page Fault | min/maj 缺页率、/proc/vmstat 分析 |
| `check-pagecache.sh` | PageCache缓存命中率 | `./check-pagecache.sh` | 缓存命中率低、频繁读磁盘 | 缓存命中率、脏页数量、内存回收 |
| `check-syscall.sh` | 系统调用频率与性能 | `./check-syscall.sh [pid]` | 系统调用过多、性能下降 | strace 概要统计、高频系统调用分析 |
| `check-kernel-health.sh` | 内核整体健康状态 | `./check-kernel-health.sh` | 内核日志异常、模块加载失败 | kernel panic/oops、内核版本 |
| `check-systemd.sh` | **systemd服务诊断** ⭐ | `./check-systemd.sh [service]` | 服务反复重启、定时任务异常 | 失败服务、restart-loop、关键服务、定时器 |

> **排查思路**：调度器 → 内存访问 → 缓存效率 → 系统调用 → 内核整体 → systemd服务

---

### 34-deploy — 部署发布 (5 个)

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `deploy-check.sh` | 部署前环境检查 | `./deploy-check.sh [target]` | 发布前预检、资源不足排查 |
| `deploy-rollout.sh` | 滚动发布 | `./deploy-rollout.sh [deployment]` | 零停机滚动发布 |
| `deploy-blue-green.sh` | 蓝绿部署 | `./deploy-blue-green.sh [service]` | 新旧版本快速切换、零风险回滚 |
| `deploy-canary.sh` | 金丝雀发布 | `./deploy-canary.sh [service]` | 小流量验证、渐进式发布 |
| `deploy-rollback.sh` | 一键回滚 | `./deploy-rollback.sh [deployment]` | 发布失败快速回滚 |

> **使用思路**：部署检查 → 选择策略（滚动/蓝绿/金丝雀） → 发布 → 异常回滚

---

### 35-alert — 告警处置 (5 个)

| 脚本 | 功能 | 用法 | 典型场景 |
|------|------|------|---------|
| `alert-ack.sh` | 告警签收与静默管理 | `./alert-ack.sh [alert-id]` | 收到告警后第一时间签收 |
| `alert-triage.sh` | 告警分诊与影响面评估 | `./alert-triage.sh [service]` | 判断告警影响范围、定级 |
| `alert-auto-fix.sh` | 告警自动修复 | `./alert-auto-fix.sh [alert-type]` | 磁盘满、OOM等常见告警自动恢复 |
| `alert-postmortem.sh` | 事后分析与复盘 | `./alert-postmortem.sh [incident-id]` | 故障后数据汇总与改进建议 |
| `alert-wechat-notify.sh` | 企业微信通知 | `./alert-wechat-notify.sh` | 告警推送到企业微信群聊 |

> **使用思路**：告警签收 → 分诊评估 → 自动修复 → 事后复盘 → 企业微信通知

---

### 36-daily — 日常巡检 (2 个)

| 脚本 | 功能 | 用法 | 特点 |
|------|------|------|------|
| `daily-check.sh` | 一键日常健康巡检 | `./daily-check.sh [target]` | 系统+网络+服务全量检查，生成摘要报告 |
| `daily-check-auto.sh` | 自动巡检(企业微信) | `./daily-check-auto.sh` | 同上 + 企业微信机器人通知(需配置 webhook) |

> **检查范围**：系统状态 → 资源使用 → 服务状态 → 网络连通 → 关键进程 → 日志异常

---

## 排查思路层级（从外到内）

```
不知道问题在哪？按层次排查：

第一层 — Linux系统层 (31-linux):
  ./check-cpu.sh → ./check-memory.sh → ./check-diskio.sh → ./check-process.sh

第二层 — 文件系统/资源层 (31-linux):
  ./check-filesystem.sh → ./check-fd.sh → ./check-log.sh → ./check-security.sh

第三层 — 网络层 (32-network):
  ./check-tcp-conn.sh → ./check-time-wait.sh → ./check-network-latency.sh
  → ./check-dns.sh [域名] → ./check-tls.sh [host] [port]

第四层 — 内核层 (33-kernel):
  ./check-scheduler.sh → ./check-pagefault.sh → ./check-kernel-health.sh

第五层 — 中间件层 (30-middleware):
  ./check-mysql.sh → ./check-redis.sh → ./check-kafka.sh → ./check-elasticsearch.sh

第六层 — K8S层 (29-k8s):
  ./check-node-health.sh → ./check-pod-pending.sh → ./check-pod-restart.sh
  → ./check-service-timeout.sh → ./check-ingress.sh

第七层 — 部署发布层 (34-deploy):
  ./deploy-check.sh → ./deploy-rollback.sh

第八层 — 告警处置层 (35-alert):
  ./alert-ack.sh → ./alert-triage.sh → ./alert-auto-fix.sh → ./alert-postmortem.sh
```

---

## 面试时展示

> 我在项目中沉淀了 **40+ 个一键排查脚本**，覆盖 **K8S、中间件、Linux、网络、内核、部署、告警、日常巡检** 八个层面。遇到问题时，按 **系统→网络→中间件→K8S** 的层次排查，每个脚本都有颜色输出（✅OK绿色、⚠️WARN黄色、❌FAIL红色），一目了然。遇到发布问题有蓝绿和金丝雀策略，告警支持自动修复，日常可以一键体检。这套脚本已经在 Ubuntu 22.04 生产环境完整验证，零语法错误。

---

## auto-fix — 自动修复工具 (5 个) ⚠️

> **警告**: 修复类脚本会修改系统配置，生产环境请先 `--dry-run` 试运行！

| 脚本 | 功能 | 安全阈值 | 适用场景 |
|------|------|----------|----------|
| `fix-disk-full.sh` | 安全清理磁盘 | 仅使用率>85%时执行 | apt/yum缓存、旧内核、journal、临时文件 |
| `fix-zombie.sh` | 清理僵尸进程 | 跳过bash/sshd等shell父进程 | 僵尸进程堆积 |
| `fix-service.sh` | 重启失败服务 | 最多重试3次，跳过关键系统服务 | 服务crash后恢复 |
| `fix-fd-limit.sh` | 调整FD限制 | file-max≤1048576, nofile≤1048576 | FD不足影响服务 |
| `fix-conntrack.sh` | 调整conntrack限制 | nf_conntrack_max≤2097152 | conntrack表满影响NAT |

```bash
# 试运行 (推荐)
cd troubleshoot-scripts/auto-fix
bash fix-disk-full.sh --dry-run
bash fix-zombie.sh --dry-run
bash fix-service.sh --all --dry-run

# 实际执行
bash fix-disk-full.sh          # 清理磁盘
bash fix-service.sh nginx      # 重启指定服务
bash fix-service.sh --all      # 重启所有失败服务
```

### 修复安全分层

| 层级 | 操作类型 | 示例 |
|------|----------|------|
| 🟢 **可自动** | 低风险、可逆 | 清理缓存、journal日志、临时文件 |
| 🟡 **半自动** | 需阈值保护 | 调整FD限制、重启非核心服务 |
| 🔴 **禁止** | 高风险、需人工 | 内核参数调优、网络配置、OOM终止 |

---

## 脚本特点

- **颜色输出**：OK(绿)/WARN(黄)/FAIL(红)/INFO(白)，一眼定位问题
- **参数化**：支持传参，如namespace、host、port等
- **零依赖**：纯Shell实现，核心功能不依赖额外工具
- **模块化**：按课程模块组织，学习路径清晰
- **生产验证**：Ubuntu 22.04 完整测试，0语法错误

---

## 依赖清单

### 必要依赖 (所有平台)
- `bash` >= 4.0
- `top`, `ps`, `uptime`, `free` (procps)
- `awk`, `sed`, `grep`
- `nproc` (coreutils)
- `vmstat` (procps)

### 推荐依赖 (功能增强)
- `ss` / `netstat` — TCP 连接分析 (net-tools/iproute2)
- `iostat`, `mpstat`, `iotop` — IO/CPU 详细统计 (sysstat)
- `traceroute` — 网络路径追踪
- `dig` — DNS 解析测试 (bind-utils/dnsutils)
- `curl` — HTTP/TLS 连通性测试
- `strace` — 系统调用追踪
- `ethtool` — 网卡信息查询
- `nmap` — 端口扫描 (check-tls.sh)

---

## 安全说明

- 所有诊断脚本均为**只读诊断**，不会修改系统配置
- 不需要 root 权限即可运行（部分功能受限，如 strace）
- `daily-check-auto.sh` 的企业微信 webhook 需提前配置
- 建议在非生产环境先验证后再部署到生产环境
- iOS/macOS 不兼容，仅支持 Linux

---

## 输出说明

运行 `run-all.sh` 后，结果保存在 `diagnosis-results/` 目录：

```
diagnosis-results/
├── report_20260626_143000.txt          # 汇总报告
├── check-cpu_20260626_143000.log       # CPU 诊断详细日志
├── check-memory_20260626_143000.log    # 内存诊断详细日志
... (共 40+ 个日志文件)
```

---

## 目录结构

```
troubleshoot-scripts/
├── README.md                    # 本文件
├── run-all.sh                   # 统一运行器
├── PROGRESS.md                  # 进度跟踪
├── deploy-to-t1.sh              # 部署到测试机
├── monitrc / monit.service      # Monit 监控配置
├── 29-k8s/                      # K8S故障排查（9个脚本）
│   ├── check-pod-pending.sh
│   ├── check-pod-restart.sh
│   ├── check-service-timeout.sh
│   ├── check-ingress.sh
│   ├── check-node-health.sh
│   └── node/
│       ├── check-conntrack.sh
│       ├── check-inotify.sh
│       ├── check-iptables.sh
│       └── check-pid.sh
├── 30-middleware/               # 中间件故障排查（5个脚本）
│   ├── check-mysql.sh
│   ├── check-redis.sh
│   ├── check-elasticsearch.sh
│   ├── check-kafka.sh
│   └── check-nginx.sh
├── 31-linux/                    # Linux系统故障排查（9个脚本）
│   ├── check-cpu.sh
│   ├── check-memory.sh
│   ├── check-diskio.sh
│   ├── check-process.sh
│   ├── check-boot.sh
│   ├── check-filesystem.sh
│   ├── check-fd.sh
│   ├── check-log.sh
│   └── check-security.sh
├── 32-network/                  # 网络协议深度排查（5个脚本）
│   ├── check-tcp-conn.sh
│   ├── check-time-wait.sh
│   ├── check-network-latency.sh
│   ├── check-tls.sh
│   └── check-dns.sh
├── 33-kernel/                   # 内核深度排查（6个脚本）
│   ├── check-scheduler.sh
│   ├── check-pagefault.sh
│   ├── check-pagecache.sh
│   ├── check-syscall.sh
│   ├── check-kernel-health.sh
│   └── check-systemd.sh
├── 34-deploy/                   # 部署发布（5个脚本）
│   ├── deploy-check.sh
│   ├── deploy-rollout.sh
│   ├── deploy-blue-green.sh
│   ├── deploy-canary.sh
│   └── deploy-rollback.sh
├── 35-alert/                    # 告警处置（5个脚本）
│   ├── alert-ack.sh
│   ├── alert-triage.sh
│   ├── alert-auto-fix.sh
│   ├── alert-postmortem.sh
│   ├── alert-wechat-notify.sh
│   └── aom-alert-rules.conf
├── 36-daily/                    # 日常巡检（2个脚本）
│   ├── daily-check.sh
│   └── daily-check-auto.sh
└── auto-fix/                    # 自动修复（5个脚本）⚠️
    ├── fix-disk-full.sh
    ├── fix-zombie.sh
    ├── fix-service.sh
    ├── fix-fd-limit.sh
    └── fix-conntrack.sh
```

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-26 | 初始生产版，17 个诊断脚本全部通过测试验证 |
| v1.1 | 2026-06-26 | 新增 5 个诊断脚本(文件系统/FD/日志/安全/systemd) + 4 个自动修复脚本，覆盖率提升至 ~90% |
| v2.0 | 2026-07-07 | 融合旧仓库说明文档，新增脚本总览表、典型场景、排查思路层级、面试展示话术、完整目录结构 |
