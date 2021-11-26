# Kubernetes 学习笔记

> 本系列是 [Kubernetes 学习笔记](https://www.huweihuang.com/kubernetes-notes/)
> 
> 更多的学习笔记请参考：
> - [Kubernetes 学习笔记](https://www.huweihuang.com/kubernetes-notes/)
> - [Kubernetes 源码分析笔记](https://www.huweihuang.com/k8s-source-code-analysis/)
> - [Docker 学习笔记](https://www.huweihuang.com/docker-notes/)
> - [Golang 学习笔记](https://www.huweihuang.com/golang-notes/)
> - [Linux 学习笔记](https://www.huweihuang.com/linux-notes/)
> - [数据结构学习笔记](https://www.huweihuang.com/data-structure-notes/)
>
> 个人博客：[www.huweihuang.com](https://www.huweihuang.com/)

---


## 目录

* [目录](README.md)

## 云原生体系

* [12-Factor](paas/12-factor.md)
* [k8s知识体系](paas/k8s.md)
  
## 安装与配置

* [使用kubespray安装kubernetes](setup/install-k8s-by-kubespray.md)
* [使用minikube安装kubernetes](setup/install-k8s-by-minikube.md)
* [使用kind安装kubernetes](setup/install-k8s-by-kind.md)
* [k8s证书及秘钥](setup/k8s-cert.md)

## 基本概念

* [kubernetes架构]()
    * [Kubernetes总架构图](concepts/architecture/kubernetes-architecture.md)
    * [基于Docker及Kubernetes技术构建容器云（PaaS）平台概述](concepts/architecture/paas-based-on-docker-and-kubernetes.md)
* [kubernetes对象]()
    * [理解kubernetes对象](concepts/object/understanding-kubernetes-objects.md)
    * [kubernetes常用对象说明](concepts/object/kubernetes-basic-concepts.md)
* [Pod]()
    * [Pod介绍](concepts/pod/pod.md)
    * [Pod定义文件](concepts/pod/pod-definition.md)
    * [Pod生命周期](concepts/pod/pod-lifecycle.md)
    * [Pod健康检查](concepts/pod/pod-probe.md)
    * [Pod存储卷](concepts/pod/pod-volume.md)
    * [Pod控制器](concepts/pod/pod-scheduler.md)
    * [Pod伸缩与升级](concepts/pod/pod-operation.md)
* [配置]()
    * [ConfigMap](concepts/pod/pod-configmap.md)
* [Workload]()

## 核心原理

* [核心组件]()
    * [Api Server](principle/kubernetes-core-principle-api-server.md)
    * [Controller Manager](principle/kubernetes-core-principle-controller-manager.md)
    * [Scheduler](principle/kubernetes-core-principle-scheduler.md)
    * [Kubelet](principle/kubernetes-core-principle-kubelet.md)
* [流程图]()
    * [Pod创建流程](principle/flow/pod-flow.md)
    * [PVC创建流程](principle/flow/pvc-flow.md)

## 网络

* [Docker网络](network/docker-network.md)
* [K8S网络](network/kubernetes-network.md)
* [网络插件]()
    * [Flannel介绍](network/flannel/flannel-introduction.md)
* [CNI]()
    * [Macvlan介绍](network/cni/macvlan.md)

## 存储

* [存储卷概念]()
    * [Volume](storage/volume.md)
    * [Persistent Volume](storage/persistent-volume.md)
    * [Persistent Volume Claim](storage/persistent-volume-claim.md)
    * [Storage Class](storage/storage-class.md)
    * [Dynamic Volume Provisioning](storage/dynamic-provisioning.md)
* [CSI]()
    * [csi-cephfs-plugin](csi/ceph/csi-cephfs-plugin.md)
    * [部署csi-cephfs](csi/ceph/deploy-csi-cephfs.md)
    * [部署cephfs-provisioner](csi/provisioner/cephfs-provisioner.md)
    * [FlexVolume介绍](csi/flexvolume.md)

## 资源隔离

* [资源配额](resource/resource-quota.md)
* [Pod限额](resource/limit-range.md)
* [资源服务质量](resource/quality-of-service.md)
* [Lxcfs资源视图隔离](resource/lxcfs/lxcfs.md)

## 运维指南

* [kubectl工具]()
    * [kubectl安装与配置](operation/install-kubectl.md)
    * [kubectl命令说明](operation/kubectl-commands.md)
    * [kubectl命令别名](operation/kubectl-alias.md)
* [kubernetes集群问题排查](operation/kubernetes-troubleshooting.md)
* [节点调度]()
    * [安全迁移节点](operation/safely-drain-node.md)
    * [指定Node调度与隔离](operation/nodeselector-and-taint.md)
* [镜像仓库配置]()
    * [配置私有的镜像仓库](operation/registry/config-private-registry.md)
    * [拉取私有镜像](operation/registry/ImagePullSecrets.md)

## 开发指南

* [client-go的使用及源码分析](develop/client-go.md)
* [CSI插件开发]()
    * [nfs-client-provisioner源码分析](develop/nfs-client-provisioner.md)
    * [csi-provisioner源码分析](develop/csi-provisioner.md)
* [operator开发]()
    * [kubebuilder的使用](develop/operator/kubebuilder.md)

## 问题排查

* [节点相关问题]()
    * [keycreate permission denied](trouble-shooting/node/keycreate-permission-denied.md)
    * [Cgroup不支持pid资源](trouble-shooting/node/cgroup-pid-error.md)
    * [Cgroup子系统无法挂载](trouble-shooting/node/cgroup-subsystem-not-mount.md)
* [Pod驱逐](trouble-shooting/pod-evicted.md)
* [镜像拉取失败问题](trouble-shooting/pod-image-error.md)
* [PVC Terminating](trouble-shooting/pvc-terminating.md)

----

## 源码分析
* [Kubernetes源码分析笔记](code-analysis/code-analysis-notes.md)
* [kubelet]()
    * [NewKubeletCommand](code-analysis/kubelet/NewKubeletCommand.md)
    * [NewMainKubelet](code-analysis/kubelet/NewMainKubelet.md)
    * [startKubelet](code-analysis/kubelet/startKubelet.md)
    * [syncLoopIteration](code-analysis/kubelet/syncLoopIteration.md)
    * [syncPod](code-analysis/kubelet/syncPod.md)
* [kube-controller-manager]()
    * [NewControllerManagerCommand](code-analysis/kube-controller-manager/NewControllerManagerCommand.md)
    * [DeploymentController](code-analysis/kube-controller-manager/deployment-controller.md)
    * [Informer机制](code-analysis/kube-controller-manager/sharedIndexInformer.md)
* [kube-scheduler]()
    * [NewSchedulerCommand](code-analysis/kube-scheduler/NewSchedulerCommand.md)
    * [registerAlgorithmProvider](code-analysis/kube-scheduler/registerAlgorithmProvider.md)
    * [scheduleOne](code-analysis/kube-scheduler/scheduleOne.md)
    * [findNodesThatFit](code-analysis/kube-scheduler/findNodesThatFit.md)
    * [PrioritizeNodes](code-analysis/kube-scheduler/PrioritizeNodes.md)
    * [preempt](code-analysis/kube-scheduler/preempt.md)
* [kube-apiserver]()
    * [NewAPIServerCommand](code-analysis/kube-apiserver/NewAPIServerCommand.md)


----

## Runtime

* [Runtime]()
    * [Runc和Containerd概述](runtime/runtime.md)
* [Docker]()
    * [Docker学习笔记](docker/docker-notes.md)
* [Kata Container]()
    * [kata容器简介](runtime/kata/kata-container.md)
    * [kata配置](runtime/kata/kata-container-conf.md)

## Etcd

* [Etcd介绍](etcd/etcd-introduction.md)
* [Raft算法](etcd/raft.md)
* [Etcd启动配置参数](etcd/etcd-setup-flags.md)
* [Etcd访问控制](etcd/etcd-auth-and-security.md)
* [etcdctl命令工具]()
    * [etcdctl命令工具-V3](etcd/etcdctl-v3.md)
    * [etcdctl命令工具-V2](etcd/etcdctl-v2.md)
* [Etcd中的k8s数据](etcd/k8s-etcd-data.md)
* [Etcd-Operator的使用](etcd/etcd-operator-usage.md)

## 多集群管理
* [k8s多集群管理的思考](multi-cluster/k8s-multi-cluster-thinking.md)
* [Virtual Kubelet]()
    * [Virtual Kubelet介绍](virtual-kubelet/virtual-kubelet.md)
    * [Virtual Kubelet 命令](virtual-kubelet/virtual-kubelet-cmd.md)
* [Karmada]()
    * [Karmada介绍](multi-cluster/karmada.md)

## KubeEdge

* [KubeEdge介绍](kubeedge/kubeedge-arch.md)
* [KubeEdge源码分析]()
    * [cloudcore](kubeedge/code-analysis/cloudcore.md)
    * [edgecore](kubeedge/code-analysis/edgecore.md)

## 监控体系

* [监控体系介绍](monitor/kubernetes-cluster-monitoring.md)
* [cAdvisor介绍](monitor/cadvisor-introduction.md)
* [Heapster介绍](monitor/heapster-introduction.md)
* [Influxdb介绍](monitor/influxdb-introduction.md)

## GPU

* [nvidia-device-plugin介绍](gpu/nvidia-device-plugin.md)

## 虚拟化

* [虚拟化相关概念](kvm/vm-concept.md)

---

# 赞赏

> 如果觉得文章有帮助的话，可以打赏一下，谢谢！

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1551599963/blog/donate.jpg" width="70%"/>
