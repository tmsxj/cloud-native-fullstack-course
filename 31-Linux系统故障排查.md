# 模块31：Linux系统故障排查

---

## 一、理论核心

### 1.1 CPU性能瓶颈诊断模型

CPU是系统最核心的资源，生产环境中CPU飙高是最常见的故障类型。排查需区分用户态、系统态、IO等待态，不同状态的根因完全不同。

| CPU状态 | 含义 | 常见根因 | 排查命令 |
|---------|------|----------|----------|
| us（用户态） | 应用代码执行 | 死循环、密集计算、正则回溯 | `top` / `perf` |
| sy（系统态） | 内核代码执行 | 系统调用频繁、上下文切换多 | `strace` / `vmstat` |
| wa（IO等待） | 等待磁盘IO | 磁盘瓶颈、swap交换、文件系统损坏 | `iostat` / `iotop` |
| st（窃取时间） | 虚拟化层占用 | 云服务器超售、邻居租户干扰 | `top`（仅虚拟机） |
| id（空闲） | CPU未使用 | 正常状态或应用未充分利用 | `top` |

**关键要点**：
- CPU飙高先确认是us还是sy，us高找应用代码，sy高找系统调用
- wa高不一定是磁盘慢，可能是内存不足触发swap
- 多核CPU需关注单核飙高（绑核问题）还是整体飙高（全局问题）

---

### 1.2 内存泄漏与OOM机制

Linux内存管理采用虚拟内存机制，物理内存不足时触发OOM Killer选择进程终止。理解内存分配和回收机制是排查内存问题的核心。

| 内存指标 | 含义 | 告警阈值 | 排查命令 |
|----------|------|----------|----------|
| used | 已使用内存（含缓存） | >80%关注 | `free -h` |
| buff/cache | 文件缓存和缓冲区 | 可回收，不算真正占用 | `free -h` |
| available | 真正可用内存（含可回收缓存） | <20%告警 | `free -h` |
| swap used | 交换分区使用量 | >0即告警 | `free -h` |
| anon pages | 匿名页（应用堆内存） | 持续增长即泄漏 | `cat /proc/meminfo` |

**关键要点**：
- available接近0时系统即将OOM，需立即处理
- swap使用>0表示物理内存不足，性能会急剧下降
- OOM Killer日志在`/var/log/messages`或`dmesg`中查看
- 内存泄漏排查工具：`valgrind`（开发）、`pmap`（生产）、`/proc/<pid>/smaps`

---

### 1.3 磁盘IO与文件系统故障

磁盘是系统最慢的资源，IO瓶颈会导致整个系统卡顿。排查需区分磁盘硬件、文件系统、IO调度器三层。

| 排查维度 | 核心指标 | 正常范围 | 异常表现 |
|----------|----------|----------|----------|
| 磁盘使用率 | 容量占用百分比 | <80% | >90%触发只读保护 |
| IO吞吐量 | 每秒读写MB数 | 视磁盘类型 | 持续低于理论值 |
| IO延迟 | 平均等待时间（await） | SSD<5ms HDD<20ms | 超过50ms严重卡顿 |
| IO队列深度 | 未完成的IO请求数 | <磁盘并发能力 | 持续堆积 |
| 文件系统状态 | 挂载状态、只读/读写 | 读写挂载 | 只读挂载（损坏） |

**关键要点**：
- `iostat -x 1`中`%util`接近100%表示磁盘饱和
- `await`高但`svctm`低表示队列堆积，需优化IO模式
- 文件系统变只读通常是硬件故障或超级块损坏，需fsck修复
- 日志型文件系统（ext4/xfs）比非日志型更抗崩溃

---

## 二、实操演练

### 任务1：排查CPU飙高（用户态）

**任务目标**：定位导致CPU用户态飙高的进程和代码

**操作步骤**：

