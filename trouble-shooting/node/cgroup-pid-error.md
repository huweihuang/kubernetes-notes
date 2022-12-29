---
title: "Cgroup不支持pid资源"
weight: 2
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

机器内核版本较低，kubelet启动异常，报错如下：

```
Failed to start ContainerManager failed to initialize top level QOS containers: failed to update top level Burstable QOS cgroup : failed to set supported cgroup subsystems for cgroup [kubepods burstable]: Failed to find subsystem mount for required subsystem: pids
```

# 原因分析

低版本内核的cgroup不支持pids资源的功能，


```
cat /proc/cgroups
#subsys_name	hierarchy	num_cgroups	enabled
cpuset	5	6	1
cpu	2	76	1
cpuacct	2	76	1
memory	4	76	1
devices	10	76	1
freezer	7	6	1
net_cls	3	6	1
blkio	8	76	1
perf_event	9	6	1
hugetlb	6	6	1
```

正常机器的cgroup

```
root@host:~# cat /proc/cgroups
#subsys_name	hierarchy	num_cgroups	enabled
cpuset	5	17	1
cpu	7	80	1
cpuacct	7	80	1
memory	12	80	1
devices	10	80	1
freezer	2	17	1
net_cls	4	17	1
blkio	8	80	1
perf_event	6	17	1
hugetlb	11	17	1
pids	3	80	1    # 此处支持pids资源
oom	9	1	1
```

# 解决方案

1、升级内核版本，使得cgroup支持pids资源。

或者

2、将kubelet的启动参数添加 SupportPodPidsLimit=false,SupportNodePidsLimit=false

```
vi /etc/systemd/system/kubelet.service

# 添加 kubelet 启动参数 
--feature-gates=... ,SupportPodPidsLimit=false,SupportNodePidsLimit=false \

systemctl daemon-reload && systemctl restart kubelet.service
```


文档参考：
- [Kubernetes 1.14 稳定性改进中的进程ID限制](https://kubernetes.io/zh/blog/2019/04/15/kubernetes-1.14-%E7%A8%B3%E5%AE%9A%E6%80%A7%E6%94%B9%E8%BF%9B%E4%B8%AD%E7%9A%84%E8%BF%9B%E7%A8%8Bid%E9%99%90%E5%88%B6/)

- https://blog.csdn.net/qq_38900565/article/details/100707025

- https://adoyle.me/Today-I-Learned/k8s/k8s-deployment.html