---
title: "Flannel介绍"
weight: 1
catalog: true
date: 2024-11-24 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
- CNI
catagories:
- Kubernetes
- CNI
---

# 1. Flannel简介

Flannel 是一个简单的、易于使用的 Kubernetes 网络插件，用于为容器集群提供网络功能。它主要解决的是 Kubernetes 集群中跨节点容器间通信的问题，通过为每个节点分配一个独立的子网，确保容器之间可以使用虚拟网络进行无障碍通信。

## 1.1. Flannel 的特点与优势

1. **`易于配置和使用`**
   - 提供简单的配置文件，易于集成到 Kubernetes 集群中。
   - 支持多种后端（如 VXLAN、host-gw、AWS VPC 等），灵活满足不同环境需求。
2. **`跨节点网络通信`**
   - 为每个节点分配独立的子网，容器之间使用虚拟网络 IP 直接通信，而无需 NAT。
3. **`轻量级设计`**
   - 运行时资源占用少，适合资源有限的环境。
4. **`稳定兼容性强`**
   - 支持多种 Linux 发行版，兼容 Kubernetes 和 Docker，适应广泛的容器化场景。
5. **`多后端支持`**
   - 提供 VXLAN、host-gw、AWS VPC、UDP 等多种网络后端，以适应不同场景和需求。

## 1.2. 使用场景

1. **中小规模 Kubernetes 集群**
   - Flannel 易于部署和管理，非常适合中小规模集群使用。
2. **跨节点容器通信**
   - 在需要容器间无障碍通信的场景中，Flannel 提供可靠的虚拟网络支持。
3. **非高性能敏感的场景**
   - 由于 Flannel 使用封包封装技术（如 VXLAN），在性能要求不是特别高的场景中非常适用。
4. **混合云/多云部署**
   - Flannel 的多后端支持和灵活配置，使其在多种基础设施中易于部署。


## 1.3. Flannel 的局限性

  尽管 Flannel 易用且轻量，但它也存在一些不足之处：

  1. **性能限制**
     - 使用 VXLAN 或 UDP 后端时，由于封包和解封包操作会消耗额外资源，网络性能可能不如直接路由的方案（如 Calico 的 BGP）。
     - 在高流量或低延迟场景下，Flannel 可能不是最佳选择。
  2. **缺乏高级网络功能**
     - 不支持网络策略（Network Policy）功能，无法实现细粒度的访问控制。
     - 对于需要复杂网络功能（如流量加密、多租户隔离）的场景，Calico 或 Cilium 是更好的选择。
  3. **依赖 etcd**
     - Flannel 强依赖于 etcd。如果 etcd 出现故障，可能影响网络管理和子网分配。
     - 需要额外注意 etcd 的高可用性和性能。
  4. **运维复杂度随着规模增长**
     - `随着集群规模扩大（如 1000+ 节点），Flannel 的资源消耗和配置复杂度可能增加，不如更高性能的网络方案`。

# 2. Flannel 的架构与配置

flannel的架构比较简单，只有每个节点一个的`flanneld`组件，通过`daemonset`部署，并没有跟calico或cilium的架构中有中控组件。其他组件则使用k8s的etcd。

1. **flanneld 组件**
   - 每个节点运行一个 flanneld 服务，负责管理该节点的网络配置和数据封包解封包。
2. **etcd 集成**
   - Flannel 使用 etcd 存储网络配置和子网分配信息。
   - 所有节点通过 etcd 协调分配网络资源。
3. **网络后端**
   - Flannel 支持多种后端技术，如 VXLAN、UDP、host-gw 等，可根据需求选择。
4. **Kubernetes 集成**
   - Flannel 通过 Kubernetes 的 CNI 插件接口无缝集成，确保与 Kubernetes 网络需求的兼容性。

## 2.1. 部署flannel

通过以下的yaml文件可以快速的部署flannel组件

