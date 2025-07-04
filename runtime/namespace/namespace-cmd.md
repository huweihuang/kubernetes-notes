---
title: "Namespace命令介绍"
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

# Namespace相关命令

## 1. unshare

让进程进入一个新的namespace。

```bash
$ unshare --help

用法：
 unshare [options] <program> [<argument>...]

Run a program with some namespaces unshared from the parent.

选项：
 -m, --mount               unshare mounts namespace
 -u, --uts                 unshare UTS namespace (hostname etc)
 -i, --ipc                 unshare System V IPC namespace
 -n, --net                 unshare network namespace
 -p, --pid                 unshare pid namespace
 -U, --user                unshare user namespace
 -f, --fork                fork before launching <program>
     --mount-proc[=<dir>]  mount proc filesystem first (implies --mount)
 -r, --map-root-user       map current user to root (implies --user)
     --propagation <slave|shared|private|unchanged>
                           modify mount propagation in mount namespace
 -s, --setgroups allow|deny  control the setgroups syscall in user namespaces

 -h, --help     显示此帮助并退出
 -V, --version  输出版本信息并退出

更多信息请参阅 unshare(1)。
```

示例：



## 2. nsenter

进入某个namespace下运行某个进程。例如：docker exec -it <container_id> bash。

```bash
$ nsenter --help

用法：
 nsenter [options] <program> [<argument>...]

Run a program with namespaces of other processes.

选项：
 -t, --target <pid>     要获取名字空间的目标进程
 -m, --mount[=<file>]   enter mount namespace
 -u, --uts[=<file>]     enter UTS namespace (hostname etc)
 -i, --ipc[=<file>]     enter System V IPC namespace
 -n, --net[=<file>]     enter network namespace
 -p, --pid[=<file>]     enter pid namespace
 -U, --user[=<file>]    enter user namespace
 -S, --setuid <uid>     set uid in entered namespace
 -G, --setgid <gid>     set gid in entered namespace
     --preserve-credentials do not touch uids or gids
 -r, --root[=<dir>]     set the root directory
 -w, --wd[=<dir>]       set the working directory
 -F, --no-fork          执行 <程序> 前不 fork
 -Z, --follow-context   set SELinux context according to --target PID

 -h, --help     显示此帮助并退出
 -V, --version  输出版本信息并退出

更多信息请参阅 nsenter(1)。
```
