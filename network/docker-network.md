# 1. Docker的网络基础

## 1.1. Network Namespace

不同的网络命名空间中，协议栈是独立的，完全隔离，彼此之间无法通信。同一个网络命名空间有独立的路由表和独立的`Iptables/Netfilter`来提供包的转发、NAT、IP包过滤等功能。

### 1.1.1. 网络命名空间的实现

将与网络协议栈相关的全局变量变成一个`Net Namespace`变量的成员，然后在调用协议栈函数中加入一个Namepace参数。

### 1.1.2. 网络命名空间的操作

1、创建网络命名空间

ip netns add `name`

2、在命名空间内执行命令

ip netns exec `name` `command`

3、进入命名空间

ip netns exec `name` bash

# 2. Docker的网络实现

## 2.1. 容器网络

Docker使用Linux桥接，在宿主机虚拟一个Docker容器网桥(docker0)，Docker启动一个容器时会根据Docker网桥的网段分配给容器一个IP地址，称为Container-IP，同时Docker网桥是每个容器的默认网关。因为在同一宿主机内的容器都接入同一个网桥，这样容器之间就能够通过容器的Container-IP直接通信。

Docker网桥是宿主机虚拟出来的，并不是真实存在的网络设备，外部网络是无法寻址到的，这也意味着外部网络无法通过直接Container-IP访问到容器。如果容器希望外部访问能够访问到，可以通过映射容器端口到宿主主机（端口映射），即docker run创建容器时候通过 -p 或 -P 参数来启用，访问容器的时候就通过[宿主机IP]:[容器端口]访问容器。

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/container-network.png)

## 2.2. 4类网络模式

| Docker网络模式 | 配置                         | 说明                                                         |
| -------------- | ---------------------------- | ------------------------------------------------------------ |
| host模式       | --net=host                   | 容器和宿主机共享Network namespace。                          |
| container模式  | --net=container:NAME_or_ID   | 容器和另外一个容器共享Network namespace。 kubernetes中的pod就是多个容器共享一个Network namespace。 |
| none模式       | --net=none                   | 容器有独立的Network namespace，但并没有对其进行任何网络设置，如分配veth pair 和网桥连接，配置IP等。 |
| bridge模式     | --net=bridge（默认为该模式） | 桥接模式                                                     |

# 3. Docker网络模式

## 3.1. bridge桥接模式

在bridge模式下，Docker可以使用独立的网络栈。实现方式是父进程在创建子进程的时候通过传入`CLONE_NEWNET`的参数创建出一个网络命名空间。

**实现步骤：**

1. Docker Daemon首次启动时会创建一个虚拟网桥docker0，地址通常为172.x.x.x开头，在私有的网络空间中给这个网络分配一个子网。
2. 由Docker创建处理的每个容器，都会创建一个虚拟以太设备对（veth pair），一端关联到网桥，另一端使用Namespace技术映射到容器内的eth0设备，然后从网桥的地址段内给eth0接口分配一个IP地址。

![这里写图片描述](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578957/article/kubernetes/network/bridge.png)

一般情况，宿主机IP与docker0 IP、容器IP是不同的IP段，默认情况，外部看不到docker0和容器IP，对于外部来说相当于docker0和容器的IP为内网IP。

### 3.1.1. 外部网络访问Docker容器

外部访问docker容器可以通过`端口映射(NAT)`的方式，Docker使用NAT的方式将容器内部的服务与宿主机的某个端口port_1绑定。

外部访问容器的流程如下：

1. 外界网络通过宿主机的IP和映射的端口port_1访问。
2. 当宿主机收到此类请求，会通过DNAT将请求的目标IP即宿主机IP和目标端口即映射端口port_1替换成容器的IP和容器的端口port_0。
3. 由于宿主机上可以识别容器IP，所以宿主机将请求发给veth pair。
4. veth pair将请求发送给容器内部的eth0，由容器内部的服务进行处理。

### 3.1.2. Docker容器访问外部网络

docker容器访问外部网络的流程：

1. docker容器向外部目标IP和目标端口port_2发起请求，请求报文中的源IP为容器IP。

2. 请求通过容器内部的eth0到veth pair的另一端docker0网桥。

3. docker0网桥通过数据报转发功能将请求转发到宿主机的eth0。

4. 宿主机处理请求时通过SNAT将请求中的源IP换成宿主机eth0的IP。

5. 处理后的报文通过请求的目标IP发送到外部网络。

### 3.1.3. 缺点

   使用NAT的方式可能会带来性能的问题，影响网络传输效率。

## 3.2. host模式

host模式并没有给容器创建一个隔离的网络环境，而是和宿主机共用一个网络命名空间，容器使用宿主机的eth0和外界进行通信，同样容器也共用宿主机的端口资源，即分配端口可能存在与宿主机已分配的端口冲突的问题。

实现的方式即父进程在创建子进程的时候不传入`CLONE_NEWNET`的参数，从而和宿主机共享一个网络空间。

host模式没有通过NAT的方式进行转发因此性能上相对较好，但是不存在网络隔离性，可能产生端口冲突的问题。

## 3.3. container模式

container模式即docker容器可以使用其他容器的网络命名空间，即和其他容器处于同一个网络命名空间。

步骤：

1. 查找其他容器的网络命名空间。
2. 新创建的容器的网络命名空间使用其他容器的网络命名空间。

通过和其他容器共享网络命名空间的方式，可以让不同的容器之间处于相同的网络命名空间，可以直接通过localhost的方式进行通信，简化了强关联的多个容器之间的通信问题。

k8s中的pod的概念就是通过一组容器共享一个网络命名空间来达到pod内部的不同容器可以直接通过localhost的方式进行通信。

## 3.4. none模式

none模式即不为容器创建任何的网络环境，用户可以根据自己的需要手动去创建不同的网络定制配置。



参考：

- 《Docker源码分析》