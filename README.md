## kubernetes-notes
> Kubernetes 学习笔记

## Summary
* [Introduction](README.md)

* [1. 安装与配置](setup/README.md)
    * [1.1. 使用kubespray安装kubernetes](setup/install-k8s-by-kubespray.md)
    * [1.2. 使用minikube安装kubernetes](setup/install-k8s-by-minikube.md)
* [2. 基本概念](concepts/README.md)
    * [2.1. kubernetes架构](concepts/architecture/README.md)
        * [2.1.1. Kubernetes总架构图](concepts/architecture/kubernetes-architecture.md)
        * [2.1.2. 基于Docker及Kubernetes技术构建容器云（PaaS）平台概述](concepts/architecture/paas-based-on-docker-and-kubernetes.md)
    * [2.2. kubernetes对象](concepts/object/README.md)
        * [2.2.1. 理解kubernetes对象](concepts/object/understanding-kubernetes-objects.md)
        * [2.2.2. kubernetes常用对象说明](concepts/object/kubernetes-basic-concepts.md)
        * [2.2.3. Pod详解](concepts/object/kubernetes-pod-introduction.md)
* [3. 核心原理](principle/README.md)
    * [3.1. Api Server](principle/kubernetes-core-principle-api-server.md)
    * [3.2. Controller Manager](principle/kubernetes-core-principle-controller-manager.md)
    * [3.3. Scheduler](principle/kubernetes-core-principle-scheduler.md)
    * [3.4. Kubelet](principle/kubernetes-core-principle-kubelet.md)
* [4. 运维指南](operation/README.md)
    * [4.1. kubernetes集群问题排查](operation/kubernetes-troubleshooting.md)
    * [4.2. 指定Node调度与隔离](operation/nodeselector-and-taint.md)
* [5. 监控体系](monitor/README.md)
    * [5.1. 监控体系介绍](monitor/kubernetes-cluster-monitoring.md)
    * [5.2. cAdvisor介绍](monitor/cadvisor-introduction.md)
    * [5.3. Heapster介绍](monitor/heapster-introduction.md)
    * [5.4. Influxdb介绍](monitor/influxdb-introduction.md)
  