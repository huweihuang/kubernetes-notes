---
title: "Cgroup目录"
weight: 3
catalog: true
date: 2021-07-20 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Runtime
catagories:
- Runtime
---

# 1. cgroup的目录

`/sys/fs/cgroup/`

```bash
$ ll /sys/fs/cgroup/
总用量 0
drwxr-xr-x 6 root root  0 2月  18 14:31 blkio
lrwxrwxrwx 1 root root 11 2月  18 14:25 cpu -> cpu,cpuacct
lrwxrwxrwx 1 root root 11 2月  18 14:25 cpuacct -> cpu,cpuacct
drwxr-xr-x 6 root root  0 2月  18 14:31 cpu,cpuacct
drwxr-xr-x 4 root root  0 2月  18 14:25 cpuset
drwxr-xr-x 6 root root  0 2月  18 14:31 devices
drwxr-xr-x 4 root root  0 2月  18 14:25 freezer
drwxr-xr-x 4 root root  0 2月  18 14:25 hugetlb
drwxr-xr-x 6 root root  0 2月  18 14:31 memory
drwxr-xr-x 4 root root  0 2月  18 14:25 net_cls
drwxr-xr-x 2 root root  0 2月  18 14:25 oom
drwxr-xr-x 4 root root  0 2月  18 14:25 perf_event
drwxr-xr-x 6 root root  0 2月  18 14:31 pids
drwxr-xr-x 6 root root  0 2月  18 14:25 systemd
```

# 2. docker中cgroup目录

## 2.1. cpu

`/sys/fs/cgroup/cpu/docker/32a294d870965072acbf544da0c93a1692660d908bd72de43d1da48852083094`

```bash
# ll /sys/fs/cgroup/cpu/docker/32a294d870965072acbf544da0c93a1692660d908bd72de43d1da48852083094
总用量 0
-rw-r--r-- 1 root root 0 7月   8 17:04 cgroup.clone_children
--w--w--w- 1 root root 0 7月   8 17:04 cgroup.event_control
-rw-r--r-- 1 root root 0 7月   8 17:04 cgroup.procs
-r--r--r-- 1 root root 0 7月   8 17:04 cpuacct.stat
-r--r--r-- 1 root root 0 7月   8 17:04 cpuacct.uptime
-rw-r--r-- 1 root root 0 7月   8 17:04 cpuacct.usage
-r--r--r-- 1 root root 0 7月   8 17:04 cpuacct.usage_percpu
-rw-r--r-- 1 root root 0 7月   8 17:04 cpu.cfs_period_us
-rw-r--r-- 1 root root 0 7月   8 17:04 cpu.cfs_quota_us
-rw-r--r-- 1 root root 0 7月   8 17:04 cpu.cfs_relax_thresh_sec
-rw-r--r-- 1 root root 0 7月   8 17:04 cpu.rt_period_us
-rw-r--r-- 1 root root 0 7月   8 17:04 cpu.rt_runtime_us
-rw-r--r-- 1 root root 0 7月   8 17:04 cpu.shares
-r--r--r-- 1 root root 0 7月   8 17:04 cpu.stat
-rw-r--r-- 1 root root 0 7月   8 17:04 notify_on_release
-rw-r--r-- 1 root root 0 7月   8 17:04 tasks
```

## 2.2. memory

```bash
# ll /sys/fs/cgroup/memory/docker/32a294d870965072acbf544da0c93a1692660d908bd72de43d1da48852083094
总用量 0
-rw-r--r-- 1 root root 0 7月   8 17:04 cgroup.clone_children
--w--w--w- 1 root root 0 7月   8 17:04 cgroup.event_control
-rw-r--r-- 1 root root 0 7月   8 17:04 cgroup.procs
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.failcnt
--w------- 1 root root 0 7月   8 17:04 memory.force_empty
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.kmem.failcnt
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.kmem.limit_in_bytes
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.kmem.max_usage_in_bytes
-r--r--r-- 1 root root 0 7月   8 17:04 memory.kmem.slabinfo
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.kmem.tcp.failcnt
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.kmem.tcp.limit_in_bytes
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.kmem.tcp.max_usage_in_bytes
-r--r--r-- 1 root root 0 7月   8 17:04 memory.kmem.tcp.usage_in_bytes
-r--r--r-- 1 root root 0 7月   8 17:04 memory.kmem.usage_in_bytes
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.limit_in_bytes
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.max_usage_in_bytes
-r--r--r-- 1 root root 0 7月   8 17:04 memory.meminfo
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.memsw.failcnt
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.memsw.limit_in_bytes
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.memsw.max_usage_in_bytes
-r--r--r-- 1 root root 0 7月   8 17:04 memory.memsw.usage_in_bytes
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.move_charge_at_immigrate
-r--r--r-- 1 root root 0 7月   8 17:04 memory.numa_stat
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.oom_control
---------- 1 root root 0 7月   8 17:04 memory.pressure_level
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.soft_limit_in_bytes
-r--r--r-- 1 root root 0 7月   8 17:04 memory.stat
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.swappiness
-r--r--r-- 1 root root 0 7月   8 17:04 memory.usage_in_bytes
-rw-r--r-- 1 root root 0 7月   8 17:04 memory.use_hierarchy
-r--r--r-- 1 root root 0 7月   8 17:04 memory.vmstat
-rw-r--r-- 1 root root 0 7月   8 17:04 notify_on_release
-rw-r--r-- 1 root root 0 7月   8 17:04 tasks
```

