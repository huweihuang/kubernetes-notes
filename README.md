# Kubernetes 学习笔记

> 本系列是 [Kubernetes 学习笔记](https://www.huweihuang.com/kubernetes-notes/)
> 
> 更多的学习笔记请参考：
> 
> - [Kubernetes 学习笔记](https://www.huweihuang.com/kubernetes-notes/)
> - [Kubernetes 源码分析笔记](https://www.huweihuang.com/k8s-source-code-analysis/)
> - [Docker 学习笔记](https://www.huweihuang.com/docker-notes/)
> - [Golang 学习笔记](https://www.huweihuang.com/golang-notes/)
> - [Linux 学习笔记](https://www.huweihuang.com/linux-notes/)
> - [数据结构学习笔记](https://www.huweihuang.com/data-structure-notes/)
> 
> 个人博客：
> - [www.huweihuang.com](https://www.huweihuang.com/)
> - [blog.huweihuang.com](https://blog.huweihuang.com/)
> - [k8s.huweihuang.com](https://k8s.huweihuang.com/)

# 微信公众号

微信公众号：容器云架构

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1551600382/blog/wechat-public-acconut.jpg" width="35%">

---

## 云原生体系 <a id="paas"></a>

- [12-Factor](paas/12-factor.md)
- [K8S知识体系](paas/k8s.md)

## 安装与配置 <a id="setup"></a>

- [部署k8s集群](setup/installer/_index.md)
  - [使用kubeadm安装生产环境kubernetes](setup/installer/install-k8s-by-kubeadm.md)
  - [使用kubespray安装kubernetes](setup/installer/install-k8s-by-kubespray.md)
  - [使用minikube安装kubernetes](setup/installer/install-k8s-by-minikube.md)
  - [使用kind安装kubernetes](setup/installer/install-k8s-by-kind.md)
- [k8s证书及秘钥](setup/k8s-cert.md)
- [k8s版本说明](setup/k8s-version-release.md)

## 基本概念 <a id="concepts"></a>

- [kubernetes架构](concepts/architecture/_index.md)
  - [Kubernetes总架构图](concepts/architecture/kubernetes-architecture.md)
  - [基于Docker及Kubernetes技术构建容器云（PaaS）平台概述](concepts/architecture/paas-based-on-docker-and-kubernetes.md)
- [kubernetes对象](concepts/object/_index.md)
  - [理解kubernetes对象](concepts/object/understanding-kubernetes-objects.md)
  - [kubernetes常用对象说明](concepts/object/kubernetes-basic-concepts.md)
- [Pod](concepts/pod/_index.md)
  - [Pod介绍](concepts/pod/pod.md)
  - [Pod定义文件](concepts/pod/pod-definition.md)
  - [Pod生命周期](concepts/pod/pod-lifecycle.md)
  - [Pod健康检查](concepts/pod/pod-probe.md)
  - [Pod存储卷](concepts/pod/pod-volume.md)
  - [Pod控制器](concepts/pod/pod-scheduler.md)
  - [Pod伸缩与升级](concepts/pod/pod-operation.md)
- [配置](concepts/configmap/_index.md)
  - [ConfigMap](concepts/configmap/pod-configmap.md)
- [Workload](concepts/_index.md)

## 核心原理 <a id="principle"></a>

- [核心组件](principle/component/_index.md)
  - [Api Server](principle/component/kubernetes-core-principle-api-server.md)
  - [Controller Manager](principle/component/kubernetes-core-principle-controller-manager.md)
  - [Scheduler](principle/component/kubernetes-core-principle-scheduler.md)
  - [Kubelet](principle/component/kubernetes-core-principle-kubelet.md)
- [流程图](principle/flow/_index.md)
  - [Pod创建流程](principle/flow/pod-flow.md)
  - [PVC创建流程](principle/flow/pvc-flow.md)

## 容器网络 <a id="network"></a>

- [Docker网络](network/docker-network.md)
- [K8S网络](network/kubernetes-network.md)
- [Pod的DNS策略](network/pod-dns.md)
- [网络插件](network/flannel/_index.md)
  - [Flannel介绍](network/flannel/flannel-introduction.md)
- [CNI](network/cni/_index.md)
  - [CNI接口介绍](network/cni/cni.md)
  - [Macvlan介绍](network/cni/macvlan.md)

## 容器存储 <a id="storage"></a>

- [存储卷概念](storage/volume/_index.md)
  - [Volume](storage/volume/volume.md)
  - [Persistent Volume](storage/volume/persistent-volume.md)
  - [Persistent Volume Claim](storage/volume/persistent-volume-claim.md)
  - [Storage Class](storage/volume/storage-class.md)
  - [Dynamic Volume Provisioning](storage/volume/dynamic-provisioning.md)
- [CSI](storage/csi/_index.md)
  - [csi-cephfs-plugin](storage/csi/ceph/csi-cephfs-plugin.md)
  - [部署csi-cephfs](storage/csi/ceph/deploy-csi-cephfs.md)
  - [部署cephfs-provisioner](storage/csi/provisioner/cephfs-provisioner.md)
  - [FlexVolume介绍](storage/csi/flexvolume.md)

## 资源隔离 <a id="resource"></a>

- [资源配额](resource/resource-quota.md)
- [Pod限额](resource/limit-range.md)
- [资源服务质量](resource/quality-of-service.md)
- [Lxcfs资源视图隔离](resource/lxcfs/lxcfs.md)

## 运维指南 <a id="operation"></a>

- [kubectl工具](operation/kubectl/_index.md)
  - [kubectl安装与配置](operation/kubectl/install-kubectl.md)
  - [kubectl命令说明](operation/kubectl/kubectl-commands.md)
  - [kubectl命令别名](operation/kubectl/kubectl-alias.md)
  - [kubectl进入node shell](operation/kubectl/kubectl-node-shell.md)
  - [helm的使用](operation/kubectl/helm-usage.md)
- [kubernetes集群问题排查](operation/kubernetes-troubleshooting.md)
- [节点调度](operation/node/_index.md)
  - [安全迁移节点](operation/node/safely-drain-node.md)
  - [指定Node调度与隔离](operation/node/nodeselector-and-taint.md)
- [镜像仓库配置](operation/registry/_index.md)
  - [配置私有的镜像仓库](operation/registry/config-private-registry.md)
  - [拉取私有镜像](operation/registry/ImagePullSecrets.md)

## 开发指南 <a id="develop"></a>

- [client-go的使用及源码分析](develop/client-go.md)
- [CSI插件开发](develop/csi/_index.md)
  - [nfs-client-provisioner源码分析](develop/csi/nfs-client-provisioner.md)
  - [csi-provisioner源码分析](develop/csi/csi-provisioner.md)
- [operator开发](develop/operator/_index.md)
  - [kubebuilder的使用](develop/operator/kubebuilder.md)

## 问题排查 <a id="trouble-shooting"></a>

- [节点相关问题](trouble-shooting/node/_index.md)
  - [keycreate permission denied](trouble-shooting/node/keycreate-permission-denied.md)
  - [Cgroup不支持pid资源](trouble-shooting/node/cgroup-pid-error.md)
  - [Cgroup子系统无法挂载](trouble-shooting/node/cgroup-subsystem-not-mount.md)
- [Pod驱逐](trouble-shooting/pod-evicted.md)
- [镜像拉取失败问题](trouble-shooting/pod-image-error.md)
- [PVC Terminating](trouble-shooting/pvc-terminating.md)

----

## 源码分析 <a id="code-analysis"></a>

- [Kubernetes源码分析笔记](code-analysis/code-analysis-notes.md)
- [kubelet](code-analysis/kubelet/_index.md)
  - [NewKubeletCommand](code-analysis/kubelet/NewKubeletCommand.md)
  - [NewMainKubelet](code-analysis/kubelet/NewMainKubelet.md)
  - [startKubelet](code-analysis/kubelet/startKubelet.md)
  - [syncLoopIteration](code-analysis/kubelet/syncLoopIteration.md)
  - [syncPod](code-analysis/kubelet/syncPod.md)
- [kube-controller-manager](code-analysis/kube-controller-manager/_index.md)
  - [NewControllerManagerCommand](code-analysis/kube-controller-manager/NewControllerManagerCommand.md)
  - [DeploymentController](code-analysis/kube-controller-manager/deployment-controller.md)
  - [Informer机制](code-analysis/kube-controller-manager/sharedIndexInformer.md)
- [kube-scheduler](code-analysis/kube-scheduler/_index.md)
  - [NewSchedulerCommand](code-analysis/kube-scheduler/NewSchedulerCommand.md)
  - [registerAlgorithmProvider](code-analysis/kube-scheduler/registerAlgorithmProvider.md)
  - [scheduleOne](code-analysis/kube-scheduler/scheduleOne.md)
  - [findNodesThatFit](code-analysis/kube-scheduler/findNodesThatFit.md)
  - [PrioritizeNodes](code-analysis/kube-scheduler/PrioritizeNodes.md)
  - [preempt](code-analysis/kube-scheduler/preempt.md)
- [kube-apiserver](code-analysis/kube-apiserver/_index.md)
  - [NewAPIServerCommand](code-analysis/kube-apiserver/NewAPIServerCommand.md)

----

## Runtime <a id="runtime"></a>

- [Runtime](runtime/_index.md)
  - [Runc和Containerd概述](runtime/runtime.md)
- [Containerd](runtime/containerd/_index.md)
  - [安装Containerd](runtime/containerd/install-containerd.md)
- [Docker](runtime/docker/_index.md)
  - [Docker学习笔记](runtime/docker/docker-notes.md)
- [Kata Container](runtime/kata/_index.md)
  - [kata容器简介](runtime/kata/kata-container.md)
  - [kata配置](runtime/kata/kata-container-conf.md)
- [GPU](runtime/gpu/_index.md)
  - [nvidia-device-plugin介绍](runtime/gpu/nvidia-device-plugin.md)

## Etcd <a id="etcd"></a>

- [Etcd介绍](etcd/etcd-introduction.md)
- [Raft算法](etcd/raft.md)
- [Etcd启动配置参数](etcd/etcd-setup-flags.md)
- [Etcd访问控制](etcd/etcd-auth-and-security.md)
- [etcdctl命令工具](etcd/etcdctl/_index.md)
  - [etcdctl命令工具-V3](etcd/etcdctl/etcdctl-v3.md)
  - [etcdctl命令工具-V2](etcd/etcdctl/etcdctl-v2.md)
- [Etcd中的k8s数据](etcd/k8s-etcd-data.md)
- [Etcd-Operator的使用](etcd/etcd-operator-usage.md)

## 多集群管理 <a id="multi-cluster"></a>

- [k8s多集群管理的思考](multi-cluster/k8s-multi-cluster-thinking.md)
- [Virtual Kubelet](multi-cluster/virtual-kubelet/_index.md)
  - [Virtual Kubelet介绍](multi-cluster/virtual-kubelet/virtual-kubelet.md)
  - [Virtual Kubelet 命令](multi-cluster/virtual-kubelet/virtual-kubelet-cmd.md)
- [Karmada](multi-cluster/karmada/_index.md)
  - [Karmada介绍](multi-cluster/karmada/karmada-introduction.md)

## 边缘容器 <a id="kubeedge"></a>

- [KubeEdge介绍](edge/kubeedge/kubeedge-arch.md)
- [KubeEdge源码分析](edge/kubeedge/code-analysis/_index.md)
  - [cloudcore](edge/kubeedge/code-analysis/cloudcore.md)
  - [edgecore](edge/kubeedge/code-analysis/edgecore.md)
- [OpenYurt](edge/openyurt/_index.md)
  - [OpenYurt部署](edge/openyurt/install-openyurt.md)
  - [OpenYurt部署之调整k8s配置](edge/openyurt/update-k8s-for-openyurt.md)  


## 虚拟化 <a id="kvm"></a>

- [虚拟化相关概念](kvm/vm-concept.md)
- [KubeVirt](kvm/kubevirt/_index.md)
  - [KubeVirt的介绍](kvm/kubevirt/kubevirt-introduction.md)
  - [KubeVirt的使用](kvm/kubevirt/kubevirt-installation.md)

## 监控体系 <a id="monitor"></a>

- [监控体系介绍](monitor/kubernetes-cluster-monitoring.md)
- [cAdvisor介绍](monitor/cadvisor-introduction.md)
- [Heapster介绍](monitor/heapster-introduction.md)
- [Influxdb介绍](monitor/influxdb-introduction.md)


---

# 赞赏

> 如果觉得文章有帮助的话，可以打赏一下，谢谢！

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1551599963/blog/donate.jpg" width="70%"/>
