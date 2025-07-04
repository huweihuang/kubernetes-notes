---
title: "CNI插件选型"
weight: 2
catalog: true
date: 2024-11-16 10:50:57
subtitle:
header-img: 
tags:
- CNI
catagories:
- CNI
---

本文主要描述常用的CNI插件的选型，主要包括cilium，calico，flannel三种插件的对比。

# 1. 技术特点对比

| 特性       | **Cilium**                 | **Calico**                       | **Flannel**                     |
| ---------- | -------------------------- | -------------------------------- | ------------------------------- |
| 数据面技术 | eBPF 加速                  | 基于 iptables（支持 eBPF）       | vxlan、host-gw、ipip 等隧道技术 |
| 转发效率   | 高（内核级加速，直通流量） | 高（支持原生路由）               | 中（隧道技术增加开销）          |
| 可扩展性   | 优（支持高级 L7 策略）     | 优（支持原生路由和简单网络策略） | 较低（以 L3 网络为主）          |
| 延迟       | 低（无需额外隧道或规则）   | 低（无隧道或 eBPF 模式）         | 较高（隧道封装增加延迟）        |
| 吞吐量     | 高（eBPF 高效转发）        | 中（依赖 iptables 或 eBPF）      | 较低（隧道开销显著）            |

# 2. 性能指标对比

| 性能指标     | **Cilium**                  | **Calico**                 | **Flannel**              |
| ------------ | --------------------------- | -------------------------- | ------------------------ |
| **吞吐量**   | 高（eBPF 高效转发）         | 中-高（取决于模式）        | 较低（隧道封装损耗较大） |
| **延迟**     | 低（直接路由模式最佳）      | 较低（非隧道模式表现良好） | 较高（隧道增加延迟）     |
| **CPU使用**  | 较高（eBPF 和可观测性功能） | 中（iptables/eBPF 开销）   | 低（简单架构）           |
| **内存使用** | 较高（功能丰富）            | 中                         | 低                       |

# 3. 测试数据示例

以下是根据典型测试场景总结的指标（单位为吞吐量 Mbps 和延迟 ms）：

| 测试场景            | **Cilium**  | **Calico**  | **Flannel** |
| ------------------- | ----------- | ----------- | ----------- |
| **吞吐量 (单节点)** | ~9,000 Mbps | ~8,500 Mbps | ~6,000 Mbps |
| **吞吐量 (跨节点)** | ~8,000 Mbps | ~7,500 Mbps | ~5,000 Mbps |
| **延迟 (单节点)**   | ~0.2 ms     | ~0.3 ms     | ~1.0 ms     |
| **延迟 (跨节点)**   | ~0.4 ms     | ~0.5 ms     | ~2.0 ms     |

2020年测试数据：

数据来源：[Benchmark results of Kubernetes network plugins (CNI) over 10Gbit/s network (Updated: August 2020)](https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-10gbit-s-network-updated-august-2020-6e1b757b9e49)

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1731839739/article/kubernetes/network/cni/cni-comparison.webp)

[2024年]单位带宽消耗的CPU和内存数据：

数据来源：[Benchmark results of Kubernetes network plugins (CNI) over 40Gbit/s network -2024](https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-40gbit-s-network-2024-156f085a5e4e#89d8-90c23c8caeb4-reply)

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1731839992/article/kubernetes/network/cni/Resource-efficiency-per-CNI.webp)

以上可以看出cilium单位消耗的CPU和内存相比于flannel高。

# 4. 网络性能分析

## 4.1. Cilium

- **吞吐量**：基于 eBPF 的数据面技术，可直接在 Linux 内核中高效转发流量，减少上下文切换。使用直连路由模式（`--tunnel=disabled`）时，进一步减少封装开销。
- **延迟**：支持 Sidecar-less 的服务网格架构，能够降低服务间通信延迟。
- **资源消耗**：由于其高级功能（如 Hubble 可观测性和 L7 策略），在 CPU 和内存使用上高于其他插件。

