---
title: "increase the mlock limit"
weight: 5
catalog: true
date: 2021-6-23 16:22:24
subtitle:
header-img:
tags:
- 问题排查
catagories:
- 问题排查
---

## 问题描述

容器启动报错：increase the mlock limit，原因是ulimit mlock值比较小，需要将ulimit值调大。

报错如下：

```bash
runtime: mlock of signal stack failed: 12
runtime: increase the mlock limit (ulimit -l) or
runtime: update your kernel to 5.3.15+, 5.4.2+, or 5.5+
fatal error: mlock failed

runtime stack:
runtime.throw(0x1a7729f, 0xc)
    /usr/local/go/src/runtime/panic.go:1112 +0x72
runtime.mlockGsignal(0xc000702300)
    /usr/local/go/src/runtime/os_linux_x86.go:72 +0x107
runtime.mpreinit(0xc000588380)
    /usr/local/go/src/runtime/os_linux.go:341 +0x78
runtime.mcommoninit(0xc000588380)
    /usr/local/go/src/runtime/proc.go:630 +0x108
runtime.allocm(0xc000072000, 0x1adcb70, 0x0)
    /usr/local/go/src/runtime/proc.go:1390 +0x14e
runtime.newm(0x1adcb70, 0xc000072000)
    /usr/local/go/src/runtime/proc.go:1704 +0x39
runtime.startm(0x0, 0xc000267e01)
    /usr/local/go/src/runtime/proc.go:1869 +0x12a
runtime.wakep(...)
    /usr/local/go/src/runtime/proc.go:1953
runtime.resetspinning()
    /usr/local/go/src/runtime/proc.go:2415 +0x93
runtime.schedule()
    /usr/local/go/src/runtime/proc.go:2527 +0x2de
runtime.mstart1()
    /usr/local/go/src/runtime/proc.go:1104 +0x8e
runtime.mstart()
    /usr/local/go/src/runtime/proc.go:1062 +0x6e

goroutine 1 [runnable, locked to thread]:
github.com/xdg/stringprep.init()
    /root/go/pkg/mod/github.com/xdg/stringprep@v1.0.3/tables.go:443 +0x19087

goroutine 43 [select]:
go.opencensus.io/stats/view.(*worker).start(0xc00067e800)
    /root/go/pkg/mod/go.opencensus.io@v0.23.0/stats/view/worker.go:276 +0x100
created by go.opencensus.io/stats/view.init.0
    /root/go/pkg/mod/go.opencensus.io@v0.23.0/stats/view/worker.go:34 +0x68
```

## 原因

宿主机的ulimit值比较小，需要将内存的ulimit值调大。

```bash
$ ulimit -l
64
```

## 解决方案

vi /lib/systemd/system/containerd.service。在containerd.service文件中增加`LimitMEMLOCK=infinity` 参数。

```bash
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitMEMLOCK=infinity
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
```

重启containerd

```bash
systemctl daemon-reload
systemctl restart containerd
systemctl status containerd
```


