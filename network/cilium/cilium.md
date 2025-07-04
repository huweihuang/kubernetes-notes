---
title: "Cilium介绍"
weight: 1
catalog: true
date: 2024-11-16 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
- CNI
catagories:
- Kubernetes
- CNI
---

# 1. Cilium简介

Cilium 是一个开源的容器网络插件（CNI），专为 Kubernetes 和云原生环境设计，基于 **eBPF（Extended Berkeley Packet Filter）** 实现高性能、可扩展的网络和安全功能。它支持微服务间的细粒度流量控制，能够在 L3/L4/L7 层提供网络策略，同时具有强大的可观测性工具（如 Hubble）以帮助运维人员监控和优化流量。

## 1.1. 核心特性

1. **基于 eBPF 的**高性能**数据平面**

   - **eBPF**：Cilium 通过 eBPF 在 Linux 内核中直接运行数据包处理逻辑，避免了内核与用户态的频繁切换，大幅提高了性能。

   - **高效流量转发**：支持 BPF 的快速路径优化（Zero-Copy 转发），在高流量环境中表现出色。

2. **多层网络策略**

   - **L3/L4 策略**：基于 IP 和端口的基本流量控制。

   - **L7 策略**：支持应用层协议（如 HTTP、gRPC）的访问控制，可以根据请求路径、方法或内容过滤流量。

   - **微服务友好**：特别适合需要细粒度网络策略的微服务架构。


3. **可观测性**

   - **Hubble**：Cilium 内置的可观测性平台，可以实时监控服务间的网络流量、延迟和错误率，帮助开发和运维团队快速定位问题。

   - **流量路径追踪**：支持流量路径的全链路追踪，便于排查网络瓶颈或策略冲突。


4. **拓展性**

   - 支持自定义 eBPF 程序，用户可以根据业务需求扩展网络功能。

   - 与其他云原生工具（如 Prometheus、Grafana、Istio）无缝集成。


5. **跨云和混合云支持**
   - 支持 Kubernetes 集群的多网络环境，例如在跨云和混合云场景中提供统一的网络策略和流量控制。


6. **服务发现与负载均衡**

   - **内置服务负载均衡**：提供内核级的流量负载均衡，比传统的 kube-proxy 性能更高。

   - **服务发现支持**：可以与 Kubernetes 的 Service 资源协同工作，自动实现 Pod 间通信。

## 1.2. 适用场景

1. 云原生微服务架构
   - 在需要严格流量控制和丰富可观测性的环境中表现尤为出色。
2. 边缘计算
   - 低延迟需求较高的场景，如 CDN 边缘节点和 IoT 环境。
3. 高流量集群
   - 适用于对吞吐量和性能要求极高的生产集群，例如电商、流媒体和金融服务。
4. 多租户隔离
   - 支持多租户网络环境中的强隔离需求。

## 1.3. Cilium的局限性

虽然 Cilium 在现代 Kubernetes 网络中表现出色，但它也存在一些缺点或需要注意的限制。

**`1. 高性能消耗`**

- **内存和 CPU 占用**：由于需要在每个节点运行 Cilium Agent 和依赖 eBPF 加载程序，可能对节点资源消耗较高，尤其是在高流量场景下。
- **资源密集功能**：如 Hubble（Cilium 的可观测性工具）可能进一步增加资源使用。

**`2. 依赖 Linux 内核版本`**

- **eBPF 限制**：Cilium 依赖 eBPF 技术，对 Linux 内核版本有要求，最低需要 **4.19+**，部分功能（如高级负载均衡）需要 **5.x** 或更高版本。
- **内核升级成本**：在某些环境（如老旧系统或企业级环境）中，升级内核可能具有挑战性。

**`3. 学习曲线陡峭`**

- **复杂性**：Cilium 引入了 eBPF 技术，与传统 CNI（如 Calico、Flannel）相比技术更复杂，需要深入理解 eBPF、Linux 内核网络栈和 Cilium 的配置方式。

