# 1. Pod是什么（what）

## 1.1. Pod概念

- Pod是kubernetes集群中最小的部署和管理的`基本单元`，协同寻址，协同调度。
- Pod是一个或多个容器的集合，是一个或一组服务（进程）的抽象集合。
- Pod中可以共享网络和存储（可以简单理解为一个逻辑上的虚拟机，但并不是虚拟机）。
- Pod被创建后用一个`UID`来唯一标识，当Pod生命周期结束，被一个等价Pod替代，UID将重新生成。

### 1.1.1. Pod与Docker

- Docker是目前Pod最常用的容器环境，但仍支持其他容器环境。
- Pod是一组被模块化的拥有共享命名空间和共享存储卷的容器，但并没有共享PID 命名空间（即同个Pod的不同容器中进程的PID是独立的，互相看不到非自己容器的进程）。

### 1.1.2. Pod中容器的运行方式

1. **只运行一个单独的容器**

即`one-container-per-Pod`模式，是最常用的模式，可以把这样的Pod看成单独的一个容器去管理。

2. **运行多个强关联的容器**

即`sidecar`模式，Pod 封装了一组紧耦合、共享资源、协同寻址的容器，将这组容器作为一个管理单元。

## 1.2. Pod管理多个容器

Pod是一组紧耦合的容器的集合，Pod内的容器作为一个整体以Pod形式进行协同寻址，协同调度、协同管理。相同Pod内的容器共享网络和存储。

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1535286616/article/kubernetes/pod/pod.svg" width="50%" />

### 1.2.1. 网络

- 每个Pod被分配了唯一的IP地址，该Pod内的所有容器共享一个网络空间，包括IP和端口。
- 同个Pod不同容器之间通过`localhos`t通信，Pod内端口不能冲突。
- 不同Pod之间的通信则通过IP+端口的形式来访问到Pod内的具体服务（容器）。

### 1.2.2. 存储

- 可以在Pod中创建共享`存储卷`的方式来实现不同容器之间数据共享。

# 2. 为什么需要Pod(why)

## 2.1. 管理需求

Pod 是一种模式的抽象：互相协作的多个进程（容器）共同形成一个完整的服务。以一个或多个容器的方式组合成一个整体，作为管理的基本单元，通过Pod可以方便部署、水平扩展，协同调度等。

## 2.2. 资源共享和通信

Pod作为多个紧耦合的容器的集合，通过共享网络和存储的方式来简化紧耦合容器之间的通信，从这个角度，可以将Pod简单理解为一个逻辑上的“虚拟机”。而不同的Pod之间的通信则通过Pod的IP和端口的方式。

## 2.3. Pod设计的优势

- 调度器和控制器的可拔插性。
- 将Pod 的生存期从 controller 中剥离出来，从而减少相互影响。
- 高可用--在终止和删除 Pod 前，需要提前生成替代 Pod。
- 集群级别的功能和 Kubelet（Pod Controller） 级别的功能组合更加清晰。

# 3. Pod的使用(how)

Pod一般是通过各种不同类型的`Controller`对Pod进行管理和控制，包括自我恢复（例如Pod因异常退出，则会再起一个相同的Pod替代该Pod，而该Pod则会被清除）。也可以不通过Controller单独创建一个Pod，但一般很少这么操作，因为这个Pod是一个孤立的实体，并不会被Controller管理。

## 3.1. Controller

`Controller`是kubernetes中用于对Pod进行管理的控制器，通过该控制器让Pod始终维持在一个用户原本设定或期望的状态。如果节点宕机或者Pod因其他原因死亡，则会在其他节点起一个相同的Pod来替代该Pod。

常用的Controller有：

- `Deployment`
- `StatefulSet`
- `DaemonSet`

`Controller`是通过用户提供的Pod模板来创建和控制Pod。

## 3.2. Pod模板

Pod模板用来定义Pod的各种属性，Controller通过Pod模板来生成对应的Pod。

Pod模板类似一个饼干模具，通过模具已经生成的饼干与原模具已经没有关系，即对原模具的修改不会影响已经生成的饼干，只会对通过修改后的模具生成的饼干有影响。这种方式可以更加方便地控制和管理Pod。

# 4. Pod的终止

用户发起一个删除Pod的请求，系统会先发送`TERM`信号给每个容器的主进程，如果在宽限期（默认30秒）主进程没有自主终止运行，则系统会发送`KILL`信号给该进程，接着Pod将被删除。

## 4.1. Pod终止的流程

1. 用户发送一个删除 Pod 的命令， 并使用默认的宽限期（30s)。
2. 把 API server 上的 pod 的时间更新成 Pod 与宽限期一起被认为 “dead” 之外的时间点。
3. 使用客户端的命令，显示出的Pod的状态为 `terminating`。
4. （与第3步同时发生）Kubelet 发现某一个 Pod 由于时间超过第2步的设置而被标志成 terminating 状态时， Kubelet 将启动一个停止进程。
   1. 如果 pod 已经被定义成一个 `preStop hook`，这会在 pod 内部进行调用。如果宽限期已经过期但 preStop 锚依然还在运行，将调用第2步并在原来的宽限期上加一个小的时间窗口（2 秒钟）。
   2. 把 Pod 里的进程发送到 `TERM `信号。
5. （与第3步同时发生），Pod 被从终端的服务列表里移除，同时也不再被 replication controllers 看做时一组运行中的 pods。 在负载均衡（比如说 service proxy）会将它们从轮询中移除前， Pods 这种慢关闭的方式可以继续为流量提供服务。
6. 当宽期限过期时， 任何还在 Pod 里运行的进程都会被 `SIGKILL `杀掉。
7. Kubelet 通过在 API server 把宽期限设置成0(立刻删除)的方式完成删除 Pod的过程。 这时 Pod 在 API 里消失，也不再能被用户看到。

## 4.2. 强制删除Pod

强制删除Pod是指从k8s集群状态和Etcd中立刻删除对应的Pod数据，API Server不会等待kubelet的确认信息。被强制删除后，即可重新创建一个相同名字的Pod。

删除默认的宽限期是30秒，通过将宽限期设置为0的方式可以强制删除Pod。

通过`kubectl delete` 命令后加`--force`和`--grace-period=0`的参数强制删除Pod。

```bash
kubectl delete pod <pod_name> --namespace=<namespace>  --force --grace-period=0
```

## 4.3. Pod特权模式

特权模式是指让Pod中的进程具有访问宿主机系统设备或使用网络栈操作等的能力，例如编写网络插件和卷插件。

通过将`container spec`中的`SecurityContext`设置为`privileged`即将该容器赋予了特权模式。特权模式的使用要求k8s版本高于`v1.1`。



参考文章：

- https://kubernetes.io/docs/concepts/workloads/pods/pod-overview/
- https://kubernetes.io/docs/concepts/workloads/pods/pod/
