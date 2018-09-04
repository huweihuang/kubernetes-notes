# 1. Pod phase

Pod的`phase`是Pod生命周期中的简单宏观描述，定义在Pod的`PodStatus`对象的`phase` 字段中。

`phase`有以下几种值：

- `挂起（Pending）`：Pod 已被 Kubernetes 系统接受，但有一个或者多个容器镜像尚未创建。等待时间包括调度 Pod 的时间和通过网络下载镜像的时间。
- `运行中（Running）`：该 Pod 已经绑定到了一个节点上，Pod 中所有的容器都已被创建。至少有一个容器正在运行，或者正处于启动或重启状态。
- `成功（Succeeded）`：Pod 中的所有容器都被成功终止，并且不会再重启。
- `失败（Failed）`：Pod 中的所有容器都已终止了，并且至少有一个容器是因为失败终止。也就是说，容器以非0状态退出或者被系统终止。
- `未知（Unknown）`：因为某些原因无法取得 Pod 的状态，通常是因为与 Pod 所在主机通信失败。

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

# 3. 容器探针

## 3.1. Handler

`探针`是`kubelet`对容器执行定期的诊断，主要通过调用容器配置的三类`Handler`实现：

**Handler的类型**：

- `ExecAction`：在容器内执行指定命令。如果命令退出时返回码为 0 则认为诊断成功。
- `TCPSocketAction`：对指定端口上的容器的 IP 地址进行 TCP 检查。如果端口打开，则诊断被认为是成功的。
- `HTTPGetAction`：对指定的端口和路径上的容器的 IP 地址执行 HTTP Get 请求。如果响应的状态码大于等于200 且小于 400，则诊断被认为是成功的。

**探测结果**为以下三种之一：

- `成功`：容器通过了诊断。
- `失败`：容器未通过诊断。
- `未知`：诊断失败，因此不会采取任何行动。

## 3.2. 探针类型

**1. livenessProbe(存活探针)**

- 表明容器是否正在运行。
- 如果存活探测失败，则 kubelet 会杀死容器，并且容器将受到其 `重启策略`的影响。
- 如果容器不提供存活探针，则默认状态为 `Success`。

**2. readinessProbe(就绪探针)**

- 表明容器是否可以正常接受请求。
- 如果就绪探测失败，端点控制器将从与 Pod 匹配的所有 Service 的端点中删除该 Pod 的 IP 地址。
- 初始延迟之前的就绪状态默认为 `Failure`。
- 如果容器不提供就绪探针，则默认状态为 `Success`。

**探针使用方式**

- 如果容器异常可以自动崩溃，则不一定要使用探针，可以由Pod的`restartPolicy`执行重启操作。
- `存活探针`适用于希望容器探测失败后被杀死并重新启动，需要指定`restartPolicy` 为 Always 或 OnFailure。
- `就绪探针`适用于希望Pod在不能正常接收流量的时候被剔除，并且在就绪探针探测成功后才接收流量。

**示例**

存活探针由 kubelet 来执行，因此所有的请求都在 kubelet 的网络命名空间中进行。

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    test: liveness
  name: liveness-http
spec:
  containers:
  - args:
    - /server
    image: gcr.io/google_containers/liveness
    livenessProbe:
      httpGet:
        # when "host" is not defined, "PodIP" will be used
        # host: my-host
        # when "scheme" is not defined, "HTTP" scheme will be used. Only "HTTP" and "HTTPS" are allowed
        # scheme: HTTPS
        path: /healthz
        port: 8080
        httpHeaders:
          - name: X-Custom-Header
            value: Awesome
      initialDelaySeconds: 15
      timeoutSeconds: 1
    name: liveness
```

# 4. 重启策略

Pod通过`restartPolicy`字段指定重启策略，重启策略类型为：Always、OnFailure 和 Never，默认为 Always。

`restartPolicy` 仅指通过同一节点上的 kubelet 重新启动容器。

# 5. Pod的生命

Pod的生命周期一般通过`Controler`	的方式管理，每种`Controller`都会包含`PodTemplate`来指明Pod的相关属性，Controller可以自动对pod的异常状态进行重新调度和恢复，除非通过Controller的方式删除其管理的Pod，不然kubernetes始终运行用户预期状态的Pod。

**控制器的分类**

- 使用 `Job`运行预期会终止的 Pod，例如批量计算。Job 仅适用于重启策略为 `OnFailure` 或 `Never` 的 Pod。
- 对预期不会终止的 Pod 使用 `ReplicationController`、`ReplicaSet`和 `Deployment`，例如 Web 服务器。 ReplicationController 仅适用于具有 `restartPolicy` 为 Always 的 Pod。
- 提供特定于机器的系统服务，使用 `DaemonSet`为每台机器运行一个 Pod 。

如果节点死亡或与集群的其余部分断开连接，则 Kubernetes 将应用一个策略将丢失节点上的所有 Pod 的 `phase` 设置为 `Failed`。

# 6. Pod状态转换

## 6.1. 容器运行时内存超出限制

- 容器以失败状态终止。
- 记录 OOM 事件。
- 如果`restartPolicy`为：
  - Always：重启容器；Pod `phase` 仍为 Running。
  - OnFailure：重启容器；Pod `phase` 仍为 Running。
  - Never: 记录失败事件；Pod `phase` 仍为 Failed。

## 6.2. 磁盘故障

- 杀掉所有容器。
- 记录适当事件。
- Pod `phase` 变成 Failed。
- 如果使用控制器来运行，Pod 将在别处重建。

## 6.3. 运行节点挂掉

- 节点控制器等待直到超时。
- 节点控制器将 Pod `phase` 设置为 Failed。
- 如果是用控制器来运行，Pod 将在别处重建。



参考文章：

- https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