# 3. pod中cgroup目录

## 3.1. cpu

```bash
#ll /sys/fs/cgroup/cpu/kubepods/burstable/pode90435b5-4673-4bc2-9892-1f4825af5039/f62fb0f76b5b48cf903680296a1ba2abc314fdbf51e023886d06f8470d5ca90d
总用量 0
-rw-r--r-- 1 root root 0 8月  14 15:33 cgroup.clone_children
--w--w--w- 1 root root 0 8月  14 15:33 cgroup.event_control
-rw-r--r-- 1 root root 0 8月  14 15:33 cgroup.procs
-r--r--r-- 1 root root 0 8月  14 15:33 cpuacct.stat
-r--r--r-- 1 root root 0 8月  14 15:33 cpuacct.uptime
-rw-r--r-- 1 root root 0 8月  14 15:33 cpuacct.usage
-r--r--r-- 1 root root 0 8月  14 15:33 cpuacct.usage_percpu
-rw-r--r-- 1 root root 0 8月  14 15:33 cpu.cfs_period_us  #
-rw-r--r-- 1 root root 0 8月  14 15:33 cpu.cfs_quota_us   #
-rw-r--r-- 1 root root 0 8月  14 15:33 cpu.cfs_relax_thresh_sec
-rw-r--r-- 1 root root 0 8月  14 15:33 cpu.rt_period_us
-rw-r--r-- 1 root root 0 8月  14 15:33 cpu.rt_runtime_us
-rw-r--r-- 1 root root 0 8月  14 15:33 cpu.shares   #
-r--r--r-- 1 root root 0 8月  14 15:33 cpu.stat
-rw-r--r-- 1 root root 0 8月  14 15:33 notify_on_release
-rw-r--r-- 1 root root 0 8月  14 15:33 tasks
```

## 3.2. memory

```bash
#ll /sys/fs/cgroup/memory/kubepods/burstable/pode90435b5-4673-4bc2-9892-1f4825af5039/f62fb0f76b5b48cf903680296a1ba2abc314fdbf51e023886d06f8470d5ca90d
总用量 0
-rw-r--r-- 1 root root 0 8月  14 15:33 cgroup.clone_children
--w--w--w- 1 root root 0 8月  14 15:33 cgroup.event_control
-rw-r--r-- 1 root root 0 8月  14 15:33 cgroup.procs
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.failcnt
--w------- 1 root root 0 8月  14 15:33 memory.force_empty
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.kmem.failcnt
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.kmem.limit_in_bytes
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.kmem.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  14 15:33 memory.kmem.slabinfo
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.kmem.tcp.failcnt
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.kmem.tcp.limit_in_bytes
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.kmem.tcp.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  14 15:33 memory.kmem.tcp.usage_in_bytes
-r--r--r-- 1 root root 0 8月  14 15:33 memory.kmem.usage_in_bytes
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.limit_in_bytes
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  14 15:33 memory.meminfo
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.memsw.failcnt
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.memsw.limit_in_bytes
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.memsw.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  14 15:33 memory.memsw.usage_in_bytes
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.move_charge_at_immigrate
-r--r--r-- 1 root root 0 8月  14 15:33 memory.numa_stat
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.oom_control
---------- 1 root root 0 8月  14 15:33 memory.pressure_level
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.soft_limit_in_bytes
-r--r--r-- 1 root root 0 8月  14 15:33 memory.stat
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.swappiness
-r--r--r-- 1 root root 0 8月  14 15:33 memory.usage_in_bytes
-rw-r--r-- 1 root root 0 8月  14 15:33 memory.use_hierarchy
-r--r--r-- 1 root root 0 8月  14 15:33 memory.vmstat
-rw-r--r-- 1 root root 0 8月  14 15:33 notify_on_release
-rw-r--r-- 1 root root 0 8月  14 15:33 tasks
```

