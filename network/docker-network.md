# 1. Docker的网络基础

## 1.1. Network Namespace

不同的网络命名空间中，协议栈是独立的，完全隔离，彼此之间无法通信。同一个网络命名空间有独立的路由表和独立的Iptables/Netfilter来提供包的转发、NAT、IP包过滤等功能。

### 1.1.1. 网络命名空间的实现

将与网络协议栈相关的全局变量变成一个Net Namespace变量的成员，然后在调用协议栈函数中加入一个Namepace参数。

### 1.1.2. 网络命名空间的操作

1、创建网络命名空间

ip netns add <name>

2、在命名空间内执行命令

ip netns exec <name> <command>

3、进入命名空间

ip netns exec <name> bash

# 2. Docker的网络实现

## 2.1. 容器网络

Docker使用Linux桥接，在宿主机虚拟一个Docker容器网桥(docker0)，Docker启动一个容器时会根据Docker网桥的网段分配给容器一个IP地址，称为Container-IP，同时Docker网桥是每个容器的默认网关。因为在同一宿主机内的容器都接入同一个网桥，这样容器之间就能够通过容器的Container-IP直接通信。

Docker网桥是宿主机虚拟出来的，并不是真实存在的网络设备，外部网络是无法寻址到的，这也意味着外部网络无法通过直接Container-IP访问到容器。如果容器希望外部访问能够访问到，可以通过映射容器端口到宿主主机（端口映射），即docker run创建容器时候通过 -p 或 -P 参数来启用，访问容器的时候就通过[宿主机IP]:[容器端口]访问容器。

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/container-network.png)

## 2.2. 4类网络模式

| Docker网络模式  | 配置                         | 说明                                       |
| ----------- | -------------------------- | ---------------------------------------- |
| host模式      | --net=host                 | 容器和宿主机共享Network namespace。               |
| container模式 | --net=container:NAME_or_ID | 容器和另外一个容器共享Network namespace。 kubernetes中的pod就是多个容器共享一个Network namespace。 |
| none模式      | --net=none                 | 容器有独立的Network namespace，但并没有对其进行任何网络设置，如分配veth pair 和网桥连接，配置IP等。 |
| bridge模式    | --net=bridge（默认为该模式）       |                                          |

## 2.3. bridge模式

k8s只使用bridge模式。

在bridge模式下，Docker Daemon首次启动时会创建一个虚拟网桥docker0，地址通常为172.x.x.x开头，在私有的网络空间中给这个网络分配一个子网。由Docker创建处理的每个容器，都会创建一个虚拟以太设备（Veth设备对），一端关联到网桥，另一端使用Namespace技术映射到容器内的eth0设备，然后从网桥的地址段内给eth0接口分配一个IP地址。

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/bridge.png)

一般情况，宿主机IP与docker0 IP、容器IP是不同的IP段，默认情况，外部看不到docker0和容器IP，对于外部来说相当于docker0和容器的IP为内网IP。
