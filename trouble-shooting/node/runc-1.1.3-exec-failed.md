---
title: "runc-v1.1.3-exec-failed"
weight: 4
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

当使用`runc 1.1.3`的版本时，如果执行`systemctl daemon-reload`后，通过exec进入容器则会触发以下错误，无法进入容器。

```bash
FATA[0000] execing command in container: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "33d05b4f71a2da69c8c77cc3f7e61451814eb150edd15d0a3153b57a862126d4": OCI runtime exec failed: exec failed: unable to start container process: open /dev/pts/0: operation not permitted: unknown
```

## 原因

这个是runc 1.1.3版本起存在的一个bug，runc1.1.2的版本不存在，社区在runc 1.1.4的版本中修复了这个bug。由于 runc v1.1.3 中不再添加 `DeviceAllow=char-pts rwm` 规则了，当执行 `systemctl daemon-reload` 后， 会导致重新应用 systemd 的规则，进而导致这条规则的缺失。

## 解决方案

升级runc到1.1.4的版本，并且所有通过runc1.1.3创建的pod都需要重建才能生效。

参考：

- https://github.com/containerd/containerd/issues/7219#issuecomment-1225358826  

- https://github.com/opencontainers/runc/issues/3551

- [Release runc 1.1.4 -- &quot;If you look for perfection, you&#39;ll never be content.&quot; · opencontainers/runc · GitHub](https://github.com/opencontainers/runc/releases/tag/v1.1.4)


