---
title: "Cgroup介绍"
weight: 1
catalog: true
date: 2021-07-20 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Runtime
catagories:
- Runtime
---

# 1. cgroup简介

Linux Cgroup提供了对一组进程及将来子进程的资源限制的能力。资源包括：CPU、内存、存储、网络等。通过Cgroup可以限制某个进程的资源占用，并监控进程的统计信息。

# 2. cgroup示例

1、创建一个hierarchy（cgroup树）

```bash
# 创建一个 hierarchy 挂载点
mkdir cgroup-test 
# 挂载hierarchy 挂载点
mount -t cgroup -o none,name=cgroup-test cgroup-test ./cgroup-test
# 查看生成的默认文件
# ll
总用量 0
-rw-r--r-- 1 root root 0 3月   5 19:13 cgroup.clone_children
--w--w--w- 1 root root 0 3月   5 19:13 cgroup.event_control
-rw-r--r-- 1 root root 0 3月   5 19:13 cgroup.procs
-r--r--r-- 1 root root 0 3月   5 19:13 cgroup.sane_behavior
-rw-r--r-- 1 root root 0 3月   5 19:13 notify_on_release
-rw-r--r-- 1 root root 0 3月   5 19:13 release_agent
-rw-r--r-- 1 root root 0 3月   5 19:13 tasks
```

2、在根cgroup创建2个子cgroup

在cgroup目录下创建目录，子cgroup会继承父cgroup的属性。

```bash
mkdir cgroup-1
mkdir cgroup-2

# tree
.
├── cgroup-1
│   ├── cgroup.clone_children
│   ├── cgroup.event_control
│   ├── cgroup.procs
│   ├── notify_on_release
│   └── tasks
├── cgroup-2
│   ├── cgroup.clone_children
│   ├── cgroup.event_control
│   ├── cgroup.procs
│   ├── notify_on_release
│   └── tasks
├── cgroup.clone_children
├── cgroup.event_control
├── cgroup.procs
├── cgroup.sane_behavior
├── notify_on_release
├── release_agent
└── tasks
```

3、在cgroup中添加和移动进程。

```bash
echo $$ > tasks
```

4、通过subsystem限制cgroup中进程的资源。

系统为每个subsystem创建了一个默认的hierarchy。

# 3. cgroup限制CPU

1、启动进程，将cpu打到100%

```bash
# 启动进程，将cpu打到100%
stress-ng -c 1 --cpu-load 100 &
# 查看cpu占用
#ps auxw|grep stress
root      7607  0.0  0.0  56320  3620 pts/1    SL   10:35   0:00 stress-ng -c 1 --cpu-load 100
root      7608  100  0.0  56964  4076 pts/1    R    10:35   0:14 stress-ng -c 1 --cpu-load 100
# top
  PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
 7608 root      20   0   56964   4076   1192 R 100.0  0.0   0:37.70 stress-ng-cpu
```

2、在`/sys/fs/cgroup/cpu`下创建子cgroup

```bash
# 创建子目录
cd /sys/fs/cgroup/cpu && mkdir cgroup-test
# 生成cgroup文件
/sys/fs/cgroup/cpu/cgroup-test#ll
总用量 0
-rw-r--r-- 1 root root 0 3月   9 20:28 cgroup.clone_children
--w--w--w- 1 root root 0 3月   9 20:28 cgroup.event_control
-rw-r--r-- 1 root root 0 3月   9 20:28 cgroup.procs
-r--r--r-- 1 root root 0 3月   9 20:28 cpuacct.bt_stat
-rw-r--r-- 1 root root 0 3月   9 20:28 cpuacct.bt_usage
-r--r--r-- 1 root root 0 3月   9 20:28 cpuacct.bt_usage_percpu
-r--r--r-- 1 root root 0 3月   9 20:28 cpuacct.stat
-r--r--r-- 1 root root 0 3月   9 20:28 cpuacct.uptime
-rw-r--r-- 1 root root 0 3月   9 20:28 cpuacct.usage
-r--r--r-- 1 root root 0 3月   9 20:28 cpuacct.usage_percpu
-rw-r--r-- 1 root root 0 3月   9 20:28 cpu.bt_shares
-rw-r--r-- 1 root root 0 3月  10 10:34 cpu.cfs_period_us
-rw-r--r-- 1 root root 0 3月   9 20:29 cpu.cfs_quota_us
-rw-r--r-- 1 root root 0 3月   9 20:28 cpu.cfs_relax_thresh_sec
-rw-r--r-- 1 root root 0 3月   9 20:28 cpu.offline
-rw-r--r-- 1 root root 0 3月   9 20:28 cpu.rt_period_us
-rw-r--r-- 1 root root 0 3月   9 20:28 cpu.rt_runtime_us
-rw-r--r-- 1 root root 0 3月   9 20:28 cpu.shares
-r--r--r-- 1 root root 0 3月   9 20:28 cpu.stat
-rw-r--r-- 1 root root 0 3月   9 20:28 notify_on_release
-rw-r--r-- 1 root root 0 3月  10 10:32 tasks
```