```bash
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

部署完成后会生成默认配置：`kube-flannel-cfg`， 其中默认使用`vxlan`的后端模式。

```yaml
apiVersion: v1
kind: ConfigMap
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"  // 默认为vxlan的模式
      }
    }
```

## 2.2. 节点配置

在`/etc/cni/net.d`路径下会生成flannel的cni配置。

```yaml
{
  "name": "cbr0",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "flannel",
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    }
  ]
}
```

同时在节点会生成一个子网配置`/var/run/flannel/subnet.env`

```bash
FLANNEL_NETWORK=10.244.0.0/16  # 整个集群的Pod网段
FLANNEL_SUBNET=10.244.3.1/24   # 该节点的子网Pod网段
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
```

节点会生成`cni0`和`flannel.1`的网卡，其中`网卡的网段跟该节点的FLANNEL_SUBNET网段一致，如果不一致则需要重建网卡`。

- `flannel.1`：节点网关，10.244.3.0
- `cni0`: 10.244.3.1
- `FLANNEL_SUBNET`=10.244.3.1/24

```bash
cni0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
        inet 10.244.3.1  netmask 255.255.255.0  broadcast 10.244.3.255
        inet6 fe80::828:abff:fe83:34ac  prefixlen 64  scopeid 0x20<link>
        ether 0a:28:ab:83:34:ac  txqueuelen 1000  (Ethernet)
        RX packets 16220840959  bytes 2329280828193 (2.3 TB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 16382181068  bytes 43297103465563 (43.2 TB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
        
flannel.1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
        inet 10.244.3.0  netmask 255.255.255.255  broadcast 0.0.0.0
        inet6 fe80::d875:a3ff:fe8b:1e64  prefixlen 64  scopeid 0x20<link>
        ether da:75:a3:8b:1e:64  txqueuelen 0  (Ethernet)
        RX packets 225837271  bytes 33216374045 (33.2 GB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 204036495  bytes 396891087255 (396.8 GB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0        
```

# 3. Flannel网络原理

## 3.1. 原理图

![flannel](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578568/article/flannel/flannel.png)

> 图中docker0等价于cni0, flannel0等价于flannel.1网卡

**关键网卡和路由表的角色**

1. **`cni0` 网桥**
   - 是一个 Linux 网桥，连接同一节点上的所有 Pod 网络接口（`veth` 对）。
   - `将数据包从 Pod 转发到本地的其他 Pod` 或上交给 `flannel.1`。
2. **`flannel.1` 网卡**
   - 是一个虚拟网卡（VXLAN 接口），`用于封装和解封装跨节点的 Pod 数据包`。
   - 连接到物理网络，通过封装的方式将数据包发送到目标节点。
3. **`路由表`**
   - 定义了如何转发数据包，包括 Pod 子网的路由规则和默认路由。
   - Flannel 会在每个节点配置路由表，使得本地 Pod 的子网可以通过 `cni0` 访问，远程 Pod 的子网通过 `flannel.1` 访问。

## 3.2. 数据包路径

### 3.2.1. 数据包环境

假设有以下环境：

- **Node A**：子网 `10.244.1.0/24`，Pod1 的 IP 是 `10.244.1.2`。
- **Node B**：子网 `10.244.2.0/24`，Pod2 的 IP 是 `10.244.2.3`。
- 两个节点通过物理网络互联。

其中节点路由表信息如下：

A 节点（Pod IP：10.244.1.2）：

```bash
# 物理机路由
default via <物理机网关> dev bond0 proto static
<物理机目标网段> dev bond0 proto kernel scope link src <本机节点IP>
# flannel路由
10.244.0.0/24 via 10.244.0.0 dev flannel.1 onlink
10.244.1.0/24 dev cni0 proto kernel scope link src 10.244.1.1  #本地子网，直接通过 cni0 处理。
10.244.2.0/24 via 10.244.2.0 dev flannel.1 onlink # 远程子网，数据包通过 flannel.1 封装
```

B节点（Pod IP：10.244.2.3）：

```bash
# 物理机路由
default via <物理机网关> dev bond0 proto static
<物理机目标网段> dev bond0 proto kernel scope link src <本机节点IP>
# flannel路由
10.244.0.0/24 via 10.244.0.0 dev flannel.1 onlink
10.244.1.0/24 via 10.244.1.0 dev flannel.1 onlink    # 远程子网，数据包通过 flannel.1 封装
10.244.2.0/24 dev cni0 proto kernel scope link src 10.244.2.1  #本地子网，直接通过 cni0 处理。
```

### 3.2.1. 数据路径

**1. 从 Pod 发出的数据包**

**(1) Pod1 发送数据包**

- Pod1 发往 Pod2 的数据包：
  - **源 IP**：`10.244.1.2`
  - **目标 IP**：`10.244.2.3`
- 数据包通过 Pod1 的 `veth` 设备发送到本地的 `cni0` 网桥。

**2. cni0 网桥处理**

- **判断目标 IP 属于哪个子网**：
  - 本节点子网（`10.244.1.0/24`）：直接转发到对应的 `veth`。
  - 其他子网（`10.244.2.0/24`）：路由表指向 `flannel.1`。
- 在本例中，目标 IP 属于 `10.244.2.0/24`，因此数据包通过路由规则转发到 `flannel.1`。

**3. flannel.1 网卡封装**

**(1) 数据封装**

- Flannel 代理（`flanneld`）会检测目标子网属于远程节点，触发封装流程。
- 数据包封装为 VXLAN 包，外层 IP 标头：
  - **源 IP**：Node A 的物理 IP（例如 `192.168.1.1`）。
  - **目标 IP**：Node B 的物理 IP（例如 `192.168.1.2`）。
  - **VXLAN Header**：标记虚拟网络 ID 和其他信息。

**(2) 路由转发**

- 封装后的数据包通过主机的物理网卡（如 `eth0`）发送到目标节点。

**4. 到达目标节点 (Node B)**

**(1) flannel.1 接收数据包**

- Node B 的物理网卡接收封装的 VXLAN 数据包，交由 `flannel.1`。
- flannel.1 解封数据包，还原出原始的 Pod 数据包：
  - **源 IP**：`10.244.1.2`
  - **目标 IP**：`10.244.2.3`

**(2) 路由到 cni0**

- 根据路由表，目标子网 `10.244.2.0/24` 属于本节点，通过 `cni0` 转发数据包。
- `cni0` 根据目标 IP，找到 Pod2 的 `veth` 设备。

**5. 数据包到达目标 Pod**

- 数据包最终通过 `cni0` 网桥送到 Pod2 的 `veth` 接口，Pod2 接收到来自 Pod1 的通信。

### 3.2.3. 数据流总结

1. Pod1 数据包先进入本地的 `cni0` 网桥。
2. `cni0` 网桥通过路由表，发现目标 IP 属于其他子网，交由 `flannel.1`。
3. `flannel.1` 封装数据包，并通过物理网卡发往目标节点。
4. 目标节点的 `flannel.1` 解封数据包，交给 `cni0`。
5. `cni0` 网桥将数据包转发到目标 Pod 的 `veth`。

通过这种方式，不同节点的 Pod 实现了透明的互通。

# 4. 总结

Flannel是一个非常简单，稳定的CNI插件，其中部署和配置方式都非常简单，网络原理也简单，出现问题排查比较方便。特别适合k8s集群规模不大（1000个节点以内），网络性能要求不是非常严格，且团队中网络相关人员较少且无法支持维护复杂网络插件的团队使用。因为选择方案有一个基本的考虑点是该方案稳定且团队中有人可维护，而Flannel是一个维护成本相对比较低的网络方案。



参考：

- https://github.com/flannel-io/flannel