## 4.2. Calico

- **吞吐量**：非隧道模式下，基于 BGP 的原生路由性能接近裸机水平；启用 eBPF 模式时，性能进一步提升。
- **延迟**：表现良好，但在复杂网络策略下可能增加延迟。
- **资源消耗**：资源使用适中，适合大多数生产环境。

## 4.3. Flannel

- **吞吐量**：由于采用 VXLAN、IPIP 等隧道封装方式，其性能通常不如 Cilium 和 Calico。
- **延迟**：封装和解封装的额外操作导致延迟增加。
- **资源消耗**：架构简单，资源使用最低，适合资源有限的小型集群。

# 5. 业务场景选型

**1. Cilium：适合高性能与安全需求的场景**

- 适用场景：
  - **微服务架构**：Cilium 的 eBPF 技术支持 L7 数据包过滤、服务可观测性和无 Sidecar 服务网格，非常适合复杂微服务环境。
  - **边缘计算**：在边缘节点上，需要低延迟和高吞吐量，Cilium 的直连路由模式（`--tunnel=disabled`）非常高效。
  - **多云和混合云**：支持多种高级网络功能，如网络策略的灵活配置和透明的加密。
- 局限性：
  - 部署复杂度相对较高，对 Linux 内核版本有要求（推荐 5.3+）。
  - 资源消耗比 Flannel 高。


**2. Calico：适合大规模、灵活策略的企业集群**

- 适用场景：
  - **大规模 Kubernetes 集群**：基于 BGP 的网络路由能够高效扩展，适合公有云和企业级大规模集群。
  - **注重安全策略**：支持丰富的网络安全策略，并提供对接 eBPF 的能力，兼顾性能和策略灵活性。
  - **混合部署**：Calico 可以在非 Kubernetes 工作负载中实现一致的网络策略。
- 局限性：
  - 默认基于 iptables 的实现在高负载下性能可能不如 Cilium 的 eBPF 数据面。
  - 网络策略复杂度较高时，可能增加运维工作量。


**3. Flannel：适合轻量级和资源有限的集群**

- 适用场景：
  - **小型集群**：Flannel 架构简单，资源使用少，适合轻量化的 Kubernetes 部署。
  - **测试环境**：性能需求较低的开发和测试环境中，可以快速搭建和运行。
  - **边缘计算（非高性能）**：对网络性能要求较低的小型边缘节点可以使用。
- 局限性：
  - 在吞吐量和延迟上不如 Cilium 和 Calico，尤其是需要大量隧道封装时。
  - 缺乏高级网络功能，例如复杂的网络策略和观测能力。

**4. 推荐选择总结**

| 场景类型             | 推荐插件           | 原因                                                       |
| -------------------- | ------------------ | ---------------------------------------------------------- |
| **高性能微服务架构** | **Cilium**         | 提供 eBPF 技术，支持复杂策略和低延迟网络                   |
| **大规模企业集群**   | **Calico**         | 稳定、灵活，适合多样化和大规模 Kubernetes 部署             |
| **资源受限环境**     | **Flannel**        | 简单易用，资源消耗低                                       |
| **边缘计算**         | **Cilium/Flannel** | Cilium 适合高性能需求，Flannel 适合轻量级节点              |
| **混合云/多云**      | **Cilium/Calico**  | Cilium 支持透明加密和现代架构，Calico 提供灵活网络策略支持 |





参考：

- https://docs.cilium.io/en/latest/operations/performance/benchmark/
- https://cilium.io/blog/2018/12/03/cni-performance/
- https://cilium.io/blog/2021/05/11/cni-benchmark/
- [Benchmark results of Kubernetes network plugins (CNI) over 40Gbit/s network -2024](https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-40gbit-s-network-2024-156f085a5e4e#89d8-90c23c8caeb4-reply)
- [Benchmark results of Kubernetes network plugins (CNI) over 10Gbit/s network (Updated: August 2020)](https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-10gbit-s-network-updated-august-2020-6e1b757b9e49)