```bash
# 步骤1：查看整体CPU状态
top -bn1 | head -20
# 预期输出：%Cpu(s)行显示us、sy、wa、id比例

# 步骤2：定位高CPU进程
ps aux --sort=-%cpu | head -10
# 预期输出：按CPU使用率排序的进程列表

# 步骤3：定位高CPU线程
ps -eLo pid,tid,%cpu,comm --sort=-%cpu | head -10
# 预期输出：按线程CPU排序，找到具体线程ID

# 步骤4：线程ID转16进制（用于jstack）
printf "%x\n" <tid>
# 预期输出：线程ID的16进制表示

# 步骤5：Java应用获取线程堆栈
jstack <pid> | grep -A20 <hex-tid>
# 预期输出：该线程的调用栈，定位到具体代码

# 步骤6：非Java应用使用perf分析
perf top -p <pid>
# 预期输出：实时显示该进程的热点函数

# 步骤7：生成火焰图（需安装perf和FlameGraph）
perf record -F 99 -p <pid> -g -- sleep 30
perf script | ./stackcollapse-perf.pl | ./flamegraph.pl > cpu.svg
# 预期输出：生成cpu.svg火焰图，可视化热点

# 步骤8：验证修复
watch -n 1 'ps aux | grep <pid>'
# 预期输出：CPU使用率下降到正常范围
```

**注意事项**：
- Java应用CPU飙高最常见原因是死循环、正则回溯、频繁GC
- 多线程应用需关注是否某个线程独占CPU（绑核问题）
- perf需要root权限，生产环境谨慎使用

---

### 任务2：排查内存不足与OOM

**任务目标**：定位内存不足根因，分析OOM Killer行为

**操作步骤**：

```bash
# 步骤1：查看内存整体状态
free -h
# 预期输出：total、used、free、shared、buffers、cache、available

# 步骤2：查看内存详细分布
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|AnonPages"
# 预期输出：各内存类型的具体数值（KB）

# 步骤3：查看各进程内存使用
ps aux --sort=-%mem | head -10
# 预期输出：按内存使用率排序的进程

# 步骤4：查看具体进程内存映射
pmap -x <pid> | tail -1
# 预期输出：该进程的总内存、RSS、Dirty页

# 步骤5：查看OOM Killer日志
dmesg | grep -i "killed process"
# 预期输出：显示被OOM Killer终止的进程名和PID

# 步骤6：查看OOM评分（分数越高越容易被杀）
cat /proc/<pid>/oom_score
# 预期输出：0-1000的评分值

# 步骤7：调整OOM评分（保护关键进程）
echo -1000 > /proc/<pid>/oom_score_adj
# 预期输出：该进程不会被OOM Killer选中

# 步骤8：清理缓存（临时释放内存）
echo 3 > /proc/sys/vm/drop_caches
# 预期输出：清理pagecache、dentries和inodes

# 步骤9：验证修复
free -h
# 预期输出：available内存显著增加
```

**注意事项**：
- `echo 3 > /proc/sys/vm/drop_caches`是安全的，只清理缓存不杀进程
- OOM Killer选择进程的依据是oom_score，可通过oom_score_adj调整
- 长期解决方案是增加物理内存或优化应用内存使用

---

### 任务3：排查磁盘IO瓶颈

**任务目标**：定位磁盘IO延迟根因，优化IO性能

**操作步骤**：

```bash
# 步骤1：查看磁盘整体IO状态
iostat -x 1 5
# 预期输出：各磁盘的r/s、w/s、rkB/s、wkB/s、await、%util

# 步骤2：定位高IO进程
iotop -o -b -n 5
# 预期输出：按IO使用率排序的进程列表

# 步骤3：查看具体进程的IO操作
pidstat -d 1 -p <pid>
# 预期输出：该进程的每秒读写KB数

# 步骤4：分析IO模式（随机/顺序）
blktrace -d /dev/sda -o - | blkparse -i -
# 预期输出：详细的块设备IO事件

# 步骤5：检查磁盘调度器
cat /sys/block/sda/queue/scheduler
# 预期输出：[mq-deadline] kyber bfq none（当前调度器带中括号）

# 步骤6：SSD优化（切换为noop/none）
echo none > /sys/block/sda/queue/scheduler
# 预期输出：SSD使用none调度器减少延迟

# 步骤7：检查文件系统挂载选项
mount | grep /dev/sda
# 预期输出：确认noatime、nodiratime等优化选项

# 步骤8：验证修复
iostat -x 1 5
# 预期输出：await下降到正常范围，%util不再持续100%
```

