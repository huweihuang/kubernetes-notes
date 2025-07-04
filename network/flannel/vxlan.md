---
title: "VXLAN原理介绍"
weight: 2
catalog: true
date: 2024-12-01 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
- CNI
catagories:
- Kubernetes
- CNI
---


# 1. VXLAN简介

VXLAN（Virtual Extensible LAN）是一种网络虚拟化技术，旨在解决传统二层网络扩展的局限性，尤其是在数据中心大规模部署中。它通过隧道技术将二层以太网帧封装在三层UDP包中，实现了跨三层网络的二层网络延展。

## 1.1. VXLAN的基本概念

- **目的**：解决二层网络扩展的问题，例如VLAN的数量限制（传统VLAN ID 只能支持4096（2的12次方）个）。
- **封装协议**：VXLAN将二层以太网帧封装为UDP数据包（即VXLAN隧道）。
- VXLAN网络标识：
  - VXLAN使用24位的**VXLAN网络标识（VNI，Virtual Network Identifier）**，支持多达**16,777,216**（2的24次方）个虚拟网络。
  - 每个VNI对应一个虚拟的二层广播域（类似于传统的VLAN）。

## 1.2.VXLAN应用场景

- **多租户数据中心**：为不同租户提供逻辑隔离的虚拟网络。
- **混合云和跨数据中心连接**：扩展二层网络到不同位置的数据中心。
- `容器网络：在Kubernetes等平台上，用VXLAN构建跨节点的Pod网络`。

## 1.3. VXLAN的优点

- 可扩展性：
  - 支持大量虚拟网络（16M）。
  - 跨三层网络扩展二层网络，适用于大规模数据中心。
- **网络隔离**：通过VNI实现网络隔离，适合多租户场景。
- **灵活性**：VXLAN在IP网络中运行，不依赖底层的物理拓扑。

------

## 1.4. VXLAN的局限性

- **性能开销**：封装和解封装增加了CPU负载，尤其是在软件实现中。
- **复杂性**：需要额外配置VTEP和三层网络，维护成本较高。
- **MTU问题**：VXLAN封装增加了数据包长度，可能需要调整网络的MTU（通常为1600字节或更大）。

# 2. VXLAN的原理

## 2.1. VXLAN的关键组成

- **`VTEP（VXLAN Tunnel Endpoint）`** ：
  - VTEP是VXLAN隧道的起点和终点，用于封装和解封装VXLAN数据包。
  - 通常运行在物理交换机或虚拟机主机的网卡上。
  - 包括两个接口：
    - **本地接口**：连接到二层网络。
    - **隧道接口**：连接到三层网络。
- **`VXLAN头`** ：
  - VXLAN头插入到原始以太网帧和UDP头之间。
  - VXLAN头包含VNI等信息，用于区分不同的虚拟网络。
- **`UDP头`** ：
  - VXLAN数据包封装在UDP中，以便通过三层网络传输。
  - `默认使用UDP端口号4789`。
  - `确保iptables规则中该UDP端口是放开的`。

## 2.2. VXLAN的工作原理

VXLAN通过以下步骤实现跨三层网络的二层通信：

**`1. 数据包封装`**

1. VTEP捕获本地虚拟机（VM）的以太网帧。
2. VTEP在帧上封装：
   - 添加VXLAN头，用于标识VNI。
   - `添加UDP头，便于三层网络传输`。
   - 添加外层IP头和MAC头，用于在三层网络中寻址。

**`2. 数据包传输`**

1. `封装后的数据包通过三层网络传输到目标VTEP`。
2. `传输过程中使用三层网络的路由功能，可以跨越不同的子网`。

**`3. 数据包解封装`**

1. 目标VTEP接收到VXLAN数据包后，解析外层IP头。
2. 检查VNI，将数据包解封装回原始二层以太网帧。
3. 将解封装后的帧转发到目标虚拟机。

# 3.  VLAN 和 VXLAN 的区别

