---
title: "k8s版本说明"
weight: 3
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

# 2. 最新发行版本

# [1.24](https://kubernetes.io/zh-cn/releases/#release-v1-24)

最新发行版本：1.24.2 (发布日期: 2022-06-15）

不再支持：2023-09-29

**补丁版本：** [1.24.1](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.24.md#v1241)、 [1.24.2](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.24.md#v1242)

Complete 1.24 [Schedule](https://kubernetes.io/releases/patch-releases/#1-24) and [Changelog](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.24.md)

Kubernetes 1.24 使用 **go1.18**构建，默认情况下将不再验证使用 SHA-1 哈希算法签名的证书。

## 2.1.1. 重要更新

1.24.0主要参考[kubernetes/CHANGELOG-1.24.major-themes](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.24.md#major-themes)

### 1）kubelet完全移除Dockershim【最重大更新】

在 v1.20 中弃用后，dockershim 组件已从 kubelet 中删除。从 v1.24 开始，您将需要使用其他受支持的运行时之一（例如 containerd 或 CRI-O），或者如果您依赖 Docker 引擎作为容器运行时，则使用 cri-dockerd。有关确保您的集群已准备好进行此移除的更多信息，请参阅本[指南]([Is Your Cluster Ready for v1.24? | Kubernetes](https://kubernetes.io/blog/2022/03/31/ready-for-dockershim-removal/))。

### 2）Beta API 默认关闭

默认情况下，不会在集群中启用新的 beta API。默认情况下，现有的 beta API 和现有 beta API 的新版本将继续启用。

### 3）存储容量和卷扩展到GA

存储容量跟踪支持通过 CSIStorageCapacity 对象公开当前可用的存储容量，并增强使用具有后期绑定的 CSI 卷的 pod 的调度。

卷扩展增加了对调整现有持久卷大小的支持。

### 4）避免 IP 分配给service的冲突

Kubernetes 1.24 引入了一项新的选择加入功能，允许您为服务的静态 IP 地址分配软预留范围。通过手动启用此功能，集群将更喜欢从服务 IP 地址池中自动分配，从而降低冲突风险。

可以分配 Service ClusterIP：

- 动态，这意味着集群将自动在配置的服务 IP 范围内选择一个空闲 IP。

- 静态，这意味着用户将在配置的服务 IP 范围内设置一个 IP。

Service ClusterIP 是唯一的，因此，尝试使用已分配的 ClusterIP 创建 Service 将返回错误。

## 2.1.2. 弃用更新

### 1）kubeadm

- **kubeadm.k8s.io/v1beta2 已被弃用**，并将在未来的版本中删除，可能在 3 个版本（一年）中。您应该开始将 **kubeadm.k8s.io/v1beta3 用于新集群**。要迁移磁盘上的旧配置文件，您可以使用 kubeadm config migrate 命令。

- **默认 k​​ubeadm 配置为 containerd 套接字**（Unix：unix:///var/run/containerd/containerd.sock，Windows：npipe:////./pipe/containerd-containerd）而不是 Docker 的配置.如果在集群创建期间 Init|JoinConfiguration.nodeRegistration.criSocket 字段为空，并且在主机上发现多个套接字，则总是会抛出错误并要求用户通过设置字段中的值来指定要使用的套接字。使用 crictl 与 CRI 套接字进行所有通信，以执行诸如拉取图像和获取正在运行的容器列表等操作，而不是在 Docker 的情况下使用 docker CLI。

- kubeadm 迁移到标签和污点中不再使用 master 一词。对于新的集群，**标签 node-role.kubernetes.io/master 将不再添加到控制平面节点，只会添加标签 node-role.kubernetes.io/control-plane**。

### 2）kube-apiserver

- 不安全的地址标志 --address、--insecure-bind-address、--port 和 --insecure-port（自 1.20 起惰性）被删除

- 弃用了--master-countflag 和--endpoint-reconciler-type=master-countreconciler，转而使用 lease reconciler。

- 已弃用Service.Spec.LoadBalancerIP。

### 3）kube-controller-manager

- kube-controller-manager 中的不安全地址标志 --address 和 --port 自 v1.20 起无效，并在 v1.24 中被删除。

### 4）kubelet

- --pod-infra-container-image kubelet 标志已弃用，将在未来版本中删除。

- **以下与 dockershim 相关的标志也与 dockershim 一起被删除 --experimental-dockershim-root-directory、--docker-endpoint、--image-pull-progress-deadline、--network-plugin、--cni-conf -dir，--cni-bin-dir，--cni-cache-dir，--network-plugin-mtu。([#106907](https://github.com/kubernetes/kubernetes/pull/106907), [@cyclinder](https://github.com/cyclinder))**

# [1.23](https://kubernetes.io/zh-cn/releases/#release-v1-23)

最新发行版本：1.23.8 (发布日期: 2022-06-15）

不再支持：2023-02-28

**补丁版本：** [1.23.1](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1231)、 [1.23.2](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1232)、 [1.23.3](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1233)、 [1.23.4](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1234)、 [1.23.5](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1235)、 [1.23.6](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1236)、 [1.23.7](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1237)、 [1.23.8](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1238)

Complete 1.23 [Schedule](https://kubernetes.io/releases/patch-releases/#1-23) and [Changelog](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md)

Kubernetes 是使用 **golang 1.17** 构建的。此版本的 go 删除了使用 GODEBUG=x509ignoreCN=0 环境设置来重新启用将 X.509 服务证书的 CommonName 视为主机名的已弃用旧行为的能力。

## 2.2.1. 重要更新

### 1）FlexVolume 已弃用

FlexVolume 已弃用。 Out-of-tree CSI 驱动程序是在 Kubernetes 中编写卷驱动程序的推荐方式。FlexVolume 驱动程序的维护者应实施 CSI 驱动程序并将 FlexVolume 的用户转移到 CSI。 FlexVolume 的用户应将其工作负载转移到 CSI 驱动程序。

### 2）IPv4/IPv6 双栈网络到 GA

IPv4/IPv6 双栈网络从 GA 毕业。从 1.21 开始，Kubernetes 集群默认启用支持双栈网络。在 1.23 中，移除了 IPv6DualStack 功能门。双栈网络的使用不是强制性的。尽管启用了集群以支持双栈网络，但 Pod 和服务继续默认为单栈。要使用双栈网络：Kubernetes 节点具有可路由的 IPv4/IPv6 网络接口，使用支持双栈的 CNI 网络插件，Pod 配置为双栈，服务的 .spec.ipFamilyPolicy 字段设置为 PreferDualStack 或需要双栈。

### 3）Horizo​​ntalPodAutoscaler v2 到 GA

Horizo​​ntalPodAutoscaler API 的第 2 版在 1.23 版本中逐渐稳定。 Horizo​​ntalPodAutoscaler autoscaling/v2beta2 API 已弃用，取而代之的是新的 autoscaling/v2 API，Kubernetes 项目建议将其用于所有用例。

### 4）Scheduler简化多点插件配置

kube-scheduler 正在为插件添加一个新的、简化的配置字段，以允许在一个位置启用多个扩展点。新的 multiPoint 插件字段旨在为管理员简化大多数调度程序设置。通过 multiPoint 启用的插件将自动为它们实现的每个单独的扩展点注册。例如，实现 Score 和 Filter 扩展的插件可以同时为两者启用。这意味着可以启用和禁用整个插件，而无需手动编辑单个扩展点设置。这些扩展点现在可以被抽象出来，因为它们与大多数用户无关。

## 2.2.2. 已知问题

在 1.22 Kubernetes 版本附带的 **etcd v3.5.0 版本中发现了数据损坏问题**。请阅读 etcd 的最新[生产建议]([etcd/CHANGELOG at main · etcd-io/etcd · GitHub](https://github.com/etcd-io/etcd/tree/main/CHANGELOG))。

运行etcd v3.5.2 v3.5.1和v3.5.0高负荷会导致数据损坏问题。如果etcd进程被杀,偶尔有些已提交的事务并不反映在所有的成员。建议升级到**v3.5.3**。

**最低推荐etcd版本运行在生产3.3.18 + 3.4.2 + v3.5.3 +。**

# [1.22](https://kubernetes.io/zh-cn/releases/#release-v1-22)

最新发行版本：1.22.11 (发布日期: 2022-06-15）

不再支持：2022-10-28

**补丁版本：** [1.22.1](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1221)、 [1.22.2](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1222)、 [1.22.3](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1223)、 [1.22.4](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1224)、 [1.22.5](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1225)、 [1.22.6](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1226)、 [1.22.7](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1227)、 [1.22.8](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1228)、 [1.22.9](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1229)、 [1.22.10](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v12210)、 [1.22.11](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v12211)

Complete 1.22 [Schedule](https://kubernetes.io/releases/patch-releases/#1-22) and [Changelog](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md)

## 2.3.1. 重要更新

### 1）kubeadm

- 允许非root用户允许kubeadm。

- 现在V1beta3首选API版本;v1beta2 API也仍然是可用的,并没有弃用。

- 移除对docker cgroup driver的检查，kubeadm默认使用systemd cgroup driver，需要手动将runtime配置为systemd。

- v1beta3中删除ClusterConfiguration.DNS字段，因为CoreDNS是唯一支持DNS类型。

### 2）etcd

- etcd使用v3.5.0版本。（但是在1.23版本中发现v3.5.0有数据损坏的问题）

### 3）kubelet

- 节点支持swap内存。

- 作为α特性,Kubernetes v1.22并且可以使用cgroup v2 API来控制内存分配和隔离。这个功能的目的是改善工作负载和节点可用性时对内存资源的争用。

# 3. 版本偏差策略

## 3.1. 支持的版本偏差

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

## 3.2. 组件升级顺序

优先升级kube-apiserver，其他的组件按照上述的版本要求进行升级，最好保持一致的版本。

# 4. k8s版本发布周期

k8s每年大概发布三次，即3-4个月发布一次大版本（发布版本为 `vX.Y` 里程碑创建的 Git 分支 `release-X.Y`）。

发布过程可被认为具有三个主要阶段：

- 特性增强定义
- 实现
- 稳定

## 4.1. 发布周期

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

- [Kubernetes 1.24 正式发布，这里是更新功能总览](https://www.cnblogs.com/lizexiong/p/16223997.html)

- [design-proposals-archive/versioning.md at main · kubernetes/design-proposals-archive · GitHub](https://github.com/kubernetes/design-proposals-archive/blob/main/release/versioning.md#kubernetes-release-versioning)

- [Kubernetes 发布周期 | Kubernetes](https://kubernetes.io/zh-cn/releases/release/)


