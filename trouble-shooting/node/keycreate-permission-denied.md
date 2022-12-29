---
title: "keycreate permission denied"
weight: 1
catalog: true
date: 2021-6-23 16:22:24
subtitle:
header-img:
tags:
- 问题排查
catagories:
- 问题排查
---

# 问题描述

```
write /proc/self/attr/keycreate: permission denied
```

具体报错：

```bash
kuberuntime_manager.go:758] createPodSandbox for pod "ecc-hostpath-provisioner-8jbhf_kube-system(b8050fd3-4ffe-11eb-a82e-c6090b53405b)" failed: rpc error: code = Unknown desc = failed to start sandbox container for pod "ecc-hostpath-provisioner-8jbhf": Error response from daemon: OCI runtime create failed: container_linux.go:349: starting container process caused "process_linux.go:449: container init caused \"write /proc/self/attr/keycreate: permission denied\"": unknown
```

# 解决办法

SELINUX未设置成disabled

```bash
# 将SELINUX设置成disabled
setenforce 0 # 临时生效
# 永久生效，但需重启，配合上述命令可以不用立即重启
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

# 查看SELinux状态
$ /usr/sbin/sestatus -v 
SELinux status:                 disabled

$ getenforce
Disabled
```