| **特性**         | **VLAN**                                        | **VXLAN**                                     |
| ---------------- | ----------------------------------------------- | --------------------------------------------- |
| **定义**         | 二层网络分段技术，通过 802.1Q 标准实现。        | 二层覆盖网络技术，通过三层网络扩展二层网络。  |
| **标准**         | IEEE 802.1Q                                     | IETF RFC 7348                                 |
| **隔离方式**     | 通过 12 位 VLAN ID 标记帧，实现二层广播域隔离。 | 通过 24 位 VXLAN ID（VNI）实现隔离。          |
| **支持网络数量** | 最多 4096 个 VLAN                               | 超过 1600 万个虚拟网络                        |
| **封装方式**     | 在以太网帧中添加 4 字节 VLAN Tag。              | 在以太网帧外封装 UDP，增加 IP 和 VXLAN 标头。 |
| **网络边界**     | 限于局域网，依赖物理拓扑。                      | 基于三层网络，支持跨地域、跨数据中心连接。    |
| **性能**         | 性能高，硬件交换机对 VLAN 支持成熟。            | 封装和解封装增加开销，但灵活性更强。          |
| **适用场景**     | 中小型网络，局域网内的简单隔离需求。            | 大规模云环境，多租户数据中心，跨地域网络。    |
| **复杂性**       | 配置简单，维护容易。                            | 配置复杂，需要支持 VXLAN 的设备。             |
| **硬件依赖**     | 广泛支持，几乎所有交换机都支持。                | 需要支持 VXLAN 的设备或软件实现。             |
| **广播域扩展**   | 广播域较大，不适合大规模网络。                  | 通过三层网络扩展二层广播域。                  |

# 4. Flannel VXLAN 的基本原理

Flannel 是 Kubernetes 中常用的网络插件之一，用于实现容器跨节点的网络通信。它支持多种网络后端，其中 **VXLAN 后端** 是一种常用的选择，利用 VXLAN 隧道实现不同节点的容器网络互通。

Flannel 使用 VXLAN 创建一个虚拟的二层网络，把位于不同节点上的容器子网连接起来。这些子网统一组成一个逻辑上的扁平网络，使得容器可以使用 Pod IP 直接互通。

在 VXLAN 模式下：

- **每个节点**分配一个独立的子网（例如 `/24`），该子网中的 IP 地址分配给该节点上的 Pod。
- **VXLAN 隧道**用于在不同节点之间封装和传输数据包。

## 4.1. Flannel VXLAN 的关键组件

1. **etcd / Kubernetes API**：
   - Flannel 使用 etcd 或 Kubernetes API 作为存储，保存每个节点的子网分配信息。
   - 例如，节点 A 的子网是 `10.1.1.0/24`，节点 B 的子网是 `10.1.2.0/24`。
2. **flanneld 进程**：
   - 每个节点运行 flanneld，负责：
     - 从 etcd 获取子网信息。
     - 配置 VXLAN 设备。
     - 管理路由规则。
3. **VXLAN 设备**：
   - `Flannel 在每个节点上创建一个 VXLAN 虚拟网络接口`（如 `flannel.1`）。
   - 通过这个接口，将数据包封装到 VXLAN 隧道中。

## 4.2. Flannel VXLAN 的通信流程

### 4.2.1. Pod 到 Pod 通信示例

假设 Pod1 在节点 A，Pod2 在节点 B，Pod1 的 IP 为 `10.1.1.2`，Pod2 的 IP 为 `10.1.2.3`：

1. **数据包生成**：
   - Pod1 想要与 Pod2 通信，发送一个 IP 数据包，目标地址是 `10.1.2.3`。
2. **节点路由查找**：
   - 节点 A 的路由表根据目标 IP (`10.1.2.3`)，发现其子网 `10.1.2.0/24`属于节点 B。
   - 数据包被转发到 VXLAN 设备 `flannel.1`。
3. **VXLAN 封装**：
   - 在 flannel.1上，数据包被封装：
     - 原始 IP 数据包被作为 VXLAN 的有效载荷。
     - VXLAN 头部和外层 UDP/IP 头部被添加。
     - 外层 IP 头的目标地址是节点 B 的物理 IP 地址。
4. **跨网络传输**：
   - 封装后的数据包通过底层三层网络（通常是宿主机的物理网卡）发送到节点 B。
5. **解封装和转发**：
   - 节点 B 的 VXLAN 设备接收到数据包后，解封装外层头部，还原出原始 IP 数据包。
   - 节点 B 根据路由规则将数据包转发给 Pod2。

### 4.2.2. 路由和 ARP 的处理

- **路由表**：

  - Flannel 会在每个节点配置路由规则，将目标子网与相应的 VXLAN 隧道设备关联。

  - 例如：

```bash
10.1.2.0/24 via 192.168.1.2 dev flannel.1
```

