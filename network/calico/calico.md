---
title: "Calico介绍"
weight: 1
catalog: true
date: 2024-10-26 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
- CNI
catagories:
- Kubernetes
- CNI
---

# 1. Calico简介

**Calico** 是一个开源的网络和网络安全解决方案，主要用于 Kubernetes 等容器编排系统。它通过提供高效的网络连接和强大的安全控制来满足容器化和微服务架构的需求。Calico 以其灵活性、可扩展性和性能著称，是许多企业和云原生应用的首选网络插件。

## 1.1. 主要功能和特点

1. **网络架构**：
   
   - **L3 路由架构**：Calico 基于第三层（L3）网络构建，不依赖传统的覆盖网络（overlay network），使其可以利用 IP 路由来实现跨节点的直接通信。
   - **BGP 支持**：Calico 使用 BGP（边界网关协议）来分发和同步路由信息，使得容器和 Pod 能够跨节点直接通信，减少网络延迟，提升性能。
   - **支持多种后端**：除了默认的 IP 路由模式，Calico 也支持 VXLAN、IPIP、WireGuard 和 eBPF 后端，适应不同的网络环境和需求。

2. **网络安全**：
   
   - **网络策略**：Calico 支持标准的 Kubernetes NetworkPolicy，用户可以通过策略控制 Pod 之间的通信权限。
   - **GlobalNetworkPolicy**：Calico 提供 GlobalNetworkPolicy，可以实现跨命名空间、跨集群的统一策略管理，用于多租户隔离或更高的安全控制。
   - **支持 eBPF**：Calico 在启用 eBPF 模式时，可以通过 eBPF 提供更高效的网络数据处理，并支持 L4 层的负载均衡和网络策略控制。

3. **可观测性和可视化**：
   
   - Calico 集成了多种可观测性工具，支持 Prometheus 等监控系统，并可以生成网络流量和策略的监控指标，帮助运维人员了解网络状况。
   - 支持与 EFK（Elasticsearch, Fluentd, Kibana）集成，便于可视化网络流量和策略。

4. **高扩展性**：
   
   - Calico 可以在不同的基础设施中运行，包括本地数据中心和云平台（AWS、GCP、Azure），并支持与 VM 及裸金属服务器互联。
   - 使用 IP 路由和 BGP，使得 Calico 在大规模集群中也能保持良好的性能和扩展性。

## 1.2. 适用场景

- **容器化应用的网络管理**：适用于 Kubernetes 等容器编排平台，为容器提供高效、安全的网络连接。
- **混合云和多集群部署**：Calico 支持跨数据中心和云环境的多集群部署，非常适合混合云和多租户环境。
- **网络安全**：对于需要细粒度的网络安全策略控制和多租户隔离的场景，Calico 提供多层次的安全控制和隔离。

## 1.3. Calico的局限性

calico也存在一些不足和局限性。

**`1. 对网络拓扑的依赖`**

- **BGP 配置复杂性**：
  Calico 默认使用 BGP 协议进行路由，如果网络环境中没有现成的 BGP 支持（如非生产环境或网络管理员经验不足），配置可能较复杂。此外，BGP 的管理对部分运维人员有一定门槛。
- **对底层网络要求较高**：
  Calico 的无隧道设计依赖底层网络的正常运行。如果底层网络不支持高效的路由或不能很好地管理多播流量，可能会影响整体网络性能。

------

**`2. 大规模集群性能问题`**

- **etcd 负载**：
  在大规模 Kubernetes 集群中（如几千个节点），Calico 对 etcd 的访问频率较高，这可能会给 etcd 带来较大压力。尽管 Typha 可以缓解部分问题，但依然可能成为瓶颈。
- **路由表膨胀**：
  在大规模集群中，BGP 模式下每个节点需要维护大量路由信息（与集群中 Pod 的数量相关），可能导致路由表膨胀并对内存和 CPU 资源产生较大压力。

# 2. Calico架构图

> 来自官网

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1693626884/article/calico/calico-architecture.png" title="" alt="" width="1046">

## 2.1. Calico 架构概览

Calico 通过 BGP（边界网关协议）在 Kubernetes 集群节点之间进行路由广播，无需使用复杂的隧道协议（如 VXLAN 或 GRE），这使得 Calico 的网络性能较高。它主要由以下组件组成：

1. **calico-node**：这是 Calico 的核心组件，运行在每个节点上，负责设置路由、管理 IP 地址，并通过 Felix 实现网络策略的执行。
2. **BGP Daemon (Bird)**：负责节点之间的路由传播，以实现不同节点 Pod 之间的流量路由。
3. **Felix**：作为 Calico 的主代理，负责监控 etcd 中存储的网络策略并将其应用于节点的网络接口，同时负责设置 IP 路由、管理 ACLs 以确保流量符合策略。
4. **Typha**：当节点数较多时，可以通过 Typha 组件来减少 etcd 的访问负载。它会将 etcd 中的策略变化缓存起来，并同步给每个节点的 Felix 代理。
5. **etcd**：Calico 使用 etcd 作为存储后端，用于存储网络策略、IP 池等配置。也可以使用 Kubernetes 的 API Server 作为存储后端，便于集成。