**注意事项**：
- `await` = IO请求在队列中的等待时间 + 磁盘处理时间
- SSD应使用none调度器，HDD应使用mq-deadline
- 数据库等重IO应用建议单独挂载磁盘，避免与其他应用竞争

---

### 任务4：排查僵尸进程与进程挂起

**任务目标**：定位僵尸进程和不可中断睡眠进程（D状态）

**操作步骤**：

```bash
# 步骤1：查看僵尸进程
ps aux | grep "^Z"
# 预期输出：STAT列为Z的僵尸进程

# 步骤2：查看D状态进程（不可中断睡眠）
ps aux | awk '$8 ~ /^D/'
# 预期输出：STAT列为D的进程，通常卡在IO操作

# 步骤3：查看僵尸进程的父进程
ps -ef | grep <zombie-pid>
# 预期输出：找到PPID（父进程ID）

# 步骤4：杀死父进程（僵尸进程会随父进程退出而被init接管清理）
kill -9 <ppid>
# 预期输出：父进程终止，僵尸进程消失

# 步骤5：D状态进程分析（通常卡在IO）
cat /proc/<pid>/stack
# 预期输出：显示进程在内核中的调用栈

# 步骤6：检查进程等待的资源
cat /proc/<pid>/wchan
# 预期输出：进程正在等待的内核函数

# 步骤7：检查进程打开的文件
cat /proc/<pid>/fd | wc -l
# 预期输出：进程打开的文件描述符数量

# 步骤8：验证修复
ps aux | grep -E "^Z|^D"
# 预期输出：无Z或D状态进程
```

**注意事项**：
- 僵尸进程不占用资源，但占用PID，大量僵尸会导致无法创建新进程
- D状态进程无法通过kill终止，只能等待IO完成或重启系统
- 大量D状态进程通常是磁盘故障或NFS挂载问题

---

### 任务5：排查系统启动失败与内核panic

**任务目标**：定位系统无法启动或内核panic的根因

**操作步骤**：

```bash
# 步骤1：查看启动日志（如能进入救援模式）
journalctl -xb
# 预期输出：本次启动的完整日志

# 步骤2：查看上一次启动日志
journalctl -xb -1
# 预期输出：上一次启动的日志

# 步骤3：查看内核panic信息
dmesg | grep -i panic
# 预期输出：panic时的内核堆栈

# 步骤4：检查文件系统（救援模式下）
fsck -y /dev/sda1
# 预期输出：自动修复文件系统错误

# 步骤5：检查磁盘SMART状态
smartctl -a /dev/sda
# 预期输出：磁盘健康状态，关注Reallocated_Sector_Ct

# 步骤6：检查GRUB配置
cat /boot/grub2/grub.cfg | grep -A5 "menuentry"
# 预期输出：确认启动项配置正确

# 步骤7：重建initramfs
dracut -f
# 预期输出：重新生成initramfs镜像

# 步骤8：验证修复
reboot
# 预期输出：系统正常启动
```

**注意事项**：
- 内核panic常见原因：硬件故障、驱动bug、内核参数错误、内存损坏
- 文件系统损坏通常由断电或磁盘故障引起，fsck可修复大部分问题
- 重要数据在修复前建议备份，fsck可能导致数据丢失

---

## 三、面试真题

### 基础 高频 - Q1: 服务器CPU飙高，如何排查？

> **参考答案**：
> 1. **确认CPU状态**：执行`top`查看%Cpu(s)行，区分us（用户态）、sy（系统态）、wa（IO等待）
> 2. **定位进程**：`ps aux --sort=-%cpu`找到高CPU进程
> 3. **定位线程**：`ps -eLo pid,tid,%cpu`找到具体线程，Java应用用`jstack`分析线程堆栈
> 4. **用户态高**：通常是应用死循环或密集计算，用`perf top`定位热点函数
> 5. **系统态高**：通常是系统调用频繁或上下文切换多，用`strace`跟踪系统调用
>
> **延伸知识**：wa高不一定是磁盘慢，可能是内存不足触发swap，需先检查`free -h`确认swap使用

---

### 基础 高频 - Q2: 服务器内存不足，如何排查？