3、限制进程的cpu

```bash
# 限制cpu比例为 cpu.cfs_quota_us/cpu.cfs_period_us,默认cpu.cfs_period_us为100000
cd /sys/fs/cgroup/cpu/cgroup-test
echo 50000 > cpu.cfs_quota_us  # 限制cpu使用率为50%

# 将进程号写入tasks
echo 7608 > tasks

# 查看cpu使用率，可以看出cpu限制在50%
 PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
 7608 root      20   0   56964   4076   1192 R  50.2  0.0   9:08.24 stress-ng-cpu
```

# 4. cgroup限制内存

1、进入`/sys/fs/cgroup/memory`创建子cgroup

```bash
cd /sys/fs/cgroup/memory
mkdir cgroup-test

# 查看子cgroup生成内容
/sys/fs/cgroup/memory/cgroup-test#ll
总用量 0
-rw-r--r-- 1 root root 0 3月  10 10:51 cgroup.clone_children
--w--w--w- 1 root root 0 3月  10 10:51 cgroup.event_control
-rw-r--r-- 1 root root 0 3月  10 10:51 cgroup.procs
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.failcnt
--w------- 1 root root 0 3月  10 10:51 memory.force_empty
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.kmem.failcnt
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.kmem.limit_in_bytes
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.kmem.max_usage_in_bytes
-r--r--r-- 1 root root 0 3月  10 10:51 memory.kmem.slabinfo
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.kmem.tcp.failcnt
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.kmem.tcp.limit_in_bytes
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.kmem.tcp.max_usage_in_bytes
-r--r--r-- 1 root root 0 3月  10 10:51 memory.kmem.tcp.usage_in_bytes
-r--r--r-- 1 root root 0 3月  10 10:51 memory.kmem.usage_in_bytes
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.limit_in_bytes
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.max_usage_in_bytes
-r--r--r-- 1 root root 0 3月  10 10:51 memory.meminfo
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.memsw.failcnt
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.memsw.limit_in_bytes
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.memsw.max_usage_in_bytes
-r--r--r-- 1 root root 0 3月  10 10:51 memory.memsw.usage_in_bytes
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.move_charge_at_immigrate
-r--r--r-- 1 root root 0 3月  10 10:51 memory.numa_stat
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.oom_control
---------- 1 root root 0 3月  10 10:51 memory.pressure_level
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.soft_limit_in_bytes
-r--r--r-- 1 root root 0 3月  10 10:51 memory.stat
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.swappiness
-r--r--r-- 1 root root 0 3月  10 10:51 memory.usage_in_bytes
-rw-r--r-- 1 root root 0 3月  10 10:51 memory.use_hierarchy
-r--r--r-- 1 root root 0 3月  10 10:51 memory.vmstat
-rw-r--r-- 1 root root 0 3月  10 10:51 notify_on_release
-rw-r--r-- 1 root root 0 3月  10 10:51 tasks
```

2、限制进程内存为100M

```bash
# 设置当前cgroup限制进程内存100M
cd /sys/fs/cgroup/memory/cgroup-tes
echo 100m > memory.limit_in_bytes
# 查看文件内容
/sys/fs/cgroup/memory/cgroup-test#cat memory.limit_in_bytes
104857600
```

3、启动测试进程

```bash
# 把当前的bash进程加入tasks
echo $$ > tasks
#cat tasks
7125
11980

# ps auxw|grep 7125
root      7125  0.0  0.0 115116  2588 pts/1    Ss   10:35   0:00 -bash

# 启动50M的进程
cd /sys/fs/cgroup/memory/cgroup-test
stress-ng --vm-bytes 50m --vm-keep -m 1 &

# 进程内存占用为50M，可正常运行
ps auxw|grep stress
root     20021  100  0.0 113932 58188 pts/1    R    10:58   2:13 stress-ng --vm-bytes 50m --vm-keep -m 1

# 改用启动200M的测试进程
stress-ng --vm-bytes 200m --vm-keep -m 1
# ps auxw|grep stress
root     29937  0.0  0.0  56320  3644 pts/1    SL   11:16   0:00 stress-ng --vm-bytes 200m --vm-keep -m 1
root     29938  0.1  0.0  56324   976 pts/1    S    11:16   0:00 stress-ng --vm-bytes 200m --vm-keep -m 1
# cat tasks
7125
29937
29938
32247
32248
```

4、进程OOM

