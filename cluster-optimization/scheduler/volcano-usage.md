---
title: "Volcano的使用"
weight: 2
catalog: true
date: 2025-06-27 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
- Scheduler
catagories:
- Kubernetes
- Scheduler
---

> 本文主要介绍volcano的使用，内容由官网文档进行整理。

# 1. Volcano介绍

Volcano作为一个通用批处理平台，Volcano与几乎所有的主流计算框 架无缝对接，如[Spark](https://spark.apache.org/) 、[TensorFlow](https://tensorflow.google.cn/) 、[PyTorch](https://pytorch.org/) 、 [Flink](https://flink.apache.org/) 、[Argo](https://argoproj.github.io/) 、[MindSpore](https://www.mindspore.cn/) 、 [PaddlePaddle](https://www.paddlepaddle.org.cn/)，[Ray](https://www.ray.io/)等。还提供了包括异构设备调度，网络拓扑感知调度，多集群调度，在离线混部调度等多种调度能力。

# 2. 特性

## 2.1. 统一调度

- 支持Kubernetes原生负载调度
- 支持使用VolcanoJob来进行PyTorch、TensorFlow、Spark、Flink、Ray等框架的一体化作业调度
- 将在线微服务和离线批处理作业统一调度，提升集群资源利用率

## 2.2. 丰富的调度策略

- **Gang Scheduling**：确保作业的所有任务同时启动，适用于分布式训练、大数据等场景。
- **Binpack Scheduling**：通过任务紧凑分配优化资源利用率
- **Heterogeneous device scheduling**：高效共享GPU异构资源，支持CUDA和MIG两种模式的GPU调度，支持NPU调度
- **Proportion/Capacity Scheduling**：基于队列配额进行资源的共享/抢占/回收
- **NodeGroup Scheduling**：支持节点分组亲和性调度，实现队列与节点组的绑定关系
- **DRF Scheduling**：支持多维度资源的公平调度
- **SLA Scheduling**：基于服务质量的调度保障
- **Task-topology Scheduling**：支持任务拓扑感知调度，优化通信密集型应用性能
- **NUMA Aware Scheduling**：支持NUMA架构的调度，优化任务在多核处理器上的资源分配，提升内存访问效率和计算性能

## 2.3. GPU支持

支持多种[GPU虚拟化](https://volcano.sh/zh/docs/gpu_virtualization/)技术，提供灵活的GPU资源管理

- **动态MIG支持**：支持NVIDIA Multi-Instance GPU(MIG)，通过硬件级隔离将单个GPU分割为多个独立的GPU实例
- **vCUDA虚拟化**：通过软件层将物理GPU虚拟化为多个vGPU设备，实现资源共享和隔离
- **细粒度资源控制**：为每个GPU实例提供独立的显存和算力分配
- **多容器共享**：允许多个容器安全地共享同一个GPU资源，提升利用率
- **统一监控**：提供对所有GPU实例的统一使用情况监控和指标收集

## 2.4. 在离线混部

- 支持在线和离线业务混合部署，通过统一调度，动态资源超卖，CPU Burst，资源隔离等能力，提升资源利用率的同时保障在线业务QoS

## 2.5. 重调度

- 支持动态重调度，优化集群负载分布，提升系统稳定性

# 3. 架构介绍

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1751114745/article/kubernetes/scheduler/volcano_arch.png)

Volcano由scheduler、controllermanager、admission和vcctl组成:

- Scheduler Volcano scheduler通过一系列的action和plugin调度Job，并为它找到一个最适合的节点。与Kubernetes default-scheduler相比，Volcano与众不同的 地方是它支持针对Job的多种调度算法。

- Controllermanager Volcano controllermanager管理CRD资源的生命周期。它主要由**Queue ControllerManager**、 **PodGroupControllerManager**、 **VCJob ControllerManager**构成。

- Admission Volcano admission负责对CRD API资源进行校验。

- Vcctl 是Volcano的命令行客户端工具。

# 4. 部署

可以通过helm部署volcano。

```bash
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts

helm repo update

helm install volcano volcano-sh/volcano -n volcano-system --create-namespace
```

查看volcano组件

```bash
kubectl get all -n volcano-system
NAME                                       READY   STATUS      RESTARTS   AGE
pod/volcano-admission-5bd5756f79-p89tx     1/1     Running     0          6m10s
pod/volcano-admission-init-d4dns           0/1     Completed   0          6m10s
pod/volcano-controllers-687948d9c8-bd28m   1/1     Running     0          6m10s
pod/volcano-scheduler-94998fc64-9df5g      1/1     Running     0          6m10s

NAME                                TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/volcano-admission-service   ClusterIP   10.96.140.22   <none>        443/TCP   6m10s

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/volcano-admission     1/1     1            1           6m10s
deployment.apps/volcano-controllers   1/1     1            1           6m10s
deployment.apps/volcano-scheduler     1/1     1            1           6m10s

NAME                                             DESIRED   CURRENT   READY   AGE
replicaset.apps/volcano-admission-5bd5756f79     1         1         1       6m10s
replicaset.apps/volcano-controllers-687948d9c8   1         1         1       6m10s
replicaset.apps/volcano-scheduler-94998fc64      1         1         1       6m10s

NAME                               COMPLETIONS   DURATION   AGE
job.batch/volcano-admission-init   1/1           28s        6m10s
```

# 5. 使用

我们以组调度为例（gang scheduling），通过成组调度，您可以指定一个最小数量的Pod，这些Pod必须能够作为一个组被同时调度，然后该工作负载的任何Pod才能启动。

## 5.1. 创建带有`group-min-member`注解的Deployment

让我们创建一个Deployment，它期望有3个副本，但要求至少有2个Pod能被Volcano作为一个组进行调度。

```yaml
# deployment-with-minmember.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-deployment
  annotations:
    # 对成组调度至关重要：此注解告知Volcano将此Deployment视为一个组，
    # 要求至少2个Pod能够一起调度，然后才会启动任何Pod。
    scheduling.volcano.sh/group-min-member: "2"
    # 可选：您也可以为此Deployment创建的PodGroup指定一个特定的Volcano队列。
    # scheduling.volcano.sh/queue-name: "my-deployment-queue"
  labels:
    app: my-app
spec:
  replicas: 3 # 我们期望应用有3个副本
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      schedulerName: volcano # 关键：确保此Deployment的Pod使用Volcano调度器
      containers:
        - name: my-container
          image: busybox
          command: ["sh", "-c", "echo 'Hello Volcano from Deployment'; sleep 3600"] # 一个长时间运行的命令，用于演示
          resources:
            requests:
              cpu: 1
            limits:
              cpu: 1
```

## 5.2. 观察自动创建的PodGroup和Pod

当您应用带有`scheduling.volcano.sh/group-min-member`注解的Deployment（或StatefulSet）时，Volcano会自动创建一个PodGroup资源。此PodGroup负责为属于该工作负载的Pod强制执行成组调度约束。

检查PodGroup的状态：

```bash
kubectl get pg podgroup-[ReplicaSet的UID] -oyaml
```

输出

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  # ...
  name: podgroup-09e95eb0-e520-4b50-a15c-c14cad844674
  namespace: default
  ownerReferences:
  - apiVersion: apps/v1
    blockOwnerDeletion: true
    controller: true
    kind: ReplicaSet
    name: my-app-deployment-74644c8849
    uid: 09e95eb0-e520-4b50-a15c-c14cad844674
  # ...
spec:
  minMember: 2
  minResources:
    count/pods: "2"
    cpu: "2"
    limits.cpu: "2"
    pods: "2"
    requests.cpu: "2"
  queue: default
status:
  conditions:
  - lastTransitionTime: "2025-05-28T09:08:13Z"
    reason: tasks in gang are ready to be scheduled
    status: "True"
    transitionID: e0b1508e-4b77-4dea-836f-0b14f9ca58df
    type: Scheduled
  phase: Running
  running: 3
```

将观察到Volcano调度器会确保至少`minMember`（本例中为2）个Pod能够一起调度，然后才允许此Deployment中的任何Pod启动。如果资源不足以满足这些Pod的需求，它们将保持`Pending`状态。

参考：

- [介绍 | Volcano](https://volcano.sh/zh/docs/)

- [快速开始 | Volcano](https://volcano.sh/zh/docs/tutorials/)

- [GitHub - volcano-sh/volcano: A Cloud Native Batch System ](https://github.com/volcano-sh/volcano)
