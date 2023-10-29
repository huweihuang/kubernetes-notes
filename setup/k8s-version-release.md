---
title: "k8s版本说明"
weight: 5
catalog: true
date: 2022-6-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. k8s版本号说明

k8s维护最新三个版本的发布分支（[2022.7.2]当前**最新三个版本为1.24、1.23、1.22**），Kubernetes 1.19 和更新的版本获得大约 1 年的补丁支持。

Kubernetes 版本表示为 **x.y.z**， 其中 **x** 是主要版本，**y** 是次要版本，**z** 是补丁版本。遵循[语义化版本规范](https://semver.org/)。

# 2. 版本偏差策略

## 2.1. 支持的版本偏差

总结：

- `kubelet` 版本不能比 `kube-apiserver` 版本新，最多只可落后两个次要版本。

- `kube-controller-manager`、`kube-scheduler` 和 `cloud-controller-manager` 不能比 `kube-apiserver` 版本新。最多落后一个次要版本（允许实时升级）。

- `kubectl` 在 `kube-apiserver` 的一个次要版本（较旧或较新）中支持。

- `kube-proxy` 和节点上的 `kubelet` 必须是相同的次要版本。

### 1）kube-apiserver

在[高可用性（HA）集群](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/high-availability/)中， 最新版和最老版的 `kube-apiserver` 实例版本偏差最多为一个次要版本。

例如：

- 最新的 `kube-apiserver` 实例处于 **1.24** 版本
- 其他 `kube-apiserver` 实例支持 **1.24** 和 **1.23** 版本

### 2）kubelet

`kubelet` 版本不能比 `kube-apiserver` 版本新，并且最多只可落后两个次要版本。

例如：

- `kube-apiserver` 处于 **1.24** 版本
- `kubelet` 支持 **1.24**、**1.23** 和 **1.22** 版本

**说明：**

如果 HA 集群中的 `kube-apiserver` 实例之间存在版本偏差，这会缩小允许的 `kubelet` 版本范围。

例如：

- `kube-apiserver` 实例处于 **1.24** 和 **1.23** 版本
- `kubelet` 支持 **1.23** 和 **1.22** 版本， （不支持 **1.24** 版本，因为这将比 `kube-apiserver` **1.23** 版本的实例新）

### 3）kube-controller-manager、kube-scheduler 和 cloud-controller-manager

`kube-controller-manager`、`kube-scheduler` 和 `cloud-controller-manager` 不能比与它们通信的 `kube-apiserver` 实例新。 它们应该与 `kube-apiserver` 次要版本相匹配，但可能最多旧一个次要版本（允许实时升级）。

例如：

- `kube-apiserver` 处于 **1.24** 版本
- `kube-controller-manager`、`kube-scheduler` 和 `cloud-controller-manager` 支持 **1.24** 和 **1.23** 版本

**说明：**

如果 HA 集群中的 `kube-apiserver` 实例之间存在版本偏差， 并且这些组件可以与集群中的任何 `kube-apiserver` 实例通信（例如，通过负载均衡器），这会缩小这些组件所允许的版本范围。

例如：

- `kube-apiserver` 实例处于 **1.24** 和 **1.23** 版本
- `kube-controller-manager`、`kube-scheduler` 和 `cloud-controller-manager` 与可以路由到任何 `kube-apiserver` 实例的负载均衡器通信
- `kube-controller-manager`、`kube-scheduler` 和 `cloud-controller-manager` 支持 **1.23** 版本（不支持 **1.24** 版本，因为它比 **1.23** 版本的 `kube-apiserver` 实例新）

### 4）kubectl

`kubectl` 在 `kube-apiserver` 的一个次要版本（较旧或较新）中支持。

例如：

- `kube-apiserver` 处于 **1.24** 版本
- `kubectl` 支持 **1.25**、**1.24** 和 **1.23** 版本

**说明：**

如果 HA 集群中的 `kube-apiserver` 实例之间存在版本偏差，这会缩小支持的 `kubectl` 版本范围。

例如：

- `kube-apiserver` 实例处于 **1.24** 和 **1.23** 版本
- `kubectl` 支持 **1.24** 和 **1.23** 版本（其他版本将与 `kube-apiserver` 组件之一相差不止一个的次要版本）

### 5）kube-proxy

- `kube-proxy` 和节点上的 `kubelet` 必须是相同的次要版本。
- `kube-proxy` 版本不能比 `kube-apiserver` 版本新。
- `kube-proxy` 最多只能比 `kube-apiserver` 落后两个次要版本。

例如：

如果 `kube-proxy` 版本处于 **1.22** 版本：

- `kubelet` 必须处于相同的次要版本 **1.22**。
- `kube-apiserver` 版本必须介于 **1.22** 和 **1.24** 之间，包括两者。

## 2.2. 组件升级顺序

优先升级kube-apiserver，其他的组件按照上述的版本要求进行升级，最好保持一致的版本。

# 3. k8s版本发布周期

k8s每年大概发布三次，即3-4个月发布一次大版本（发布版本为 `vX.Y` 里程碑创建的 Git 分支 `release-X.Y`）。

发布过程可被认为具有三个主要阶段：

- 特性增强定义
- 实现
- 稳定

## 3.1. 发布周期

1）正常开发（第 1-11 周）

- /sig {name}

- /sig {name}

- /kind {type}

- /lgtm

- /approved

2）[代码冻结](https://git.k8s.io/sig-release/releases/release_phases.md#code-freeze)（第 12-14 周）

- /milestone {v1.y}
- /sig {name}
- /kind {bug, failing-test}
- /lgtm
- /approved

3）发布后（第 14 周以上）

回到“正常开发”阶段要求：

- /sig {name}
- /kind {type}
- /lgtm
- /approved

# 参考：

- [发行版本 | Kubernetes](https://kubernetes.io/zh-cn/releases/)

- [kubernetes/CHANGELOG at master  · GitHub](https://github.com/kubernetes/kubernetes/tree/master/CHANGELOG)

- [sig-release/releases at master · kubernetes/sig-release · GitHub](https://github.com/kubernetes/sig-release/tree/master/releases)

- [design-proposals-archive/versioning.md at main · kubernetes/design-proposals-archive · GitHub](https://github.com/kubernetes/design-proposals-archive/blob/main/release/versioning.md#kubernetes-release-versioning)

- [Kubernetes 发布周期 | Kubernetes](https://kubernetes.io/zh-cn/releases/release/)