```bash
tailf /var/log/messages
# OOM日志
Mar 10 11:19:17  kernel: stress-ng-vm invoked oom-killer: gfp_mask=0xd0, order=0, oom_score_adj=1000
Mar 10 11:19:17  kernel: stress-ng-vm cpuset=/ mems_allowed=0
Mar 10 11:19:17  kernel: CPU: 11 PID: 3691 Comm: stress-ng-vm Not tainted 3.10.107-1-tlinux2-0051 #1
Mar 10 11:19:17  kernel: Hardware name: Inspur SA5212M4/Shuyu, BIOS 4.1.13 01/24/2018
Mar 10 11:19:17  kernel: ffff880f5d92cd70 0000000094b48ef1 ffff880f2cee3c90 ffffffff819d9165
Mar 10 11:19:17  kernel: ffff880f2cee3cd0 ffffffff819d4957 000000002d514000 ffff880f5d92cd70
Mar 10 11:19:17  kernel: 0000000000000786 00000000000000d0 ffffffff81d73d78 0000000000006400
Mar 10 11:19:17  kernel: Call Trace:
Mar 10 11:19:17  kernel: [<ffffffff819d9165>] dump_stack+0x19/0x1b
Mar 10 11:19:17  kernel: [<ffffffff819d4957>] dump_header+0x79/0xb5
Mar 10 11:19:17  kernel: [<ffffffff81120aee>] oom_kill_process+0x24e/0x3a0
Mar 10 11:19:17  kernel: [<ffffffff8117b2f9>] mem_cgroup_oom_synchronize+0x4e9/0x510
Mar 10 11:19:17  kernel: [<ffffffff8117a330>] ? mem_cgroup_charge_common+0xc0/0xc0
Mar 10 11:19:17  kernel: [<ffffffff81121764>] pagefault_out_of_memory+0x14/0x90
Mar 10 11:19:17  kernel: [<ffffffff819d32dd>] mm_fault_error+0x67/0x140
Mar 10 11:19:17  kernel: [<ffffffff819e7ae6>] __do_page_fault+0x396/0x550
Mar 10 11:19:17  kernel: [<ffffffff8108335f>] ? set_next_entity+0x5f/0x80
Mar 10 11:19:17  kernel: [<ffffffff81084e63>] ? pick_next_task_fair+0x1c3/0x2d0
Mar 10 11:19:17  kernel: [<ffffffff819e7cae>] do_page_fault+0xe/0x10
Mar 10 11:19:17  kernel: [<ffffffff819e4422>] page_fault+0x22/0x30
Mar 10 11:19:17  kernel: Task in /cgroup-test killed as a result of limit of /cgroup-test
Mar 10 11:19:17  kernel: memory: usage 102400kB, limit 102400kB, failcnt 252574
Mar 10 11:19:17  kernel: memory+swap: usage 102400kB, limit 18014398509481983kB, failcnt 0
Mar 10 11:19:17  kernel: kmem: usage 0kB, limit 18014398509481983kB, failcnt 0
Mar 10 11:19:17  kernel: Memory cgroup stats for /cgroup-test: cache:101728KB rss:672KB rss_huge:0KB mapped_file:101728KB swap:0KB inactive_anon:101712KB active_anon:600KB inactive_file:0KB active_file:0KB unevictable:16KB
Mar 10 11:19:17  kernel: [ pid ]   uid  tgid total_vm      rss nr_ptes swapents oom_score_adj name
Mar 10 11:19:17  kernel: [ 7125]     0  7125    28779      650      15        0             0 bash
Mar 10 11:19:17  kernel: [29937]     0 29937    14080      911      23        0         -1000 stress-ng
Mar 10 11:19:17  kernel: [29938]     0 29938    14081      244      23        0         -1000 stress-ng-vm
Mar 10 11:19:17  kernel: [ 3691]     0  3691    65281    24993      73        0          1000 stress-ng-vm
Mar 10 11:19:17  kernel: Memory cgroup out of memory: Kill process 3691 (stress-ng-vm) score 1926 or sacrifice child
Mar 10 11:19:17  kernel: Killed process 3691 (stress-ng-vm) total-vm:261124kB, anon-rss:292kB, file-rss:99680kB
Mar 10 11:19:17  cadvisor: I0310 11:19:17.952314    3143 manager.go:1178] Created an OOM event in container "/cgroup-test" at 2021-03-10 11:21:19.308776449 +0800 CST m=+150332.715342256
Mar 10 11:19:17  stress-ng: memory (MB): total 63979.26, free 58262.03, shared 0.00, buffer 481.01, swap 0.00, free swap 0.00
Mar 10 11:19:18  kernel: Memory cgroup out of memory: Kill process 3692 (stress-ng-vm) score 1926 or sacrifice child
Mar 10 11:19:18  kernel: Killed process 3692 (stress-ng-vm) total-vm:261124kB, anon-rss:292kB, file-rss:99680kB
Mar 10 11:19:18  stress-ng: memory (MB): total 63979.26, free 58262.15, shared 0.00, buffer 481.01, swap 0.00, free swap 0.00
```






参考：

- https://www.kernel.org/doc/Documentation/cgroup-v1/cgroups.txt