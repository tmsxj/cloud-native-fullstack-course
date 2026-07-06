# Linux 故障排查诊断工具集 (生产版)

## 测试验证报告

| 项目 | 结果 |
|------|------|
| 测试版本 | v4 (2026-06-26) |
| 测试平台 | Ubuntu 22.04 (t1: 192.168.1.71) |
| 诊断脚本 | 22 (全部通过 ✅) |
| 修复脚本 | 4 (dry-run 全部通过 ✅) |
| 语法错误 | 0 |
| integer expression 警告 | 0 |
| 新增覆盖 | 文件系统 / FD泄漏 / 日志异常 / 安全审计 / systemd服务 |

## 覆盖面 (v4)

| 领域 | 脚本数 | 覆盖率 |
|------|--------|--------|
| CPU/内存/IO/进程 | 5 | ✅ |
| 文件系统/inode/挂载 | 1 | ✅ **新增** |
| FD泄漏/资源限制 | 1 | ✅ **新增** |
| 日志异常扫描 | 1 | ✅ **新增** |
| 安全审计 | 1 | ✅ **新增** |
| 网络/TCP/DNS/TLS | 5 | ✅ |
| 内核/调度器/系统调用 | 5 | ✅ |
| systemd服务/定时器 | 1 | ✅ **新增** |
| 日常巡检 | 2 | ✅ |
| **总覆盖率** | | **~90%** |

### 已修复 Bug 清单

| Bug | 脚本 | 根因 | 修复 |
|-----|------|------|------|
| `integer expression expected: wa,` | check-cpu.sh | `grep -E '%Cpu\|%CPU'` 同时匹配了 `%Cpu(s)` 行和 PID 表头 `%CPU` 列，`_cpu_extract` sed 多行处理导致值包含非数字字符 | `grep '%Cpu(s)'` 精确匹配 + `_cpu_extract` 添加数字验证守卫 |
| `integer expression expected: OutSegs` | check-network-latency.sh | `grep "^Tcp:" /proc/net/snmp` 返回表头+数据两行，awk `$12`/`$13` 取到表头文字而非数值 | 分离表头/数据行，按列名动态定位字段索引 |
| `unexpected EOF while looking for matching ''` | check-syscall.sh | awk 正则 `/total\|---/` 中的 `/'` 被 bash 解析为字符串结束符 | 拆分为 `$1 !~ /total/ && $1 !~ /---/` |

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

### 31-linux — 系统基础诊断 (9 个)

| 脚本 | 功能 | 关键指标 |
|------|------|----------|
| `check-cpu.sh` | CPU 瓶颈诊断 | us/sy/wa/id 使用率、上下文切换、系统负载 |
| `check-memory.sh` | 内存诊断 | 总内存、可用内存、Swap 使用、OOM 检测 |
| `check-diskio.sh` | 磁盘 IO 诊断 | iostat 吞吐量、IOPS、等待时间、iotop 进程 |
| `check-process.sh` | 进程诊断 | 僵尸进程、CPU/内存 TOP 进程、线程数 |
| `check-boot.sh` | 启动诊断 | 启动时间、失败服务、内核日志错误 |
| `check-filesystem.sh` | **文件系统诊断** ⭐ | inode/磁盘使用率、挂载状态、NFS/CIFS、已删除文件句柄 |
| `check-fd.sh` | **FD/资源限制** ⭐ | 系统/进程FD使用、PID耗尽、ulimit、内核参数 |
| `check-log.sh` | **日志异常扫描** ⭐ | dmesg异常、journalctl错误、auth安全日志、日志大小 |
| `check-security.sh` | **安全审计** ⭐ | 端口监听、SUID文件、可疑进程、外部连接、crontab |

### 32-network — 网络诊断 (5 个)

| 脚本 | 功能 | 关键指标 |
|------|------|----------|
| `check-tcp-conn.sh` | TCP 连接状态 | ESTABLISHED/CLOSE_WAIT 计数、连接数阈值 |
| `check-time-wait.sh` | TIME_WAIT 分析 | TW 数量、端口耗尽风险评估、内核参数建议 |
| `check-network-latency.sh` | 网络延迟 | ping 延迟、TCP 重传率、网卡错误 |
| `check-tls.sh` | TLS/SSL 诊断 | 证书有效期、协议版本、OpenSSL 版本 |
| `check-dns.sh` | DNS 诊断 | 解析延迟、DNS 服务器可达性、/etc/resolv.conf |