## 2.2. Calico 的核心组件

- **calicoctl**：这是 Calico 提供的命令行工具，用于配置和管理 Calico 的资源，比如 IP 池、策略、网络设置等。可以通过该工具查看、创建、更新和删除网络策略。
- **IPAM (IP Address Management)**：Calico 自带的 IP 地址管理模块，可以为集群中的 Pod 自动分配 IP 地址。IPAM 支持灵活的 IP 池设置，可以对不同的节点、命名空间或工作负载分配特定的 IP 范围。

## 2.3. 工作流程

- 每个节点上运行的 calico-node 组件会和其他节点进行 BGP 路由信息交换，确保不同节点的 Pod 可以互相通信。
- Felix 组件负责将网络策略的定义应用到实际的网络接口上，以确保流量符合预设的策略。
- Typha 组件在大规模集群中可以有效地减少 etcd 的压力，帮助 Felix 快速同步网络策略。

## 2.4. Calico 网络策略 (Network Policy)

Calico 支持丰富的网络策略，用于定义不同的 Pod 或服务之间的网络访问规则。网络策略的主要功能包括：

- **基于标签的策略**：可以根据 Pod 或命名空间的标签来控制网络流量的允许和拒绝。
- **支持 Egress 和 Ingress 策略**：不仅可以控制进入 Pod 的流量，还可以控制 Pod 发出的流量。
- **灵活的规则定义**：支持基于 IP 地址、端口、协议的规则配置，能够精细地控制网络流量。

# 3. Calico组件及配置

calico的部署可参考：[kubeadm-scripts/cni/install-calico.sh](https://github.com/huweihuang/kubeadm-scripts/blob/main/cni/install-calico.sh)

部署完成后可以在k8s集群中看到以下组件：

- 中控组件：calico-kube-controllers

- 节点组件：calico-node

```bash
calico-system   calico-kube-controllers-8945657f7-ntbxm             1/1     Running   0             421d
calico-system   calico-node-2df8c                                   1/1     Running   0             421d
calico-system   calico-node-5vq6z                                   1/1     Running   0             421d
calico-system   calico-node-dpnkd                                   1/1     Running   0             421d
calico-system   calico-node-sms2h                                   1/1     Running   0             421d
calico-system   calico-node-w95l2                                   1/1     Running   0             414d
```

## 3.1. calico node进程树

```bash
\_ /usr/local/bin/runsvdir -P /etc/service/enabled
    \_ runsv confd
    |   \_ calico-node -confd
    \_ runsv allocate-tunnel-addrs
    |   \_ calico-node -allocate-tunnel-addrs
    \_ runsv monitor-addresses
    |   \_ calico-node -monitor-addresses
    \_ runsv bird
    |   \_ bird -R -s /var/run/calico/bird.ctl -d -c /etc/calico/confd/config/bird.cfg
    \_ runsv felix
    |   \_ calico-node -felix
    \_ runsv cni
    |   \_ calico-node -monitor-token
    \_ runsv node-status-reporter
    |   \_ calico-node -status-reporter
    \_ runsv bird6
        \_ bird6 -R -s /var/run/calico/bird6.ctl -d -c /etc/calico/confd/config/bird6.cfg
```

## 3.2. calico-kube-controllers进程树

```bash
/usr/bin/kube-controllers
```

## 3.3. CNI calico二进制

```bash
cd /opt/cni/bin
|-- calico
|-- calico-ipam
|-- install
```

## 3.4. CNI calico配置

**10-calico.conflist**

```bash
cd /etc/cni/net.d
# cat 10-calico.conflist
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "log_file_path": "/var/log/calico/cni/cni.log",
      "datastore_type": "kubernetes",
      "nodename": "node1",
      "mtu": 0,
      "ipam": {
          "type": "calico-ipam"
      },
      "policy": {
          "type": "k8s"
      },
      "kubernetes": {
          "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
      }
    },
    {
      "type": "portmap",
      "snat": true,
      "capabilities": {"portMappings": true}
    },
    {
      "type": "bandwidth",
      "capabilities": {"bandwidth": true}
    }
  ]
}
```

**calico-kubeconfig**

```bash
# Kubeconfig file for Calico CNI plugin. Installed by calico/node.
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    server: https://10.96.0.1:443
    certificate-authority-data: "xxx"
users:
- name: calico
  user:
    token:xxx
contexts:
- name: calico-context
  context:
    cluster: local
    user: calico
```

参考：

- https://docs.tigera.io/calico/latest/about/

- https://docs.tigera.io/calico/latest/reference/architecture/overview

- https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart

- [Live Migration from Flannel to Calico](https://www.tigera.io/blog/live-migration-from-flannel-to-calico/)
