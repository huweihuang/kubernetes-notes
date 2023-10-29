---
title: "kubeadm升级k8s集群"
weight: 2
catalog: true
date: 2023-8-15 16:22:24
subtitle:
header-img:
tags:
- kubeadm
catagories:
- kubeadm
---

本文主要说明如何使用`kubeadm`来升级k8s集群。

# 1. 版本注意事项

假设k8s的版本格式为`x.y.z`，那么使用kubeadm最多只能升级到`y+1`版本，或者是当前`y`版本的最新版本。例如你k8s集群的版本为`1.24.x`，那么你最大版本只能下载`1.25.x`的kubeadm来升级版本。

因此升级前需要执行以下命令来验证可升级的版本。

```bash
kubeadm upgrade plan
```

## 1.1. 版本跨度过大

如果出现以下报错，说明升级的版本跨度过大。

```bash
# kubeadm的版本为v1.26.7
./kubeadm version
kubeadm version: &version.Info{Major:"1", Minor:"26", GitVersion:"v1.26.7", GitCommit:"84e1fc493a47446df2e155e70fca768d2653a398", GitTreeState:"clean", BuildDate:"2023-07-19T12:22:13Z", GoVersion:"go1.20.6", Compiler:"gc", Platform:"linux/amd64"}

# 当前k8s集群版本1.24.2 版本跨度过大。
./kubeadm upgrade plan
[upgrade/config] Making sure the configuration is correct:
[upgrade/config] Reading configuration from the cluster...
[upgrade/config] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
[upgrade/config] FATAL: this version of kubeadm only supports deploying clusters with the control plane version >= 1.25.0. Current version: v1.24.2
To see the stack trace of this error execute with --v=5 or higher
```

## 1.2. 可升级的版本计划

可升级的版本计划如下

当前的k8s版本为`1.24.2`，可升级的版本是`1.24.16`或`1.25.12`，其中etcd升级的版本为`3.5.6-0`。

```bash
./kubeadm upgrade plan
[upgrade/config] Making sure the configuration is correct:
[upgrade/config] Reading configuration from the cluster...
[upgrade/config] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[preflight] Running pre-flight checks.
[upgrade] Running cluster health checks
[upgrade] Fetching available versions to upgrade to
[upgrade/versions] Cluster version: v1.24.2
[upgrade/versions] kubeadm version: v1.25.12
I0815 21:41:34.096199 2934255 version.go:256] remote version is much newer: v1.27.4; falling back to: stable-1.25
[upgrade/versions] Target version: v1.25.12
[upgrade/versions] Latest version in the v1.24 series: v1.24.16

Components that must be upgraded manually after you have upgraded the control plane with 'kubeadm upgrade apply':
COMPONENT   CURRENT       TARGET
kubelet     4 x v1.24.2   v1.24.16

Upgrade to the latest version in the v1.24 series:

COMPONENT                 CURRENT   TARGET
kube-apiserver            v1.24.2   v1.24.16
kube-controller-manager   v1.24.2   v1.24.16
kube-scheduler            v1.24.2   v1.24.16
kube-proxy                v1.24.2   v1.24.16
CoreDNS                   v1.8.6    v1.9.3
etcd                      3.5.3-0   3.5.6-0

You can now apply the upgrade by executing the following command:

    kubeadm upgrade apply v1.24.16

_____________________________________________________________________

Components that must be upgraded manually after you have upgraded the control plane with 'kubeadm upgrade apply':
COMPONENT   CURRENT       TARGET
kubelet     4 x v1.24.2   v1.25.12

Upgrade to the latest stable version:

COMPONENT                 CURRENT   TARGET
kube-apiserver            v1.24.2   v1.25.12
kube-controller-manager   v1.24.2   v1.25.12
kube-scheduler            v1.24.2   v1.25.12
kube-proxy                v1.24.2   v1.25.12
CoreDNS                   v1.8.6    v1.9.3
etcd                      3.5.3-0   3.5.6-0

You can now apply the upgrade by executing the following command:

    kubeadm upgrade apply v1.25.12

_____________________________________________________________________


The table below shows the current state of component configs as understood by this version of kubeadm.
Configs that have a "yes" mark in the "MANUAL UPGRADE REQUIRED" column require manual config upgrade or
resetting to kubeadm defaults before a successful upgrade can be performed. The version to manually
upgrade to is denoted in the "PREFERRED VERSION" column.

API GROUP                 CURRENT VERSION   PREFERRED VERSION   MANUAL UPGRADE REQUIRED
kubeproxy.config.k8s.io   v1alpha1          v1alpha1            no
kubelet.config.k8s.io     v1beta1           v1beta1             no
_____________________________________________________________________
```

# 2. 版本升级步骤

## 2.1. 准备工作

1. 下载指定版本的kubeadm二进制