- **ARP 处理**：

  - VXLAN 需要知道远程节点的物理 IP 地址。
  - Flannel 在 VXLAN 模式下通过 etcd 或 Kubernetes API 维护节点的 IP 映射关系，而不是依赖传统的 ARP。

# 5. Flannel VXLAN报文解析

通过vxlan隧道传输需要封vxlan包和解vxlan包，以下描述vxlan报文内容。

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1733194201/article/kubernetes/network/flannel/vxlan.png)

## 5.1. VXLAN 报文结构

Flannel 的 VXLAN 报文可以分为以下几个主要部分：

| **字段**                | **描述**                                                     |
| ----------------------- | ------------------------------------------------------------ |
| **外层以太网头**        | 用于传输 VXLAN 报文的物理网络的 MAC 地址。                   |
| **外层 IP 头**          | 用于三层传输，包含源 IP（本地物理机）和目的 IP（目标物理机）。 |
| **UDP 头**              | 用于封装 VXLAN 流量，通常使用 VXLAN 的默认端口 4789。        |
| **VXLAN 标头**          | 包含 VXLAN 的关键信息，例如 VNI（虚拟网络标识）。            |
| **内层以太网头**        | 原始的以太网帧头，用于容器或 Pod 之间通信。                  |
| **内层数据（Payload）** | 实际的应用层数据，例如 HTTP、TCP 或 ICMP 数据。              |

示例：

```bash
+-----------------------------+
| 外层以太网头                 | MAC 源地址 | MAC 目的地址 | 类型 |
+-----------------------------+
| 外层 IP 头                   | 源 IP 地址 | 目的 IP 地址 | 协议|
+-----------------------------+
| UDP 头                       | 源端口 | 目的端口  | 长度 |
+-----------------------------+
| VXLAN 标头                   | Flag | Reserved | VNI      |
+-----------------------------+
| 内层以太网头                 | 源 MAC 地址 | 目的 MAC 地址 |
+-----------------------------+
| 内层数据（Payload）           | 实际的数据内容            |
+-----------------------------+
```

## 5.2. 报文详细解析

**1. 外层以太网头**

- **作用**：用于承载 VXLAN 报文的实际网络传输。
- 内容：
  - **源 MAC 地址**：发送报文的物理网卡的 MAC 地址。
  - **目的 MAC 地址**：目标主机的物理网卡的 MAC 地址。

**2. 外层 IP 头**

- **作用**：在三层网络中将 VXLAN 报文路由到目标主机。
- 内容：
  - **源 IP 地址**：发送报文的物理主机的 IP 地址。
  - **目的 IP 地址**：目标主机的 IP 地址。
  - **协议类型**：UDP。

**3. UDP 头**

- **作用**：封装 VXLAN 数据。
- 内容：
  - **源端口**：动态分配的随机端口。
  - **目的端口**：VXLAN 的端口，例如 `8472`（可以在 Flannel 配置中自定义）。
  - **长度和校验和**：用于确保 UDP 报文的完整性。

**4. VXLAN 标头**

- **作用**：标识虚拟网络以及对 VXLAN 流量进行必要的控制。
- 格式：
  - **Flag**：8 位，标识是否启用 VXLAN 功能，通常为 `0x08`。
  - **VNI（Virtual Network Identifier）**：24 位，标识 VXLAN 所属的虚拟网络。
  - **Reserved**：用于对齐和扩展，通常为 0。

**5. 内层以太网头**

- **作用**：封装原始的以太网帧，用于容器或 Pod 之间的二层通信。
- 内容：
  - **源 MAC 地址**：发送容器或 Pod 的 MAC 地址。
  - **目的 MAC 地址**：目标容器或 Pod 的 MAC 地址。

**6. 内层数据（Payload）**

- **作用**：实际的用户数据。
- 内容：
  - **数据类型**：可以是 IP 数据包（例如 TCP、UDP 或 ICMP），也可能是 ARP 等协议。

## 5.3. 报文的捕获

可以通过命令`ip -d link show flannel.1`查看`vxlan id（VNI） `，`vxlan端口`，vxlan基于的物理网卡。

例如，以下查询到`vxlan id(VNI)为1`，`vxlan端口为8472`，基于的物理网卡是bond0。

```bash
# ip -d link show flannel.1
10: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN mode DEFAULT group default
    link/ether xxxxxx brd xxxxx promiscuity 0 minmtu 68 maxmtu 65535
    vxlan id 1 local xxxxxxx dev bond0 srcport 0 0 dstport 8472 nolearning ttl auto ageing 300 udpcsum noudp6zerocsumtx noudp6zerocsumrx addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
```

