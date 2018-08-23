# 1. kubernetes网络模型

## 1.1. 基础原则

1. 每个Pod都拥有一个独立的IP地址，而且假定所有Pod都在一个可以直接连通的、扁平的网络空间中，不管是否运行在同一Node上都可以通过Pod的IP来访问。
2. k8s中Pod的IP是最小粒度IP。同一个Pod内所有的容器共享一个网络堆栈，该模型称为IP-per-Pod模型。
3. Pod由docker0实际分配的IP，Pod内部看到的IP地址和端口与外部保持一致。同一个Pod内的不同容器共享网络，可以通过localhost来访问对方的端口，类似同一个VM内的不同进程。
4. IP-per-Pod模型从端口分配、域名解析、服务发现、负载均衡、应用配置等角度看，Pod可以看作是一台独立的VM或物理机。

## 1.2. k8s对集群的网络要求

1. 所有容器都可以不用NAT的方式同别的容器通信。
2. 所有节点都可以在不同NAT的方式下同所有容器通信，反之亦然。
3. 容器的地址和别人看到的地址是同一个地址。

以上的集群网络要求可以通过第三方开源方案实现，例如flannel。

## 1.3. 网络架构图

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/network-arch.png)

## 1.4. k8s集群IP概念汇总

由集群外部到集群内部：

| IP类型                | 说明                                    |
| ------------------- | ------------------------------------- |
| Proxy-IP            | 代理层公网地址IP，外部访问应用的网关服务器。[实际需要关注的IP]    |
| Service-IP          | Service的固定虚拟IP，Service-IP是内部，外部无法寻址到。 |
| Node-IP             | 容器宿主机的主机IP。                           |
| Container-Bridge-IP | 容器网桥（docker0）IP，容器的网络都需要通过容器网桥转发。     |
| Pod-IP              | Pod的IP，等效于Pod中网络容器的Container-IP。      |
| Container-IP        | 容器的IP，容器的网络是个隔离的网络空间。                 |

# 2. Docker的网络基础

## 2.1. Network Namespace

不同的网络命名空间中，协议栈是独立的，完全隔离，彼此之间无法通信。同一个网络命名空间有独立的路由表和独立的Iptables/Netfilter来提供包的转发、NAT、IP包过滤等功能。

### 2.1.1. 网络命名空间的实现

将与网络协议栈相关的全局变量变成一个Net Namespace变量的成员，然后在调用协议栈函数中加入一个Namepace参数。

### 2.1.2. 网络命名空间的操作

1、创建网络命名空间

ip netns add <name>

2、在命名空间内执行命令

ip netns exec <name> <command>

3、进入命名空间

ip netns exec <name> bash

# 3. Docker的网络实现

## 3.1. 容器网络

Docker使用Linux桥接，在宿主机虚拟一个Docker容器网桥(docker0)，Docker启动一个容器时会根据Docker网桥的网段分配给容器一个IP地址，称为Container-IP，同时Docker网桥是每个容器的默认网关。因为在同一宿主机内的容器都接入同一个网桥，这样容器之间就能够通过容器的Container-IP直接通信。

Docker网桥是宿主机虚拟出来的，并不是真实存在的网络设备，外部网络是无法寻址到的，这也意味着外部网络无法通过直接Container-IP访问到容器。如果容器希望外部访问能够访问到，可以通过映射容器端口到宿主主机（端口映射），即docker run创建容器时候通过 -p 或 -P 参数来启用，访问容器的时候就通过[宿主机IP]:[容器端口]访问容器。

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/container-network.png)

## 3.2. 4类网络模式

| Docker网络模式  | 配置                         | 说明                                       |
| ----------- | -------------------------- | ---------------------------------------- |
| host模式      | --net=host                 | 容器和宿主机共享Network namespace。               |
| container模式 | --net=container:NAME_or_ID | 容器和另外一个容器共享Network namespace。 kubernetes中的pod就是多个容器共享一个Network namespace。 |
| none模式      | --net=none                 | 容器有独立的Network namespace，但并没有对其进行任何网络设置，如分配veth pair 和网桥连接，配置IP等。 |
| bridge模式    | --net=bridge（默认为该模式）       |                                          |

