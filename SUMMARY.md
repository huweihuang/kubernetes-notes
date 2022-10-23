# Summary

## 目录 <a id="introduction"></a>

- [序言](README.md)

## 云原生体系 <a id="paas"></a>

- [12-Factor](paas/12-factor.md)
- [K8S知识体系](paas/k8s.md)

## 安装与配置 <a id="setup"></a>

- [部署k8s集群](setup/installer/README.md)
  - [使用kubeadm安装生产环境kubernetes](setup/installer/install-k8s-by-kubeadm.md)
  - [使用kubespray安装kubernetes](setup/installer/install-k8s-by-kubespray.md)
  - [使用minikube安装kubernetes](setup/installer/install-k8s-by-minikube.md)
  - [使用kind安装kubernetes](setup/installer/install-k8s-by-kind.md)
- [k8s证书及秘钥](setup/k8s-cert.md)
- [k8s版本说明](setup/k8s-version-release.md)

## 基本概念 <a id="concepts"></a>

- [kubernetes架构](concepts/architecture/README.md)
  - [Kubernetes总架构图](concepts/architecture/kubernetes-architecture.md)
  - [基于Docker及Kubernetes技术构建容器云（PaaS）平台概述](concepts/architecture/paas-based-on-docker-and-kubernetes.md)
- [kubernetes对象](concepts/object/README.md)
  - [理解kubernetes对象](concepts/object/understanding-kubernetes-objects.md)
  - [kubernetes常用对象说明](concepts/object/kubernetes-basic-concepts.md)
- [Pod](concepts/pod/README.md)
  - [Pod介绍](concepts/pod/pod.md)
  - [Pod定义文件](concepts/pod/pod-definition.md)
  - [Pod生命周期](concepts/pod/pod-lifecycle.md)
  - [Pod健康检查](concepts/pod/pod-probe.md)
  - [Pod存储卷](concepts/pod/pod-volume.md)
  - [Pod控制器](concepts/pod/pod-scheduler.md)
  - [Pod伸缩与升级](concepts/pod/pod-operation.md)
- [配置](concepts/configmap/README.md)
  - [ConfigMap](concepts/configmap/pod-configmap.md)
- [Workload](concepts/README.md)

## 核心原理 <a id="principle"></a>

- [核心组件](principle/README.md)
  - [Api Server](principle/kubernetes-core-principle-api-server.md)
  - [Controller Manager](principle/kubernetes-core-principle-controller-manager.md)
  - [Scheduler](principle/kubernetes-core-principle-scheduler.md)
  - [Kubelet](principle/kubernetes-core-principle-kubelet.md)
- [流程图](principle/flow/README.md)
  - [Pod创建流程](principle/flow/pod-flow.md)
  - [PVC创建流程](principle/flow/pvc-flow.md)

## 容器网络 <a id="network"></a>

- [Docker网络](network/docker-network.md)
- [K8S网络](network/kubernetes-network.md)
- [网络插件](network/flannel/README.md)
  - [Flannel介绍](network/flannel/flannel-introduction.md)
- [CNI](network/cni/README.md)
  - [CNI接口介绍](network/cni/cni.md)
  - [Macvlan介绍](network/cni/macvlan.md)

## 容器存储 <a id="storage"></a>

- [存储卷概念](storage/volume/README.md)
  - [Volume](storage/volume/volume.md)
  - [Persistent Volume](storage/volume/persistent-volume.md)
  - [Persistent Volume Claim](storage/volume/persistent-volume-claim.md)
  - [Storage Class](storage/volume/storage-class.md)
  - [Dynamic Volume Provisioning](storage/volume/dynamic-provisioning.md)
- [CSI](storage/csi/README.md)
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

- [kubectl工具](operation/kubectl/README.md)
  - [kubectl安装与配置](operation/kubectl/install-kubectl.md)
  - [kubectl命令说明](operation/kubectl/kubectl-commands.md)
  - [kubectl命令别名](operation/kubectl/kubectl-alias.md)
- [kubernetes集群问题排查](operation/kubernetes-troubleshooting.md)
- [节点调度](operation/node/README.md)
  - [安全迁移节点](operation/node/safely-drain-node.md)
  - [指定Node调度与隔离](operation/node/nodeselector-and-taint.md)
- [镜像仓库配置](operation/registry/README.md)
  - [配置私有的镜像仓库](operation/registry/config-private-registry.md)
  - [拉取私有镜像](operation/registry/ImagePullSecrets.md)

## 开发指南 <a id="develop"></a>

- [client-go的使用及源码分析](develop/client-go.md)
- [CSI插件开发](develop/README.md)
  - [nfs-client-provisioner源码分析](develop/nfs-client-provisioner.md)
  - [csi-provisioner源码分析](develop/csi-provisioner.md)
- [operator开发](develop/operator/README.md)
  - [kubebuilder的使用](develop/operator/kubebuilder.md)

## 问题排查 <a id="trouble-shooting"></a>

- [节点相关问题](trouble-shooting/node/README.md)
  - [keycreate permission denied](trouble-shooting/node/keycreate-permission-denied.md)
  - [Cgroup不支持pid资源](trouble-shooting/node/cgroup-pid-error.md)
  - [Cgroup子系统无法挂载](trouble-shooting/node/cgroup-subsystem-not-mount.md)