2. 查看升级计划：kubeadm upgrade plan

## 2.2. 升级master节点

### 2.2.1. 升级第一个master节点

```bash
kubeadm upgrade apply v1.25.x -f
```

 升级结束会查看都以下输出：

```bash
[upgrade/successful] SUCCESS! Your cluster was upgraded to "v1.25.x". Enjoy!

[upgrade/kubelet] Now that your control plane is upgraded, please proceed with upgrading your kubelets if you haven't already done so.
```

### 2.2.2. 手动升级你的 CNI 驱动插件。

你的容器网络接口（CNI）驱动应该提供了程序自身的升级说明。 参阅[插件](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/addons/)页面查找你的 CNI 驱动， 并查看是否需要其他升级步骤。

如果 CNI 驱动作为 DaemonSet 运行，则在其他控制平面节点上不需要此步骤。

### 2.2.3. 升级其他master节点

下载指定版本的kubeadm组件。使用以下命令升级，注意区别于第一个master的升级命令。

```bash
kubeadm upgrade node
```

### 2.2.4. 升级master的kubelet组件

将节点标记为不可调度并驱逐所有负载，准备节点的维护：

```shell
# 将 <node-to-drain> 替换为你要腾空的控制面节点名称
kubectl drain <node-to-drain> --ignore-daemonsets
```

下载kubelet和kubectl

```shell
# 用最新的补丁版本替换 1.27.x-00 中的 x
apt-mark unhold kubelet kubectl && \
apt-get update && apt-get install -y kubelet=1.27.x-00 kubectl=1.27.x-00 && \
apt-mark hold kubelet kubectl
```

重启kubelet

```shell
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

解除节点保护

```shell
# 将 <node-to-uncordon> 替换为你的节点名称
kubectl uncordon <node-to-uncordon>
```

## 2.3. 升级worker节点

同 `2.2.4. 升级master的kubelet组件`的步骤，worker节点只需要升级kubelet。

# 3. 升级版本回滚

kubeadm升级过程中会把相关目录备份到`/etc/kubernetes/tmp`目录，备份内容如下：

```bash
tmp/
├── kubeadm-backup-etcd-2023-08-16-14-50-50
│   └── etcd
└── kubeadm-backup-manifests-2023-08-16-14-50-50
    ├── etcd.yaml
    ├── kube-apiserver.yaml
    ├── kube-controller-manager.yaml
    └── kube-scheduler.yaml
```

如果 `kubeadm upgrade` 失败并且没有回滚，例如由于执行期间节点意外关闭， 你可以再次运行 `kubeadm upgrade`。 此命令是幂等的，并最终确保实际状态是你声明的期望状态。

要从故障状态恢复，你还可以运行 `kubeadm upgrade apply --force` 而无需更改集群正在运行的版本。

在升级期间，kubeadm 向 `/etc/kubernetes/tmp` 目录下的如下备份文件夹写入数据：

- `kubeadm-backup-etcd-<date>-<time>`
- `kubeadm-backup-manifests-<date>-<time>`

`kubeadm-backup-etcd` 包含当前控制面节点本地 etcd 成员数据的备份。 如果 etcd 升级失败并且自动回滚也无法修复，则可以将此文件夹中的内容复制到 `/var/lib/etcd` 进行手工修复。如果使用的是外部的 etcd，则此备份文件夹为空。

`kubeadm-backup-manifests` 包含当前控制面节点的静态 Pod 清单文件的备份版本。 如果升级失败并且无法自动回滚，则此文件夹中的内容可以复制到 `/etc/kubernetes/manifests` 目录实现手工恢复。 如果由于某些原因，在升级前后某个组件的清单未发生变化，则 kubeadm 也不会为之生成备份版本。

# 4. 问题排查

在升级k8s 从1.25.12到1.26.7的过程中，遇到master节点的服务起不来，报错如下：

```bash
"CreatePodSandbox for pod failed" err="open /run/systemd/resolve/resolv.conf: no such file or directory" pod="kube-system/kube-apiserver"
```

现象主要是静态pod起不来，包括etcd等。

具体解决方法参考：[open /run/systemd/resolve/resolv.conf](https://ask.kubesphere.io/forum/d/6474-v321masterrunsystemdresolvconfworker/3)

```bash
# 查看以下的resolv.conf是否存在
cat /var/lib/kubelet/config.yaml | grep resolvConf
/run/systemd/resolve/resolv.conf

# 如果不存在，检查systemd-resolved是否正常运行，
systemctl status systemd-resolved

# 如果没有运行，则运行该服务
systemctl start systemd-resolved

# 或者新建文件/run/systemd/resolve/resolv.conf，并将其他master的文件拷贝过来。
```





参考：

- [升级 kubeadm 集群 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [升级 Linux 节点 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/)
- [安装扩展（Addon） | Kubernetes](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/addons/)