> **参考答案**：
> 1. **查看内存状态**：`free -h`关注available字段，接近0表示即将OOM
> 2. **查看进程内存**：`ps aux --sort=-%mem`找到内存占用大的进程
> 3. **查看内存分布**：`cat /proc/meminfo`关注AnonPages（应用内存）和Slab（内核缓存）
> 4. **检查swap**：swap使用>0表示物理内存不足，性能会急剧下降
> 5. **OOM分析**：`dmesg | grep "killed process"`查看被OOM Killer终止的进程
>
> **延伸知识**：Linux的OOM Killer根据oom_score选择终止进程，可通过`oom_score_adj`保护关键进程

---

### 中等 高频 - Q3: 磁盘IO延迟高，如何排查？

> **参考答案**：
> 1. **查看IO统计**：`iostat -x 1`关注await（平均等待时间）和%util（磁盘饱和度）
> 2. **定位高IO进程**：`iotop`或`pidstat -d`找到IO占用高的进程
> 3. **分析IO模式**：`blktrace`分析是随机IO还是顺序IO，随机IO对HDD性能影响大
> 4. **检查调度器**：SSD应使用none调度器，HDD应使用mq-deadline
> 5. **检查文件系统**：`mount`确认noatime等优化选项，避免不必要的元数据更新
>
> **延伸知识**：await = IO在队列中的等待时间 + 磁盘处理时间，队列堆积时await会显著升高

---

### 中等 中频 - Q4: 什么是僵尸进程？如何处理？

> **参考答案**：
> 1. **定义**：僵尸进程是已终止但父进程未调用wait()回收的进程，STAT列为Z
> 2. **影响**：不占用内存和CPU，但占用PID，大量僵尸会导致无法创建新进程
> 3. **排查**：`ps aux | grep "^Z"`找到僵尸进程，记录其PPID
> 4. **处理**：终止父进程（`kill -9 <ppid>`），僵尸进程会被init进程接管并清理
> 5. **预防**：应用程序应正确处理SIGCHLD信号，及时回收子进程
>
> **延伸知识**：D状态进程（不可中断睡眠）比僵尸进程更危险，无法通过kill终止，通常卡在IO操作

---

### 中等 高频 - Q5: 系统无法启动，如何排查？

> **参考答案**：
> 1. **查看启动日志**：进入救援模式执行`journalctl -xb`查看本次启动日志
> 2. **检查文件系统**：`fsck -y /dev/sda1`修复文件系统错误
> 3. **检查磁盘健康**：`smartctl -a`查看SMART状态，确认无硬件故障
> 4. **检查GRUB配置**：确认启动项和内核路径正确
> 5. **重建initramfs**：`dracut -f`重新生成initramfs镜像
>
> **延伸知识**：内核panic常见原因包括硬件故障、驱动bug、内核参数错误，panic信息在`dmesg`中查看

---

### 困难 中频 - Q6: 讲一个你处理过的Linux生产故障案例（STAR-R法）

> **参考答案**（以Java应用CPU飙高为例）：
>
> **Situation**：电商订单服务，日常CPU使用率30%，某天突然飙到95%，订单接口响应时间从200ms增加到5秒，用户投诉下单卡顿
>
> **Task**：作为运维工程师，定位CPU飙高根因并恢复服务
>
> **Action**：
> 1. `top`确认CPU用户态（us）占90%，系统态（sy）正常，判断是应用问题
> 2. `ps aux`找到Java进程占用CPU最高，记录PID
> 3. `ps -eLo pid,tid,%cpu`找到具体线程ID，转换为16进制
> 4. `jstack <pid> | grep -A20 <hex-tid>`定位到订单查询接口的某个正则匹配函数
> 5. 与开发确认：该接口新增了一个复杂的正则校验，在特殊输入下发生灾难性回溯
> 6. 临时注释该校验逻辑，CPU立即下降到正常水平
>
> **Result**：CPU在2分钟内恢复正常，订单接口响应时间恢复到200ms。开发后续优化了正则表达式
>
> **Reflection**：CPU飙高先区分us/sy/wa是关键，us高直接找应用热点。改进措施包括：生产环境部署perf监控、正则表达式纳入代码审查、接口压测覆盖边界输入
>
> **延伸知识**：Java应用CPU飙高三大原因：死循环、正则回溯、频繁Full GC，排查路径各有不同