### 33-kernel — 内核/服务诊断 (6 个)

| 脚本 | 功能 | 关键指标 |
|------|------|----------|
| `check-scheduler.sh` | 调度器诊断 | 进程状态分布、调度延迟、上下文切换 |
| `check-pagefault.sh` | 缺页异常诊断 | min/maj 缺页率、/proc/vmstat 分析 |
| `check-pagecache.sh` | 页缓存诊断 | 缓存命中率、脏页数量、内存回收 |
| `check-syscall.sh` | 系统调用诊断 | strace 概要统计、高频系统调用分析 |
| `check-kernel-health.sh` | 内核健康检查 | kernel panic/opps、内核日志异常、内核版本 |
| `check-systemd.sh` | **systemd服务诊断** ⭐ | 失败服务、restart-loop、关键服务、定时器、journal |

### 36-daily — 日常巡检 (2 个)

| 脚本 | 功能 | 特点 |
|------|------|------|
| `daily-check.sh` | 日常健康检查 | 综合检查 CPU/内存/磁盘/网络/内核，生成摘要报告 |
| `daily-check-auto.sh` | 自动巡检(企业微信) | 同上 + 企业微信机器人通知(需配置 webhook) |

### 29-k8s — K8S故障排查 (11 个)

| 脚本 | 功能 | 关键指标 |
|------|------|----------|
| `check-node-health.sh` | 节点健康检查 | Node conditions, 资源使用率, 磁盘/网络/进程状态 |
| `check-pod-pending.sh` | Pod Pending 诊断 | 调度失败原因、资源不足、PVC/PV 绑定、节点亲和性 |
| `check-pod-restart.sh` | Pod 重启分析 | CrashLoopBackOff、OOMKilled、重启次数、退出码 |
| `check-ingress.sh` | Ingress 诊断 | Ingress/Service/Endpoint 链路连通性 |
| `check-service-timeout.sh` | Service 超时诊断 | Service/Endpoint/Pod 全链路连通性测试 |
| `node/check-conntrack.sh` | conntrack 诊断 | 连接跟踪表使用率、nf_conntrack_max 阈值 |
| `node/check-inotify.sh` | inotify 诊断 | 文件监控句柄使用率、max_user_watches 阈值 |
| `node/check-iptables.sh` | iptables 诊断 | 规则数量及 K8s Service 转发规则状态 |
| `node/check-pid.sh` | PID 诊断 | PID 使用率、kernel.pid_max 阈值 |

### 30-middleware — 中间件诊断 (5 个)

| 脚本 | 功能 |
|------|------|
| `check-mysql.sh` | MySQL 连接/慢查询/主从复制诊断 |
| `check-redis.sh` | Redis 内存/连接/持久化诊断 |
| `check-kafka.sh` | Kafka 消费者组/分区/积压诊断 |
| `check-elasticsearch.sh` | ES 集群/索引/分片诊断 |
| `check-nginx.sh` | Nginx 连接/性能/错误日志诊断 |

---

## auto-fix — 自动修复工具 (4 个) ⚠️

> **警告**: 修复类脚本会修改系统配置，生产环境请先 `--dry-run` 试运行！

| 脚本 | 功能 | 安全阈值 | 适用场景 |
|------|------|----------|----------|
| `fix-disk-full.sh` | 安全清理磁盘 | 仅使用率>85%时执行 | apt/yum缓存、旧内核、journal、临时文件 |
| `fix-zombie.sh` | 清理僵尸进程 | 跳过bash/sshd等shell父进程 | 僵尸进程堆积 |
| `fix-service.sh` | 重启失败服务 | 最多重试3次，跳过关键系统服务 | 服务crash后恢复 |
| `fix-fd-limit.sh` | 调整FD限制 | file-max≤1048576, nofile≤1048576 | FD不足影响服务 |

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

- 所有脚本均为**只读诊断**，不会修改系统配置
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
... (共 22 个日志文件)
```

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-26 | 初始生产版，17 个诊断脚本全部通过测试验证 |
| v1.1 | 2026-06-26 | 新增 5 个诊断脚本(文件系统/FD/日志/安全/systemd) + 4 个自动修复脚本，覆盖率提升至 ~90% |