**`4. 部署和管理复杂`**

- **高级功能配置繁琐**：如替代 `kube-proxy` 或配置高性能负载均衡，需要了解底层网络和 Kubernetes 的细节。
- **监控和故障排查难度**：eBPF 程序运行在内核中，排查问题时无法直接查看传统用户态日志，需使用专用工具如 `bpftool` 或 Hubble。

# 2. Cilium部署

## 2.1. 部署

部署文档可参考：

- https://docs.cilium.io/en/stable/installation/k8s-install-helm/
- https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#k8s-install-quick

可以使用helm来部署

**默认值：**

- 默认的`clusterPoolIPv4PodCIDRList`是`10.0.0.0/8`，需要保证pod CIDR跟node的CIDR不冲突。
- 默认`ipam.mode`是`cluster-pool`，可不修改设置。

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

# 部署cilium
kubectl create ns cilium-system || true
helm install cilium cilium/cilium --namespace cilium-system \
    --set ipam.mode=cluster-pool \
    --set ipam.operator.clusterPoolIPv4PodCIDRList="10.244.0.0/16" \
    --set ipam.operator.clusterPoolIPv4MaskSize=24
```

或者使用Cilium CLI 部署

```bash
# 安装cilium cli
curl -L --remote-name https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
sudo mv cilium /usr/local/bin

# 部署cilium套件
kubectl create ns cilium-system || true
cilium install --namespace=cilium-system \
    --set ipam.mode=cluster-pool \
    --set ipam.operator.clusterPoolIPv4PodCIDRList="10.244.0.0/16" \
    --set ipam.operator.clusterPoolIPv4MaskSize=24
```

## 2.2. 部署检查

```bash
$ cilium status --wait --namespace cilium-system
   /¯¯\
/¯¯\__/¯¯\    Cilium:         OK
\__/¯¯\__/    Operator:       OK
/¯¯\__/¯¯\    Hubble:         disabled
\__/¯¯\__/    ClusterMesh:    disabled
   \__/

DaemonSet         cilium             Desired: 2, Ready: 2/2, Available: 2/2
Deployment        cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
Containers:       cilium-operator    Running: 2
                  cilium             Running: 2
Image versions    cilium             quay.io/cilium/cilium:v1.9.5: 2
                  cilium-operator    quay.io/cilium/operator-generic:v1.9.5: 2
