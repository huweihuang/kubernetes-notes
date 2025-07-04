---
title: "Cgroup命令介绍"
weight: 2
catalog: true
date: 2021-07-20 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Runtime
catagories:
- Runtime
---

# cgroup常用命令

# 1. cgcreate

```bash
$ cgcreate --help
Usage: cgcreate [-h] [-f mode] [-d mode] [-s mode] [-t <tuid>:<tgid>] [-a <agid>:<auid>] -g <controllers>:<path> [-g ...]
Create control group(s)
  -a <tuid>:<tgid>		Owner of the group and all its files
  -d, --dperm=mode		Group directory permissions
  -f, --fperm=mode		Group file permissions
  -g <controllers>:<path>	Control group which should be added
  -h, --help			Display this help
  -s, --tperm=mode		Tasks file permissions
  -t <tuid>:<tgid>		Owner of the tasks file
```

示例：

cpu

```bash
# cgcreate -g cpu:cgrouptest

# ll /sys/fs/cgroup/cpu/cgrouptest
总用量 0
-rw-rw-r-- 1 root root 0 8月  15 20:14 cgroup.clone_children
--w--w---- 1 root root 0 8月  15 20:14 cgroup.event_control
-rw-rw-r-- 1 root root 0 8月  15 20:14 cgroup.procs
-r--r--r-- 1 root root 0 8月  15 20:14 cpuacct.stat
-r--r--r-- 1 root root 0 8月  15 20:14 cpuacct.uptime
-rw-rw-r-- 1 root root 0 8月  15 20:14 cpuacct.usage
-r--r--r-- 1 root root 0 8月  15 20:14 cpuacct.usage_percpu
-rw-rw-r-- 1 root root 0 8月  15 20:14 cpu.cfs_period_us
-rw-rw-r-- 1 root root 0 8月  15 20:14 cpu.cfs_quota_us
-rw-rw-r-- 1 root root 0 8月  15 20:14 cpu.cfs_relax_thresh_sec
-rw-rw-r-- 1 root root 0 8月  15 20:14 cpu.rt_period_us
-rw-rw-r-- 1 root root 0 8月  15 20:14 cpu.rt_runtime_us
-rw-rw-r-- 1 root root 0 8月  15 20:14 cpu.shares
-r--r--r-- 1 root root 0 8月  15 20:14 cpu.stat
-rw-rw-r-- 1 root root 0 8月  15 20:14 notify_on_release
-rw-rw-r-- 1 root root 0 8月  15 20:14 tasks
```

memory

```bash
# cgcreate -g memory:cgrouptest

# ll /sys/fs/cgroup/memory/cgrouptest
总用量 0
-rw-rw-r-- 1 root root 0 8月  15 20:16 cgroup.clone_children
--w--w---- 1 root root 0 8月  15 20:16 cgroup.event_control
-rw-rw-r-- 1 root root 0 8月  15 20:16 cgroup.procs
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.failcnt
--w--w---- 1 root root 0 8月  15 20:16 memory.force_empty
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.kmem.failcnt
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.kmem.limit_in_bytes
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.kmem.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  15 20:16 memory.kmem.slabinfo
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.kmem.tcp.failcnt
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.kmem.tcp.limit_in_bytes
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.kmem.tcp.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  15 20:16 memory.kmem.tcp.usage_in_bytes
-r--r--r-- 1 root root 0 8月  15 20:16 memory.kmem.usage_in_bytes
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.limit_in_bytes
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  15 20:16 memory.meminfo
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.memsw.failcnt
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.memsw.limit_in_bytes
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.memsw.max_usage_in_bytes
-r--r--r-- 1 root root 0 8月  15 20:16 memory.memsw.usage_in_bytes
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.move_charge_at_immigrate
-r--r--r-- 1 root root 0 8月  15 20:16 memory.numa_stat
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.oom_control
---------- 1 root root 0 8月  15 20:16 memory.pressure_level
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.soft_limit_in_bytes
-r--r--r-- 1 root root 0 8月  15 20:16 memory.stat
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.swappiness
-r--r--r-- 1 root root 0 8月  15 20:16 memory.usage_in_bytes
-rw-rw-r-- 1 root root 0 8月  15 20:16 memory.use_hierarchy
-r--r--r-- 1 root root 0 8月  15 20:16 memory.vmstat
-rw-rw-r-- 1 root root 0 8月  15 20:16 notify_on_release
-rw-rw-r-- 1 root root 0 8月  15 20:16 tasks
```

# 2. cgdelete

```bash
#cgdelete --help
Usage: cgdelete [-h] [-r] [[-g] <controllers>:<path>] ...
Remove control group(s)
  -g <controllers>:<path>	Control group to be removed (-g is optional)
  -h, --help			Display this help
  -r, --recursive		Recursively remove all subgroups
```

示例

```bash
cgdelete -g memory:/cgrouptest
cgdelete -g cpu:/cgrouptest
```

# 3. cgclassify

```bash
$ cgclassify --help
Usage: cgclassify [[-g] <controllers>:<path>] [--sticky | --cancel-sticky] <list of pids>
Move running task(s) to given cgroups
  -h, --help			Display this help
  -g <controllers>:<path>	Control group to be used as target
  --cancel-sticky		cgred daemon change pidlist and children tasks
  --sticky			cgred daemon does not change pidlist and children tasks
```