## 3.3. bridge模式

k8s只使用bridge模式。

在bridge模式下，Docker Daemon首次启动时会创建一个虚拟网桥docker0，地址通常为172.x.x.x开头，在私有的网络空间中给这个网络分配一个子网。由Docker创建处理的每个容器，都会创建一个虚拟以太设备（Veth设备对），一端关联到网桥，另一端使用Namespace技术映射到容器内的eth0设备，然后从网桥的地址段内给eth0接口分配一个IP地址。

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/bridge.png)

一般情况，宿主机IP与docker0 IP、容器IP是不同的IP段，默认情况，外部看不到docker0和容器IP，对于外部来说相当于docker0和容器的IP为内网IP。

# 4. kubernetes的网络实现

k8s网络场景

1. 容器与容器之间的直接通信。
2. Pod与Pod之间的通信。
3. Pod到Service之间的通信。
4. 集群外部与内部组件之间的通信。

## 4.1. Pod网络

Pod作为kubernetes的最小调度单元，Pod是容器的集合，是一个逻辑概念，Pod包含的容器都运行在同一个宿主机上，这些容器将拥有同样的网络空间，容器之间能够互相通信，它们能够在本地访问其它容器的端口。 实际上Pod都包含一个网络容器，它不做任何事情，只是用来接管Pod的网络，业务容器通过加入网络容器的网络从而实现网络共享。Pod网络本质上还是容器网络，所以Pod-IP就是网络容器的Container-IP。

一般将容器云平台的网络模型打造成一个扁平化网络平面，在这个网络平面内，Pod作为一个网络单元同Kubernetes Node的网络处于同一层级

## 4.2. 容器之间的通信

同一个Pod之间的不同容器因为共享同一个网络命名空间，所以可以直接通过localhost直接通信。

## 4.3. Pod之间的通信

### 4.3.1. 同Node的Pod之间的通信

同一个Node内，不同的Pod都有一个全局IP，可以直接通过Pod的IP进行通信。Pod地址和docker0在同一个网段。

### 4.3.2. 不同Node的Pod之间的通信

不同的Node之间，Node的IP相当于外网IP，可以直接访问，而Node内的docker0和Pod的IP则是内网IP，无法直接跨Node访问。需要通过Node的网卡进行转发。

所以不同Node之间的通信需要达到两个条件：

1. 对整个集群中的Pod-IP分配进行规划，不能有冲突（可以通过第三方开源工具来管理，例如flannel）。
2. 将Node-IP与该Node上的Pod-IP关联起来，通过Node-IP再转发到Pod-IP。

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/pod-network.png)

**1. Pod间实现通信**

   例如：Pod1和Pod2（同主机），Pod1和Pod3(跨主机)能够通信

   实现：因为Pod的Pod-IP是Docker网桥分配的，Pod-IP是同Node下全局唯一的。所以将不同Kubernetes Node的 Docker网桥配置成不同的IP网段即可。

**2. Node与Pod间实现通信**

   例如：Node1和Pod1/ Pod2(同主机)，Pod3(跨主机)能够通信

   实现：在容器集群中创建一个覆盖网络(Overlay Network)，联通各个节点，目前可以通过第三方网络插件来创建覆盖网络，比如Flannel和Open vSwitch等。

## 4.4. Service网络

Service的就是在Pod之间起到服务代理的作用，对外表现为一个单一访问接口，将请求转发给Pod，Service的网络转发是Kubernetes实现服务编排的关键一环。Service都会生成一个虚拟IP，称为Service-IP， Kuberenetes Porxy组件负责实现Service-IP路由和转发，在容器覆盖网络之上又实现了虚拟转发网络。

Kubernetes Porxy实现了以下功能：

1. 转发访问Service的Service-IP的请求到Endpoints(即Pod-IP)。
2. 监控Service和Endpoints的变化，实时刷新转发规则。
3. 负载均衡能力。

# 5. 开源的网络组件

## 5.1. Flannel

具体参考[Flannel介绍](http://blog.csdn.net/huwh_/article/details/77899108)

参考《Kubernetes权威指南》
