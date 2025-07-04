---
title: "Namespace介绍"
weight: 1
catalog: true
date: 2021-07-20 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Runtime
catagories:
- Runtime
---

# 1. Namespace简介

Namespace是内核的一个功能，用来给进程隔离一系列系统资源（视图隔离）。

# 2. 类别

| namespace类别     | 隔离资源                           | 系统调用参数  | 内核版本 | Docker中的例子   |
| ----------------- | ---------------------------------- | ------------- | -------- | ---------------- |
| Mount namespace   | 挂载点                             | CLONE_NEWNS   | 2.4.19   | 独立的挂载点     |
| UTS Namespace     | hostname和domainname               | CLONE_NEWUTS  | 2.6.19   | 独立的hostname   |
| IPC Namespace     | System V IPC, POSIX message queues | CLONE_NEWIPC  | 2.6.19   |                  |
| PID Namespace     | 进程ID                             | CLONE_NEWPID  | 2.6.24   | 容器进程PID为1   |
| Network Namespace | 网络设备，端口，网络栈             | CLONE_NEWNET  | 2.6.24   | 独立的网络和端口 |
| User Namespace    | 用户ID，group ID                   | CLONE_NEWUSER | 3.8      | 独立的用户ID     |

# 3. Namespace API

| API       | 说明                                                         |
| --------- | ------------------------------------------------------------ |
| clone()   | 基于某namespace创建新进程，他们的子进程也包含在该namespace中 |
| unshare() | 将进程移出某个namespace                                      |
| setns()   | 将进程加入某个namespace                                      |


# 4. namespace细分

## 4.1. Mount Namespace

Mount Namespace可以用了隔离各个进程的挂载点视图。不同的namespace中文件系统层次不一样，在其中调用mount和umount仅影响当前namespace。



## 4.2. Network Namespace

Network Namespace用来隔离网络设备，IP地址端口等网络栈。容器内可以绑定自己的端口，在宿主机建立网桥，就可以实现容器之间的通信。

ip netns 命令用来管理 network namespace。

```shell
# ip netns help
Usage: ip netns list
       ip netns add NAME
       ip netns set NAME NETNSID
       ip [-all] netns delete [NAME]
       ip netns identify [PID]
       ip netns pids NAME
       ip [-all] netns exec [NAME] cmd ...
       ip netns monitor
       ip netns list-id
```

示例：

模拟创建docker0及docker网络

1、创建lxcbr0，相当于docker0

```shell
# 添加一个网桥lxcbr0,相当于docker0
brctl addbr lxcbr0
brctl stp lxcbr0 off
ifconfig lxcbr0 192.168.10.1/24 up  # 配置网桥IP地址

# 查看网桥
# ifconfig
lxcbr0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.10.1  netmask 255.255.255.0  broadcast 192.168.10.255
        inet6 fe80::94cb:eaff:fe48:cdd5  prefixlen 64  scopeid 0x20<link>
        ether 96:cb:ea:48:cd:d5  txqueuelen 1000  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 5  bytes 426 (426.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

 添加网络命名空间

```bash
# 添加网络命名空间ns1
ip netns add ns1
# 激活namespace中的loopback，即127.0.0.1
ip netns exec ns1   ip link set dev lo up 
```

3、添加虚拟网卡

```bash
# 增加一个pair虚拟网卡，注意其中的veth类型，其中一个网卡要按进容器中
ip link add veth-ns1 type veth peer name lxcbr0.1
# 把 veth-ns1 按到namespace ns1中，这样容器中就会有一个新的网卡了
ip link set veth-ns1 netns ns1
```

4、修改容器内网卡为eth0，并分配IP

```bash
# 把容器里的 veth-ns1改名为 eth0 （容器外会冲突，容器内就不会了）
ip netns exec ns1  ip link set dev veth-ns1 name eth0 
# 为容器中的网卡分配一个IP地址，并激活它
ip netns exec ns1 ifconfig eth0 192.168.10.11/24 up
```

5、将lxcbr0.1添加上网桥

```bash
# 上面我们把veth-ns1这个网卡按到了容器中，然后我们要把lxcbr0.1添加上网桥上
brctl addif lxcbr0 lxcbr0.1
```

6、添加路由

```bash
# 为容器增加一个路由规则，让容器可以访问外面的网络
ip netns exec ns1     ip route add default via 192.168.10.1
```

7、添加nameserver

```bash
# 在/etc/netns下创建network namespce名称为ns1的目录，
# 然后为这个namespace设置resolv.conf，这样，容器内就可以访问域名了
mkdir -p /etc/netns/ns1
echo "nameserver 8.8.8.8" > /etc/netns/ns1/resolv.conf
```

8、查看网络空间内的网络配置

```bash
# 进入网络命名空间
ip netns exec ns1 bash
# 查看网络配置
ifconfig
eth0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 192.168.10.11  netmask 255.255.255.0  broadcast 192.168.10.255
        ether 2a:0c:a8:b7:bc:32  txqueuelen 1000  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        inet6 ::1  prefixlen 128  scopeid 0x10<host>
        loop  txqueuelen 1000  (Local Loopback)
        RX packets 4  bytes 240 (240.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 4  bytes 240 (240.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```
9、进入现有docker容器的网络命名空间

由于docker默认隐藏了`/var/run/netns`下的命名空间，因此需要做软链接，容器的1号进程的pid下的ns软链到`/var/run/netns`。

```bash
ln -sf /proc/<container-pid>/ns/net "/var/run/netns/<container-id>"
ip netns exec <container-id> bash
```

参考：

- https://lwn.net/Articles/531114/
- https://coolshell.cn/articles/17010.html
- https://coolshell.cn/articles/17029.html