使用 `tcpdump`，在物理网卡上捕获 VXLAN 报文， 协议是UDP，添加vxlan的端口。

```bash
tcpdump -i bond0 udp port 8472 -vv
```

# 6. 如何避免VXLAN冲突

在同一台物理机上如果存在其他设备（例如：弹性外网EIP设备）使用了VXLAN的隧道技术，可能与Flannel的VXLAN设备存在冲突，以下是冲突的可能性、原因及解决方法：

## 6.1. 可能存在的冲突

**`1. UDP 端口冲突`**

- VXLAN 通常使用 **UDP 端口 4789** 进行封装传输。如果弹性外网 IP 的 VXLAN 实现和 Flannel （默认端口8472）都使用相同的 UDP 端口，那么会导致端口冲突，使得其中一个功能失效。

**`2. VNI (VXLAN Network Identifier) 冲突`**

- VXLAN 的每个虚拟网络通过 **VNI**（24 位）进行区分。
- 如果弹性外网 IP 和 Flannel 的 VXLAN 使用了相同的 VNI，则可能导致 VXLAN 隧道之间的隔离性失效，造成数据包混乱。

**`3. 路由或设备名冲突`**

- 两者都会在物理机上创建 VXLAN 设备（如 `vxlan0` 或 `flannel.1`），如果设备名称相同，可能导致配置混乱。
- 路由表可能同时存在与 VXLAN 隧道相关的规则，如果路由目标网络有重叠，可能导致流量被错误转发。

## 6.2. 冲突的解决方法

**1. 避免 UDP 端口冲突**

- 确认弹性外网 IP 的 VXLAN 端口号。
- 自定义Flannel的VXLAN 端口号。确保两者使用不同的端口号。

**2. 避免 VNI 冲突**

- 确认弹性外网 IP 的 VXLAN 实现是否允许指定 VNI。如果允许，则为两者设置不同的 VNI 范围。
- **Flannel VNI** 通常由其内部管理，自动分配，但可以在配置文件中指定范围或固定值。

**3. 避免设备名冲突**

- **Flannel** 默认设备名是 `flannel.1`，一般非flannel的设备不会设置为该名称。
- 确保弹性外网 IP 的 VXLAN 设备名不同，或显式指定设备名称。

**4. 路由隔离**

- `仔细检查路由表，确保两者的目标子网范围没有重叠`。

如果要修改flannel的冲突参数，可以修改配置文件。

`kubectl edit cm -n kube-flannel kube-flannel-cfg`

```json
{
  "Network": "10.244.0.0/16",
  "Backend": {
    "Type": "vxlan",
    "VNI": 1, # 默认值
    "Port": 8472  # 默认值
  }
}
```

## 6.3. 查看设备的VXLAN

可以使用以下命令列出所有 VXLAN 接口：

```bash
# ip link show type vxlan
# 输出
6: vxlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 ...
7: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 ...
```

可以查看 VXLAN 接口的配置信息：

```bash
# ip -d link show <vxlan_interface>
6: vxlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether 06:42:ae:ff:fe:90 brd ff:ff:ff:ff:ff:ff promiscuity 0
    vxlan id 42 local 192.168.1.10 dev eth0 port 4789 0
    ...
# vxlan id 42：表示 VXLAN 的 VNI（Virtual Network Identifier）是 42。
# port 4789：表示 VXLAN 使用的 UDP 端口是 4789（默认端口）。
```

如果 VXLAN 接口绑定到了桥接设备（bridge），可以通过 `bridge` 命令查询详细信息。

```bash
bridge fdb show dev <vxlan_interface>
# 输出
00:00:00:00:00:13 dst x.x.x.x self permanent
```

# 7. 总结

本文主要介绍了VXLAN的基本概念和原理，报文解析以及在Flannel中的使用。除了Flannel外，在Calico和Cilium的网络插件中也涉及到VXLAN的使用，基本原理类似，大同小异。通过本文的介绍，帮助读者对于其他场景下使用VXLAN的方式也能够快速理解，并且可以快速排查VXLAN相关的网络问题。



参考：

- https://datatracker.ietf.org/doc/html/rfc7348
- https://github.com/flannel-io/flannel/blob/master/Documentation/backends.md
