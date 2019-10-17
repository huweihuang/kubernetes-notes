# 1. 简介

`Virtual Kubelet`是 [Kubernetes kubelet](https://kubernetes.io/docs/reference/generated/kubelet/) 的一种实现，作为一种虚拟的kubelet用来连接k8s集群和其他平台的API。这允许k8s的节点由其他`提供者（provider）`提供支持，这些提供者例如serverless平台（ACI, AWS Fargate）、[IoT Edge](https://github.com/Azure/iot-edge-virtual-kubelet-provider)等。

一句话概括：Kubernetes API on top, programmable back。

# 2. 架构图

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1566560767/article/kubernetes/virtual-kubelet/vk-diagram.svg">

# 3. 功能

virtual kubelet提供一个可以自定义k8s node的依赖库。

目前支持的功能如下：

-  创建、删除、更新 pod
- 容器的日志、exec命令、metrics
- 获取pod、pod列表、pod status
- node的地址、容量、daemon
- 操作系统
- 自定义virtual network

# 4. Providers

virtual kubelet提供一个插件式的**provider**接口，让开发者可以自定义实现传统kubelet的功能。自定义的provider可以用自己的配置文件和环境参数。

自定义的provider必须提供以下功能：

- 提供pod、容器、资源的生命周期管理的功能
- 符合virtual kubelet提供的API
- 不直接访问k8s apiserver，定义获取数据的回调机制，例如configmap、secrets

开源的provider

- [Alibaba Cloud ECI Provider](https://github.com/virtual-kubelet/alibabacloud-eci)
- [Azure Container Instances Provider](https://github.com/virtual-kubelet/azure-aci)
- [AWS Fargate Provider](https://github.com/virtual-kubelet/aws-fargate)

# 5. 自定义provider

创建自定义provider的目录。

```bash
git clone https://github.com/virtual-kubelet/virtual-kubelet
cd virtual-kubelet
mkdir providers/my-provider
```

## 5.1. PodLifecylceHandler

当pod被k8s创建、更新、删除时，会调用以下方法。

```go
type PodLifecycleHandler interface {
    // CreatePod takes a Kubernetes Pod and deploys it within the provider.
    CreatePod(ctx context.Context, pod *corev1.Pod) error

    // UpdatePod takes a Kubernetes Pod and updates it within the provider.
    UpdatePod(ctx context.Context, pod *corev1.Pod) error

    // DeletePod takes a Kubernetes Pod and deletes it from the provider.
    DeletePod(ctx context.Context, pod *corev1.Pod) error

    // GetPod retrieves a pod by name from the provider (can be cached).
    GetPod(ctx context.Context, namespace, name string) (*corev1.Pod, error)

    // GetPodStatus retrieves the status of a pod by name from the provider.
    GetPodStatus(ctx context.Context, namespace, name string) (*corev1.PodStatus, error)

    // GetPods retrieves a list of all pods running on the provider (can be cached).
    GetPods(context.Context) ([]*corev1.Pod, error)
}
```

`PodLifecycleHandler`是被`PodController`来调用，来管理被分配到node上的pod。

```go
pc, _ := node.NewPodController(podControllerConfig) // <-- instatiates the pod controller
pc.Run(ctx) // <-- starts watching for pods to be scheduled on the node
```

## 5.2. PodNotifier(optional)

`PodNotifier`是可选实现，该接口主要用来通知virtual kubelet的pod状态变化。如果没有实现该接口，virtual-kubelet会定期检查所有pod的状态。

```go
type PodNotifier interface {
    // NotifyPods instructs the notifier to call the passed in function when
    // the pod status changes.
    //
    // NotifyPods should not block callers.
    NotifyPods(context.Context, func(*corev1.Pod))
}
```

## 5.3. NodeProvider

`NodeProvider`用来通知virtual-kubelet关于node状态的变化，virtual-kubelet会定期检查node是状态并相应地更新k8s。

```go
type NodeProvider interface {
    // Ping checks if the node is still active.
    // This is intended to be lightweight as it will be called periodically as a
    // heartbeat to keep the node marked as ready in Kubernetes.
    Ping(context.Context) error

    // NotifyNodeStatus is used to asynchronously monitor the node.
    // The passed in callback should be called any time there is a change to the
    // node's status.
    // This will generally trigger a call to the Kubernetes API server to update
    // the status.
    //
    // NotifyNodeStatus should not block callers.
    NotifyNodeStatus(ctx context.Context, cb func(*corev1.Node))
}
```

`NodeProvider`是被NodeController调用，来管理k8s中的node对象。

```go
nc, _ := node.NewNodeController(nodeProvider, nodeSpec) // <-- instantiate a node controller from a node provider and a kubernetes node spec
nc.Run(ctx) // <-- creates the node in kubernetes and starts up he controller
```

## 5.4. 测试

进入到项目根目录

```bash
make test
```

## 5.5. 示例代码

- Azure Container Instances Provider

  https://github.com/virtual-kubelet/azure-aci/blob/master/aci.go#L541

- Alibaba Cloud ECI Provider

  https://github.com/virtual-kubelet/alibabacloud-eci/blob/master/eci.go#L177

- AWS Fargate Provider

  https://github.com/virtual-kubelet/aws-fargate/blob/master/provider.go#L110





参考：

- https://github.com/virtual-kubelet/virtual-kubelet
- https://virtual-kubelet.io/docs/