```

网络连通性测试

```bash
$ cilium connectivity test
ℹ️  Monitor aggregation detected, will skip some flow validation steps
✨ [k8s-cluster] Creating namespace for connectivity check...
(...)
---------------------------------------------------------------------------------------------------------------------
📋 Test Report
---------------------------------------------------------------------------------------------------------------------
✅ 69/69 tests successful (0 warnings)
```

## 2.3. Cilium IPAM 模式

Cilium 支持以下两种常见的 IPAM 模式：

### 2.3.1. Cluster-Pool 模式（默认模式）：

- 由 Cilium 自己管理 Pod IP 地址范围。
- 可以在部署时指定 CIDR 范围。
- **高灵活性**：支持为不同节点或区域定义独立的 IP 地址池。
- **动态管理**：可以动态调整 IP 地址池大小，适应集群的扩展需求。
- **无冲突设计**：避免因节点增加或删除引起的 IP 地址冲突。
- **优化性能**：减少对 Kubernetes 控制器的依赖，提高网络性能和资源利用率。
- **依赖 Cilium Operator**：需要运行 Cilium Operator 来管理 IP 地址池，增加运维复杂性。

**推荐场景**

- 大型集群（> 500 节点）或超大规模集群。
- 需要跨区域或多节点池的复杂网络规划。
- 需要动态扩展 Pod IP 地址范围的集群。
- 集群运行 Cilium 并需要充分利用其高级功能（如 eBPF 加速、服务网格等）。

### 2.3.2. Kubernetes 模式：

- 使用 Kubernetes 自身的 IP 地址分配方式，例如由 `kube-controller-manager` 通过 `--cluster-cidr` 进行管理。
- Cilium 从 Kubernetes 中获取分配给 Pod 的 IP 地址。
- **兼容性强**：适配大多数 CNI 插件（包括 Cilium），无需额外配置。
- **灵活性有限**：不支持细粒度的 IP 地址池管理，无法为特定节点或区域分配特定的 IP 范围。

**推荐场景**

- 小型或中型集群（< 500 节点）。
- 网络规划较为简单，无需复杂的 IP 地址管理。
- 需要快速部署并保持与 Kubernetes 默认行为一致。

# 3. Cilium架构及组件介绍

## 3.1. 架构图

参考官网： https://docs.cilium.io/en/stable/overview/component-overview/

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1731811820/article/kubernetes/network/cilium/cilium-arch.webp)

## 3.2. 核心组件

**1. Cilium Agent**

- 运行在每个 Kubernetes 节点上，是 Cilium 的核心守护进程。
- 功能：
  - 从 Kubernetes API Server 获取资源（如 Pod、Service 和网络策略）并转换为 eBPF 程序。
  - 在每个节点上管理和加载 eBPF 程序到内核。
  - 实现 L3/L4 和 L7 网络策略，并将策略下发到数据平面。
  - 负责服务发现和负载均衡（取代 kube-proxy）。

**2. Cilium CLI**

  - 命令行工具，用于安装、配置和调试 Cilium。
  - 功能：
    - 配置 Cilium 的网络策略。
    - 查看 Cilium 和 Hubble 的运行状态。
    - 调试 eBPF 程序。

**3. CNI Plugin**

- 当在节点上调度或终止pod时，Kubernetes会调用CNI插件（cilium-cni）。它与节点的Cilium API交互，触发必要的数据路径配置，为pod提供网络、负载平衡和网络策略。

 **4. Cilium Operator**

- 在 Kubernetes 中运行的控制平面组件。
- 功能：
  - 处理 IP 地址管理：管理 Pod 的 IP 池。
  - 维护 Cilium Agent 与 Kubernetes 的集成。
  - 处理节点间的拓扑变化（如节点加入或离开）。

## 3.3. 其他组件

 **1. eBPF 程序**

- Cilium 的数据平面核心，运行在 Linux 内核中。
- 功能：
  - **路由和转发**：在节点间处理 Pod 的网络流量。
  - **网络策略**：实现 L3/L4 和 L7 的访问控制。
  - **服务负载均衡**：提供类似 kube-proxy 的服务转发功能，但性能更高。
  - **监控和可观测性**：收集网络流量数据，供 Hubble 或其他工具分析。

**2. Hubble**

- Cilium 的可观测性平台，用于实时监控和分析网络流量。
- 功能：
  - 流量可视化：展示服务间的流量路径和统计。
  - 流量追踪：捕获和调试网络问题。
  - 延迟和错误率监控。

# **4. Cilium 的工作流**

1. **初始化**：
   - Cilium Agent 启动后，与 Kubernetes API Server 建立连接，监听资源变化。
2. **策略配置**：
   - 用户定义的 `NetworkPolicy` 或 `CiliumNetworkPolicy` 通过 Cilium Agent 传递到 eBPF 程序。
   - eBPF 程序在内核中直接执行流量控制逻辑。
3. **流量处理**：
   - 数据平面通过 eBPF 程序对网络流量进行路由、策略匹配和负载均衡。
4. **监控和分析**：
   - eBPF 程序收集流量数据，发送到 Hubble。
   - Hubble 将数据可视化，供用户监控和调试。



参考：

- https://docs.cilium.io/en/stable/
- https://docs.cilium.io/en/stable/overview/component-overview/
- https://docs.cilium.io/en/stable/network/concepts/ipam/