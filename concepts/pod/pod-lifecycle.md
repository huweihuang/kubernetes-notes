---
title: "Pod生命周期"
weight: 3
catalog: true
date: 2017-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. Pod phase

Pod的`phase`是Pod生命周期中的简单宏观描述，定义在Pod的`PodStatus`对象的`phase` 字段中。

`phase`有以下几种值：

| 状态值       | 说明                                       |
| --------- | ---------------------------------------- |
| `挂起（Pending）`   | Pod 已被 Kubernetes 系统接受，但有一个或者多个容器镜像尚未创建。等待时间包括调度 Pod 的时间和通过网络下载镜像的时间。 |
| `运行中（Running）`   | 该 Pod 已经绑定到了一个节点上，Pod 中所有的容器都已被创建。至少有一个容器正在运行，或者正处于启动或重启状态。 |
| `成功（Succeeded）` | Pod 中的所有容器都被成功终止，并且不会再重启。                  |
| `失败（Failed）`    | Pod 中的所有容器都已终止了，并且至少有一个容器是因为失败终止。也就是说，容器以非0状态退出或者被系统终止。               |
| `未知（Unknown）`   | 因为某些原因无法取得 Pod 的状态，通常是因为与 Pod 所在主机通信失败。           |


# 2. Pod 状态

Pod 有一个 `PodStatus` 对象，其中包含一个 [PodCondition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.11/#podcondition-v1-core) 数组。 `PodCondition`包含以下以下字段：

- `lastProbeTime`：Pod condition最后一次被探测到的时间戳。
- `lastTransitionTime`：Pod最后一次状态转变的时间戳。
- `message`：状态转化的信息，一般为报错信息，例如：containers with unready status: [c-1]。
- `reason`：最后一次状态形成的原因，一般为报错原因，例如：ContainersNotReady。
- `status`：包含的值有 True、False 和 Unknown。
- `type`：Pod状态的几种类型。

其中type字段包含以下几个值：

- `PodScheduled`：Pod已经被调度到运行节点。
- `Ready`：Pod已经可以接收请求提供服务。
- `Initialized`：所有的init container已经成功启动。
- `Unschedulable`：无法调度该Pod，例如节点资源不够。
- `ContainersReady`：Pod中的所有容器已准备就绪。

# 3. 重启策略

Pod通过`restartPolicy`字段指定重启策略，重启策略类型为：Always、OnFailure 和 Never，默认为 Always。

`restartPolicy` 仅指通过同一节点上的 kubelet 重新启动容器。

| 重启策略      | 说明                              |
| --------- | ------------------------------- |
| Always    | 当容器失效时，由kubelet自动重启该容器          |
| OnFailure | 当容器终止运行且退出码不为0时，由kubelet自动重启该容器 |
| Never     | 不论容器运行状态如何，kubelet都不会重启该容器      |

**说明**：

可以管理Pod的控制器有Replication Controller，Job，DaemonSet，及kubelet（静态Pod）。

1. RC和DaemonSet：必须设置为Always，需要保证该容器持续运行。
2. Job：OnFailure或Never，确保容器执行完后不再重启。
3. kubelet：在Pod失效的时候重启它，不论RestartPolicy设置为什么值，并且不会对Pod进行健康检查。

# 4. Pod的生命

Pod的生命周期一般通过`Controler`	的方式管理，每种`Controller`都会包含`PodTemplate`来指明Pod的相关属性，Controller可以自动对pod的异常状态进行重新调度和恢复，除非通过Controller的方式删除其管理的Pod，不然kubernetes始终运行用户预期状态的Pod。

**控制器的分类**

- 使用 `Job`运行预期会终止的 Pod，例如批量计算。Job 仅适用于重启策略为 `OnFailure` 或 `Never` 的 Pod。
- 对预期不会终止的 Pod 使用 `ReplicationController`、`ReplicaSet`和 `Deployment`，例如 Web 服务器。 ReplicationController 仅适用于具有 `restartPolicy` 为 Always 的 Pod。
- 提供特定于机器的系统服务，使用 `DaemonSet`为每台机器运行一个 Pod 。

如果节点死亡或与集群的其余部分断开连接，则 Kubernetes 将应用一个策略将丢失节点上的所有 Pod 的 `phase` 设置为 `Failed`。

# 5. Pod状态转换

**常见的状态转换**

| Pod的容器数 | Pod当前状态 | 发生的事件    | Pod结果状态              |                         |                     |
| ------- | ------- | -------- | -------------------- | ----------------------- | ------------------- |
|         |         |          | RestartPolicy=Always | RestartPolicy=OnFailure | RestartPolicy=Never |
| 包含一个容器  | Running | 容器成功退出   | Running              | Succeeded               | Succeeded           |
| 包含一个容器  | Running | 容器失败退出   | Running              | Running                 | Failure             |
| 包含两个容器  | Running | 1个容器失败退出 | Running              | Running                 | Running             |
| 包含两个容器  | Running | 容器被OOM杀掉 | Running              | Running                 | Failure             |


## 5.1. 容器运行时内存超出限制

- 容器以失败状态终止。
- 记录 OOM 事件。
- 如果`restartPolicy`为：
  - Always：重启容器；Pod `phase` 仍为 Running。
  - OnFailure：重启容器；Pod `phase` 仍为 Running。
  - Never: 记录失败事件；Pod `phase` 仍为 Failed。

## 5.2. 磁盘故障

- 杀掉所有容器。
- 记录适当事件。
- Pod `phase` 变成 Failed。
- 如果使用控制器来运行，Pod 将在别处重建。

## 5.3. 运行节点挂掉

- 节点控制器等待直到超时。
- 节点控制器将 Pod `phase` 设置为 Failed。
- 如果是用控制器来运行，Pod 将在别处重建。


参考文章：

- https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

