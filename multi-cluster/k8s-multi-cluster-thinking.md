---
title: "k8s多集群管理的思考"
linkTitle: "k8s多集群管理的思考"
weight: 1
catalog: true
date: 2021-07-10 10:50:57
subtitle:
header-img: 
tags:
- 多集群
catagories:
- 多集群
---

# k8s多集群的思考

# 1. 为什么需要多集群

**1、k8s单集群的承载能力有限。**

 Kubernetes v1.21 支持的最大节点数为 5000。 更具体地说，Kubernetes旨在适应满足以下*所有*标准的配置：

- 每个节点的 Pod 数量不超过 100
- 节点数不超过 5000
- Pod 总数不超过 150000
- 容器总数不超过 300000

> 参考：https://kubernetes.io/zh/docs/setup/best-practices/cluster-large/

且当节点数量较大时，会出现调度延迟，etcd读写延迟，apiserver负载高等问题，影响服务的正常创建。

**2、分散集群服务风险。**

全部服务都放在一个k8s集群中，当该集群出现异常，短期无法恢复的情况下，则影响全部服务和影响部署。为了避免机房等故障导致单集群异常，建议将k8s的master在分散在延迟较低的不同可用区部署，且在不同region部署多个k8s集群来进行集群级别的容灾。

**3、当前混合云的使用方式和架构**

当前部分公司会存在自建机房+不同云厂商的公有云从而来实现混部云的运营模式，那么自然会引入多集群管理的问题。

# 2. 多集群部署需要解决哪些问题

目标：**让用户像使用单集群一样来使用多集群**。

扩展集群的边界，服务的边界从单台物理机多个进程，发展到通过k8s集群来管理多台的物理机，再发展到管理多个的k8s集群。**服务的边界从物理机发展到集群**。

而多集群管理需要解决以下问题：

- **多集群服务的分发部署（deployment、daemonset等）**
- **跨集群自动迁移与调度（当某个集群异常，服务可以在其他集群自动部署）**
- **多集群服务发现，网络通信及负载均衡（service，ingress等）**

而多集群服务的网络通信可以由Service mesh等来解决，本文不做重点讨论。

以上几个问题，可以先从k8s管理节点的思维进行分析

|            | 物理机视角 | 单集群视角                                           | 多集群视角                                        |
| ---------- | ---------- | ---------------------------------------------------- | ------------------------------------------------- |
| 进程的边界 | 物理机     | k8s集群                                              | 多集群                                            |
| 调度单元   | 进程或线程 | 容器或pod                                            | 工作负载（deployment）                            |
| 服务的集合 |            | 工作负载（deployment）                               | 不同集群工作负载的集合体（workloadGroup）         |
| 服务发现   |            | service                                              | 不同集群service的集合体                           |
| 服务迁移   |            | 工作负载（deployment）控制器                         | 不同集群工作负载的集合体控制器                    |
| 服务调度   |            | nodename或者node selector                            | clustername或cluster selector                     |
|            |            | pod的反亲和（相同deployment下的pod不调度在相同节点） | workload反亲和（相同workloadGroup分散在不同集群） |

## 2.1. 多集群工作负载的分发

单集群中k8s的调度单元是pod，即一个pod只能跑在一个节点上，一个节点可以运行多个pod，而不同节点上的一组pod是通过一个workload来控制和分发。类似这个逻辑，那么在多集群的视角下，多集群的调度单元是一个集群的workload，一个workload只能跑在一个集群中，一个集群可以运行多个workload。

那么就需要有一个控制器来管理不同k8s集群的相同workload。例如 workloadGroup。而该workloadGroup在不侵入k8s原生API的情况下，主要包含两个部分。

**workloadGroup:**

- **资源模板（Resource Template**）：服务的描述（workload）
- **分发策略（Propagaion Policy）**：服务分发的集群（即多个workload应该被分发到哪些集群运行）

workload描述的是什么服务运行在什么节点，workloadGroup描述的是什么服务运行在什么集群。

**实现workloadGroup有两种方式**：

1. 一种是自定义API将workloadGroup中的Resource Template和Propagaion Policy合成在一个自定义的对象中，由用户直接指定该workloadGroup信息，从而将不同的workload分发到不同的集群中。
2. 另一种方式是通过一个k8s载体来记录一个具体的workload对象，再由用户指定Propagaion Policy关联该workload对象，从而让控制器自动根据用户指定的Propagaion Policy将workload分发到不同的集群中。

## 2.2. 跨集群自动迁移与调度

单集群中k8s中通过workload中的nodeselector或者nodename以及亲和性来控制pod运行在哪个节点上。而多集群的视角下，则需要有一个控制器来实现集群级别的调度逻辑，例如clustername，cluster selector，cluster AntiAffinity，从而来自动控制workloadGroup下的workload分散在什么集群上。

# 3. 目前的多集群方案

## 3.1. Kubefed[Federation v2]

简介

基本思想

## 3.2. virtual kubelet

简介

基本思想

## 3.3.  Karmada

简介

基本思想







参考：

- https://kubernetes.io/zh/docs/setup/best-practices/cluster-large/
- [CoreOS 是如何将 Kubernetes 的性能提高 10 倍的?](https://caicloud.io/blog/57392eca8241681100000003)
- [当 K8s 集群达到万级规模，阿里巴巴如何解决系统各组件性能问题？](https://juejin.cn/post/6844903950836056077)
- https://github.com/kubernetes-sigs/kubefed
- https://jimmysong.io/kubernetes-handbook/practice/federation.html
- https://kubernetes.io/blog/2018/12/12/kubernetes-federation-evolution/
- https://zhuanlan.zhihu.com/p/355193315

