# Monit + 诊断脚本集成项目 - 进度记录

> 最后更新: 2026-07-01 15:30

---

## 已完成的

### 1. Monit 部署 (t1 节点)
- [x] `monit` 二进制安装 (`/usr/local/bin/monit`)
- [x] `monit.service` systemd 托管，开机自启
- [x] 配置 `/etc/monit/monitrc` v2.3，集成 13 项检查，60s 巡检周期
- [x] 6 条自动修复链（磁盘满/FD耗尽/服务失败/僵尸进程/conntrack/inotify）
- [x] 修复 zombie-check / failed-services 内联命令转义 bug

### 2. 诊断脚本体系 (35 个 sh → 40 个 sh)
| 目录 | 数量 | 内容 |
|------|------|------|
| `31-linux/` | 9 | CPU/内存/磁盘IO/磁盘空间/文件系统/FD/进程/启动项/日志/安全 |
| `32-network/` | 5 | DNS/网络延迟/TCP连接/TIME_WAIT/TLS |
| `33-kernel/` | 6 | 内核健康/页缓存/缺页/调度器/系统调用/systemd |
| `29-k8s/` | 5 + 4 | Ingress/Node/Pod Pending/Restart/Service Timeout + conntrack/iptables/inotify/PID |
| `30-middleware/` | 5 | ES/Kafka/MySQL/Nginx/Redis |
| `34-deploy/` | 5 | 蓝绿部署/金丝雀/滚动更新/回滚/部署验证 |
| `35-alert/` | 5 | 告警通知/确认/分级/自动修复/复盘 |
| `36-daily/` | 2 | 日常巡检/企业微信通知 |

### 3. 自动修复 + Monit 专用脚本 (8 个)
| 脚本 | 触发条件 |
|------|---------|
| `fix-disk-full.sh` | 磁盘 >85% |
| `fix-fd-limit.sh` | FD 耗尽 |
| `fix-service.sh` | 关键服务 down |
| `fix-zombie.sh` | 僵尸进程 >5 |
| `fix-conntrack.sh` | conntrack >90% |
| `fix-inotify.sh` | inotify >90% |
| `monit-check-zombie.sh` | Monit 专用：僵尸进程检测 |
| `monit-check-services.sh` | Monit 专用：失败服务检测 |

### 4. 2026-07-01 部署验证 (第二轮测试)
- [x] t1 VM 在线，全线脚本已上传（53 个 sh 文件）
- [x] 全量诊断 `run-all.sh` 通过：22/22 PASS
- [x] 新增 4 个 K8s 节点脚本单独验证通过：
  - `check-conntrack.sh` → OK（t1 非 K8s 节点，conntrack 未加载，正常）
  - `check-inotify.sh` → WARN（inotify 限制偏低，建议扩容）
  - `check-iptables.sh` → OK（0 条规则，正常）
  - `check-pid.sh` → OK（使用率 0%，166 进程/4194304 上限）
- [x] Monit v2.3 重载成功，13 项检查全部注册
- [x] 修复 zombie-check 内联 awk 转义失效 → 迁移为独立脚本
- [x] 修复 failed-services `wc -l` 空格 bug → 迁移为独立脚本
- [x] 全部文件归档到 workspace，临时文件保留

### 5. 本地归档
- [x] 全部脚本已存入 `troubleshoot-scripts/` (62 个文件)
- [x] `monitrc` 已更新至 v2.3
- [x] `monit.service` 已归档
- [x] `deploy-to-t1.sh` 一键部署脚本已写好
- [x] 临时文件保留（未删除）

### 6. 2026-07-01 规范化重构 (P0/P1/P2)
- [x] **P0-编号统一**: 目录改回课程编号 29~36，37 个脚本头部全部匹配
- [x] **P0-违规词**: 修正 `待补充`→`手动截图后放置于此`、`适当增大`→`增大至当前值的1.5倍`
- [x] **P1-头部统一**: 20 个脚本补齐 `脚本名称` 行，分隔符 `=`→`===`，参数说明合并
- [x] **P1-模块名统一**: `版本发布脚本`→`版本发布与回滚`、`告警处理脚本`→`告警处置`
- [x] **P2-run-all 集成**: 中间件接入 all 诊断链，deploy/alert 仅 --module 访问+警告，K8s 节点过滤 fix 脚本
- [x] **P2-README/PROGRESS 同步更新**

---

## 待完成的

### 紧急 - 下次测试
- [ ] **模拟故障测试**（需在有 K8s 流量的节点上进行）:
  - conntrack 表满 → 验证 Monit 触发 `fix-conntrack.sh`
  - FD 耗尽 → 验证 Monit 触发 `fix-fd-limit.sh`
  - 磁盘空间 → 验证 Monit 触发 `fix-disk-full.sh`
  - inotify 耗尽 → 验证 Monit 触发 `fix-inotify.sh`
- [x] **在真实 K8s 节点 (w1/w2) 上部署脚本**，验证 K8s 专有检查的实际效果
- [x] **更新 `run-all.sh`** 已加入 29-k8s 模块（合并 34-k8s-node）

### 后续优化
- [ ] inotify 限制调整：`max_user_watches` 29339→1048576, `max_user_instances` 128→1024
- [ ] Monit 告警方式确认（目前是 log，是否需要 webhook/邮件？）
- [ ] 考虑是否将脚本扩展到其他节点（m1-m3, w1-w2）
- [ ] 补充 K8s 节点相关的修复脚本（iptables 规则清理、PID 上限调整）
- [ ] 写一份 K8s 节点 OS 维护最佳实践文档，整合 Prometheus NPD + Monit

### 长远
- [ ] 将脚本逻辑迁移为 K8s Operator (Reconcile Loop)
- [ ] eBPF 深度可观测集成 (Cilium/Tetragon)

---

## 关键部署命令速查

```bash
# 一键部署（VM 启动后执行）
cd "f:/项目管理2026/技能学习/.../troubleshoot-scripts/"
bash deploy-to-t1.sh

# 手动查看状态
ssh t1 "echo '123' | sudo -S monit summary"
ssh t1 "echo '123' | sudo -S monit status"

# 重载 Monit（修改配置后）
ssh t1 "echo '123' | sudo -S monit reload"

# 跑全部诊断
ssh t1 "bash ~/linux-scripts/run-all.sh"

# 单独测试 K8s 节点脚本
ssh t1 "bash ~/linux-scripts/29-k8s/node/check-conntrack.sh; echo EXIT:\$?"
ssh t1 "bash ~/linux-scripts/auto-fix/monit-check-zombie.sh; echo EXIT:\$?"
```

## 文件清单

```
troubleshoot-scripts/
├── PROGRESS.md          ← 本文件
├── deploy-to-t1.sh      ← 一键部署
├── monitrc              ← Monit 配置 v2.3
├── monit.service        ← systemd 单元文件
├── run-all.sh           ← 总控脚本
├── README.md
├── 31-linux/     (9 sh)  ← 系统基础诊断
├── 32-network/   (5 sh)  ← 网络协议诊断
├── 33-kernel/    (6 sh)  ← 内核诊断
├── 29-k8s/       (9 sh)  ← K8S故障排查 (含 node/ 子目录)
├── 30-middleware/(5 sh)  ← 中间件诊断
├── 34-deploy/    (5 sh)  ← 版本发布与回滚
├── 35-alert/     (5 sh + 1 conf)
├── 36-daily/     (2 sh)
└── auto-fix/     (8 sh)  ← +2 个 Monit 专用检查脚本
```
