---
title: "k8s版本记录"
weight: 6
catalog: true
date: 2023-8-2 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1.27

参考：

- [Kubernetes 在 v1.27 中移除的特性和主要变更](https://kubernetes.io/zh-cn/blog/2023/03/17/upcoming-changes-in-kubernetes-v1-27/)

- https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.27.md#changelog-since-v1260

- [202304 | K8s 1.27 正式发布 - DaoCloud Enterprise](https://docs.daocloud.io/blogs/230412-k8s-1.27/)

## （一）重要更新

### k8s.gcr.io 重定向到 registry.k8s.io 相关说明

 Kubernetes 项目为了托管其容器镜像，使用社区拥有的一个名为 registry.k8s.io. 的镜像仓库。从 3 月 20 日起，所有来自过期 [k8s.gcr.io](https://cloud.google.com/container-registry/) 仓库的流量将被重定向到 [registry.k8s.io](https://github.com/kubernetes/registry.k8s.io)。 已弃用的 k8s.gcr.io 仓库最终将被淘汰。Kubernetes v1.27 版本不会发布到旧的仓库。

### 原地调整 Pod 资源 (alpha)

参考：[Kubernetes 1.27: 原地调整 Pod 资源 (alpha) | Kubernetes](https://kubernetes.io/zh-cn/blog/2023/05/12/in-place-pod-resize-alpha/)

在 Kubernetes v1.27 中，添加了一个新的 alpha 特性，允许用户调整分配给 Pod 的 CPU 和内存资源大小，而无需重新启动容器。 首先，API 层面现在允许修改 Pod 容器中的 `resources` 字段下的 `cpu` 和 `memory` 资源。资源修改只需 patch 正在运行的 pod 规约即可。

### StatefulSet PVC 自动删除功能特性 Beta

在 v1.23 中引入的 **StatefulSetAutoDeletePVC 功能将在 1.27 版本中升级为 Beta，并默认开启。** 然而，默认开启并不意味着所有 StatefulSet 的 PVC 都将自动删除。

### 优化大型集群中 kube-proxy 的 iptables 模式性能

**功能 MinimizeIPTablesRestore** 在 1.26 版本中引入，并在 1.27 版本中升级为 Beta 并默认启用。 该功能旨在改善大型集群中 kube-proxy 的 iptables 模式性能。

如果您遇到 Service 信息未正确同步到 iptables 的问题，您可以通过将 kube-proxy 启动参数设置为 `--feature-gates=MinimizeIPTablesRestore=false` 来禁用该功能（并向社区提交问题）。 您还可以查看 kube-proxy 的 metrics 信息中的 sync_proxy_rules_iptables_partial_restore_failures_total 指标来监控规则同步失败的次数。

### Kubelet 事件驱动 PLEG 升级为 Beta

**在节点 Pod 较多的情况下，通过容器运行时的 Event 驱动 Pod 状态更新，能够有效地提升效率。** 在 1.27 中，该功能已经达到了 Beta 条件，基础的 E2E 测试任务已经添加。 之所以默认关闭该功能，是因为社区认为该功能还需要补充以下验证：压力测试、恢复测试和带退避逻辑的重试。

### Pod 调度就绪态功能增强

**调度就绪态功能 PodSchedulingReadiness**，在 v1.26 作为 Alpha 功能引入，**从 v1.27 开始该功能升级为 Beta，默认开启。**

### Deployment 滚动更新过程中的调度优化

**在 v1.27 中，PodTopologySpread 调度策略可以区分调度 Pod 标签的值** （这里通常指 Pod 的 pod-template-hash 标签，不同 replica set 对应的 Pod 该标签的值不同）， 这样滚动更新后，**新的 Pod 实例会被调度得更加均匀** 。

### 关于加快 Pod 启动的进展

要启用并行镜像拉取，请在 kubelet 配置中将 `serializeImagePulls` 字段设置为 false。 当 `serializeImagePulls` 被禁用时，将立即向镜像服务发送镜像拉取请求，并可以并行拉取多个镜像。

为了在节点上具有多个 Pod 的场景中加快 Pod 启动，特别是在突然扩缩的情况下， kubelet 需要同步 Pod 状态并准备 ConfigMap、Secret 或卷。这就需要大带宽访问 kube-apiserver。在 v1.27 中，kubelet 为了提高 Pod 启动性能，将这些默认值分别提高到了 50 和 100。

## （二）弃用变更

- kubelet 移除了命令行参数 --container-runtime。

- 弃用的命令行参数 `--pod-eviction-timeout` 将被从 kube-controller-manager 中移除。

# 1.26

参考：

- [Kubernetes 1.26 中的移除、弃用和主要变更 | Kubernetes](https://kubernetes.io/zh-cn/blog/2022/11/18/upcoming-changes-in-kubernetes-1-26/)

- https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.26.md#changelog-since-v1250

- https://docs.daocloud.io/blogs/221209-k8s-1.26/

- https://www.alibabacloud.com/help/zh/ack/product-overview/kubernetes-1-26-release-notes?spm=a2c63.p38356.0.0.64624df9xXfEkZ

## （一）重要更新

### Kubelet Evented PLEG for Better Performance

该功能让 kubelet 在跟踪节点中 Pod 状态时，通过尽可能依赖容器运行时接口(CRI) 的通知来减少定期轮训，这会减少 kubelet 对 CPU 的使用

**新增 Alpha Feature Gate** —— EventedPLEG 来控制是否开启该功能。

### 优化 kube-proxy 性能，它只发送在调用 iptables-restore 中更改的规则，而不是整个规则集

### [PR#112200](https://github.com/kubernetes/kubernetes/pull/112200) client-go 的 SharedInformerFactory 增加 Shutdown 方法，来等待 Factory 内所有运行的 informer 都结束。

## （二）弃用变更

- Kubelet 不再支持 v1alpha2 版本的 CRI，接入的容器运行时必须实现 v1 版本的容器运行时接口。

Kubernetes v1.26 将不支持 containerd 1.5.x 及更早的版本；需要升级到 containerd 1.6.x 或更高版本后，才能将该节点的 kubelet 升级到 1.26。

# 1.25

参考：

- https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.25.md#whats-new-major-themes

- [Kubernetes 1.25 的移除说明和主要变更 | Kubernetes](https://kubernetes.io/zh-cn/blog/2022/08/04/upcoming-changes-in-kubernetes-1-25/)

## （一）重要更新

### cgroup v2 升级到 GA

Kubernetes 1.25 将 cgroup v2 正式发布（GA）， 让kubelet使用最新的容器资源管理能力。一些 Kubernetes 特性专门使用 cgroup v2 来增强资源管理和隔离。 例如，[MemoryQoS 特性](https://kubernetes.io/blog/2021/11/26/qos-memory-resources/)提高了内存利用率并依赖 cgroup v2 功能来启用它。kubelet 中的新资源管理特性也将利用新的 cgroup v2 特性向前发展。

### CSI 内联存储卷正式发布GA

CSI 内联存储卷与其他类型的临时卷相似，如 `configMap`、`downwardAPI` 和 `secret`。 重要的区别是，存储是由 CSI 驱动提供的，它允许使用第三方供应商提供的临时存储。 卷被定义为 Pod 规约的一部分，并遵循 Pod 的生命周期，这意味着卷随着 Pod 的调度而创建，并随着 Pod 的销毁而销毁。

### Ephemeral Containers进入稳定版本

当pod crash的时候，无法通过kubectl exec 进入容器，这个时候可以通过临时容器[Ephemeral Containers]([临时容器 | Kubernetes](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/ephemeral-containers/))

## （二）弃用变更

- Kubernetes v1.25 将移除 PodSecurityPolicy，取而代之的是 Pod Security Admission（即 PodSecurity 安全准入控制器）。

- [清理 IPTables 链的所有权](https://github.com/kubernetes/enhancements/issues/3178) 
  
  -  从 v1.25 开始，Kubelet 将逐渐迁移为不在 `nat` 表中创建以下 iptables 链：
    
    - `KUBE-MARK-DROP`
    - `KUBE-MARK-MASQ`
    - `KUBE-POSTROUTING`

# 1.24

最新发行版本：1.24.2 (发布日期: 2022-06-15）

不再支持：2023-09-29

**补丁版本：** [1.24.1](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.24.md#v1241)、 [1.24.2](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.24.md#v1242)

Complete 1.24 [Schedule](https://kubernetes.io/releases/patch-releases/#1-24) and [Changelog](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.24.md)

Kubernetes 1.24 使用 **go1.18**构建，默认情况下将不再验证使用 SHA-1 哈希算法签名的证书。

## （一）重要更新

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

## （二）弃用变更

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

# 1.23

最新发行版本：1.23.8 (发布日期: 2022-06-15）

不再支持：2023-02-28

**补丁版本：** [1.23.1](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1231)、 [1.23.2](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1232)、 [1.23.3](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1233)、 [1.23.4](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1234)、 [1.23.5](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1235)、 [1.23.6](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1236)、 [1.23.7](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1237)、 [1.23.8](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md#v1238)

Complete 1.23 [Schedule](https://kubernetes.io/releases/patch-releases/#1-23) and [Changelog](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.23.md)

Kubernetes 是使用 **golang 1.17** 构建的。此版本的 go 删除了使用 GODEBUG=x509ignoreCN=0 环境设置来重新启用将 X.509 服务证书的 CommonName 视为主机名的已弃用旧行为的能力。

## （一） 重要更新

### 1）FlexVolume 已弃用

FlexVolume 已弃用。 Out-of-tree CSI 驱动程序是在 Kubernetes 中编写卷驱动程序的推荐方式。FlexVolume 驱动程序的维护者应实施 CSI 驱动程序并将 FlexVolume 的用户转移到 CSI。 FlexVolume 的用户应将其工作负载转移到 CSI 驱动程序。

### 2）IPv4/IPv6 双栈网络到 GA

IPv4/IPv6 双栈网络从 GA 毕业。从 1.21 开始，Kubernetes 集群默认启用支持双栈网络。在 1.23 中，移除了 IPv6DualStack 功能门。双栈网络的使用不是强制性的。尽管启用了集群以支持双栈网络，但 Pod 和服务继续默认为单栈。要使用双栈网络：Kubernetes 节点具有可路由的 IPv4/IPv6 网络接口，使用支持双栈的 CNI 网络插件，Pod 配置为双栈，服务的 .spec.ipFamilyPolicy 字段设置为 PreferDualStack 或需要双栈。

### 3）Horizo​​ntalPodAutoscaler v2 到 GA

Horizo​​ntalPodAutoscaler API 的第 2 版在 1.23 版本中逐渐稳定。 Horizo​​ntalPodAutoscaler autoscaling/v2beta2 API 已弃用，取而代之的是新的 autoscaling/v2 API，Kubernetes 项目建议将其用于所有用例。

### 4）Scheduler简化多点插件配置

kube-scheduler 正在为插件添加一个新的、简化的配置字段，以允许在一个位置启用多个扩展点。新的 multiPoint 插件字段旨在为管理员简化大多数调度程序设置。通过 multiPoint 启用的插件将自动为它们实现的每个单独的扩展点注册。例如，实现 Score 和 Filter 扩展的插件可以同时为两者启用。这意味着可以启用和禁用整个插件，而无需手动编辑单个扩展点设置。这些扩展点现在可以被抽象出来，因为它们与大多数用户无关。

## （二）已知问题

在 1.22 Kubernetes 版本附带的 **etcd v3.5.0 版本中发现了数据损坏问题**。请阅读 etcd 的最新[生产建议]([etcd/CHANGELOG at main · etcd-io/etcd · GitHub](https://github.com/etcd-io/etcd/tree/main/CHANGELOG))。

运行etcd v3.5.2 v3.5.1和v3.5.0高负荷会导致数据损坏问题。如果etcd进程被杀,偶尔有些已提交的事务并不反映在所有的成员。建议升级到**v3.5.3**。

**最低推荐etcd版本运行在生产3.3.18 + 3.4.2 + v3.5.3 +。**

# 1.22

最新发行版本：1.22.11 (发布日期: 2022-06-15）

不再支持：2022-10-28

**补丁版本：** [1.22.1](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1221)、 [1.22.2](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1222)、 [1.22.3](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1223)、 [1.22.4](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1224)、 [1.22.5](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1225)、 [1.22.6](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1226)、 [1.22.7](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1227)、 [1.22.8](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1228)、 [1.22.9](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v1229)、 [1.22.10](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v12210)、 [1.22.11](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md#v12211)

Complete 1.22 [Schedule](https://kubernetes.io/releases/patch-releases/#1-22) and [Changelog](https://git.k8s.io/kubernetes/CHANGELOG/CHANGELOG-1.22.md)

## （—）重要更新

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

参考：

- [发行版本 | Kubernetes](https://kubernetes.io/zh-cn/releases/)

- [kubernetes/CHANGELOG at master · GitHub](https://github.com/kubernetes/kubernetes/tree/master/CHANGELOG)

- [sig-release/releases at master · kubernetes/sig-release · GitHub](https://github.com/kubernetes/sig-release/tree/master/releases)

- [Kubernetes 1.24 正式发布，这里是更新功能总览](https://www.cnblogs.com/lizexiong/p/16223997.html)
