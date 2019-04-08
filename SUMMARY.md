# Summary

## 前言

* [序言](README.md)

## PaaS

* [12-Factor](paas/12-factor.md)
  
## 安装与配置

* [使用kubespray安装kubernetes](setup/install-k8s-by-kubespray.md)
* [使用minikube安装kubernetes](setup/install-k8s-by-minikube.md)

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
    * [Pod配置管理](concepts/pod/pod-configmap.md)
    * [Pod调度](concepts/pod/pod-scheduler.md)
    * [Pod操作](concepts/pod/pod-operation.md)

## 核心原理

 * [Api Server](principle/kubernetes-core-principle-api-server.md)
 * [Controller Manager](principle/kubernetes-core-principle-controller-manager.md)
 * [Scheduler](principle/kubernetes-core-principle-scheduler.md)
 * [Kubelet](principle/kubernetes-core-principle-kubelet.md)

## 网络

* [Docker网络](network/docker-network.md)
* [k8s网络](network/kubernetes-network.md)
* [Flannel]()
    * [Flannel介绍](network/flannel/flannel-introduction.md)

## 存储

* [Volume](storage/volume.md)
* [Persistent Volume](storage/persistent-volume.md)
* [Persistent Volume Claim](storage/persistent-volume-claim.md)   
* [Storage Class](storage/storage-class.md)
* [Dynamic Volume Provisioning](storage/dynamic-provisioning.md)

## CSI

* [csi-cephfs-plugin](csi/ceph/csi-cephfs-plugin.md)
* [部署csi-cephfs](csi/ceph/deploy-csi-cephfs.md)

## 资源配额

* [资源配额](resource/resource-quota.md)
* [Pod限额](resource/limit-range.md)
* [资源服务质量](resource/quality-of-service.md)   

## 运维指南

* [kubectl安装与配置](operation/install-kubectl.md)
* [kubectl命令说明](operation/kubectl-commands.md)
* [安全迁移节点](operation/safely-drain-node.md)
* [kubernetes集群问题排查](operation/kubernetes-troubleshooting.md)
* [指定Node调度与隔离](operation/nodeselector-and-taint.md)

## 开发指南

* [client-go的使用及源码分析](develop/client-go.md)
* [nfs-client-provisioner源码分析](develop/nfs-client-provisioner.md)
* [csi-provisioner源码分析](develop/csi-provisioner.md)

## 源码分析

* [kubelet]()
    * [NewKubeletCommand](code-analysis/kubelet/NewKubeletCommand.md)
    * [NewMainKubelet](code-analysis/kubelet/NewMainKubelet.md)
    * [RunKubelet](code-analysis/kubelet/RunKubelet.md)
    * [Pod的创建](code-analysis/kubelet/create-pod-by-kubelet.md)
* [kube-controller-manager]()
    * [NewControllerManagerCommand](code-analysis/kube-controller-manager/NewControllerManagerCommand.md)
    * [DeploymentController](code-analysis/kube-controller-manager/deployment-controller.md)
    * [Informer机制](code-analysis/kube-controller-manager/sharedIndexInformer.md)
* [kube-scheduler]()
    * [NewSchedulerCommand](code-analysis/kube-scheduler/NewSchedulerCommand.md)
    * [registerAlgorithmProvider](code-analysis/kube-scheduler/registerAlgorithmProvider.md)
    * [scheduleOne](code-analysis/kube-scheduler/scheduleOne.md)

## 监控体系

* [监控体系介绍](monitor/kubernetes-cluster-monitoring.md)
* [cAdvisor介绍](monitor/cadvisor-introduction.md)
* [Heapster介绍](monitor/heapster-introduction.md)
* [Influxdb介绍](monitor/influxdb-introduction.md)


----


## Docker

* [安装Docker](docker/install-docker.md)
* [Docker架构图](docker/docker-architecture.md)
* [Docker常用命令原理图](docker/docker-commands-principle.md)
* [Dockerfile使用说明](docker/dockerfile-usage.md)
* [Docker源码分析]()
    * [Docker Client](docker/code-analysis/code-analysis-of-docker-client.md) 
    * [Docker Daemon](docker/code-analysis/code-analysis-of-docker-daemon.md) 
    * [Docker Server](docker/code-analysis/code-analysis-of-docker-server.md) 

## Etcd

* [Etcd介绍](etcd/etcd-introduction.md)
* [Raft算法](etcd/raft.md)
* [Etcd启动配置参数](etcd/etcd-setup-flags.md)
* [Etcd访问控制](etcd/etcd-auth-and-security.md)
* [etcdctl命令工具-V2](etcd/etcdctl-v2.md)
* [etcdctl命令工具-V3](etcd/etcdctl-v3.md)