- [Pod驱逐](trouble-shooting/pod-evicted.md)
- [镜像拉取失败问题](trouble-shooting/pod-image-error.md)
- [PVC Terminating](trouble-shooting/pvc-terminating.md)

----

## 源码分析 <a id="code-analysis"></a>

- [Kubernetes源码分析笔记](code-analysis/code-analysis-notes.md)
- [kubelet](code-analysis/kubelet/README.md)
  - [NewKubeletCommand](code-analysis/kubelet/NewKubeletCommand.md)
  - [NewMainKubelet](code-analysis/kubelet/NewMainKubelet.md)
  - [startKubelet](code-analysis/kubelet/startKubelet.md)
  - [syncLoopIteration](code-analysis/kubelet/syncLoopIteration.md)
  - [syncPod](code-analysis/kubelet/syncPod.md)
- [kube-controller-manager](code-analysis/kube-controller-manager/README.md)
  - [NewControllerManagerCommand](code-analysis/kube-controller-manager/NewControllerManagerCommand.md)
  - [DeploymentController](code-analysis/kube-controller-manager/deployment-controller.md)
  - [Informer机制](code-analysis/kube-controller-manager/sharedIndexInformer.md)
- [kube-scheduler](code-analysis/kube-scheduler/README.md)
  - [NewSchedulerCommand](code-analysis/kube-scheduler/NewSchedulerCommand.md)
  - [registerAlgorithmProvider](code-analysis/kube-scheduler/registerAlgorithmProvider.md)
  - [scheduleOne](code-analysis/kube-scheduler/scheduleOne.md)
  - [findNodesThatFit](code-analysis/kube-scheduler/findNodesThatFit.md)
  - [PrioritizeNodes](code-analysis/kube-scheduler/PrioritizeNodes.md)
  - [preempt](code-analysis/kube-scheduler/preempt.md)
- [kube-apiserver](code-analysis/kube-apiserver/README.md)
  - [NewAPIServerCommand](code-analysis/kube-apiserver/NewAPIServerCommand.md)

----

## Runtime <a id="runtime"></a>

- [Runtime](runtime/README.md)
  - [Runc和Containerd概述](runtime/runtime.md)
- [Containerd](runtime/containerd/README.md)
  - [安装Containerd](runtime/containerd/install-containerd.md)
- [Docker](runtime/docker/README.md)
  - [Docker学习笔记](runtime/docker/docker-notes.md)
- [Kata Container](runtime/kata/README.md)
  - [kata容器简介](runtime/kata/kata-container.md)
  - [kata配置](runtime/kata/kata-container-conf.md)
- [GPU](runtime/gpu/README.md)
  - [nvidia-device-plugin介绍](runtime/gpu/nvidia-device-plugin.md)

## Etcd <a id="etcd"></a>

- [Etcd介绍](etcd/etcd-introduction.md)
- [Raft算法](etcd/raft.md)
- [Etcd启动配置参数](etcd/etcd-setup-flags.md)
- [Etcd访问控制](etcd/etcd-auth-and-security.md)
- [etcdctl命令工具](etcd/etcdctl/README.md)
  - [etcdctl命令工具-V3](etcd/etcdctl/etcdctl-v3.md)
  - [etcdctl命令工具-V2](etcd/etcdctl/etcdctl-v2.md)
- [Etcd中的k8s数据](etcd/k8s-etcd-data.md)
- [Etcd-Operator的使用](etcd/etcd-operator-usage.md)

## 多集群管理 <a id="multi-cluster"></a>

- [k8s多集群管理的思考](multi-cluster/k8s-multi-cluster-thinking.md)
- [Virtual Kubelet](multi-cluster/virtual-kubelet/README.md)
  - [Virtual Kubelet介绍](multi-cluster/virtual-kubelet/virtual-kubelet.md)
  - [Virtual Kubelet 命令](multi-cluster/virtual-kubelet/virtual-kubelet-cmd.md)
- [Karmada](multi-cluster/karmada/README.md)
  - [Karmada介绍](multi-cluster/karmada/karmada-introduction.md)

## 边缘容器 <a id="kubeedge"></a>

- [KubeEdge介绍](edge/kubeedge/kubeedge-arch.md)
- [KubeEdge源码分析](edge/kubeedge/code-analysis/README.md)
  - [cloudcore](edge/kubeedge/code-analysis/cloudcore.md)
  - [edgecore](edge/kubeedge/code-analysis/edgecore.md)
- [OpenYurt部署](edge/openyurt/install-openyurt.md)  

## 虚拟化 <a id="kvm"></a>

- [虚拟化相关概念](kvm/vm-concept.md)
- [KubeVirt](kvm/kubevirt/README.md)
  - [KubeVirt的介绍](kvm/kubevirt/kubevirt-introduction.md)
  - [KubeVirt的使用](kvm/kubevirt/kubevirt-installation.md)

## 监控体系 <a id="monitor"></a>

- [监控体系介绍](monitor/kubernetes-cluster-monitoring.md)
- [cAdvisor介绍](monitor/cadvisor-introduction.md)
- [Heapster介绍](monitor/heapster-introduction.md)
- [Influxdb介绍](monitor/influxdb-introduction.md)
