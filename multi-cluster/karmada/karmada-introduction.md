> 本文由网络资源整理以作记录

# 简介

Karmada（Kubernetes Armada）是基于Kubernetes原生API的多集群管理系统。在多云和混合云场景下，Karmada提供可插拔，全自动化管理多集群应用，实现多云集中管理、高可用性、故障恢复和流量调度。

# 特性

- 基于K8s原生API的跨集群应用管理，用户可以方便快捷地将应用从单集群迁移到多集群。
- 中心式操作和管理Kubernetes集群。
- 跨集群应用可在多集群上自动扩展，故障转移和负载均衡。
- 高级的调度策略：区域，可用区，云提供商，集群亲和性/反亲和性。
- 支持创建分发用户自定义（CustomResourceDefinitions）资源。

# 框架结构

![img](https://support.huaweicloud.com/productdesc-mcp/zh-cn_image_0000001094636778.png)

- ETCD：存储Karmada API对象。
- Karmada Scheduler：提供高级的多集群调度策略。
- Karmada Controller Manager: 包含多个Controller，Controller监听karmada对象并且与成员集群API server进行通信并创建成员集群的k8s对象。
  - Cluster Controller：成员集群的生命周期管理与对象管理。
  - Policy Controller：监听PropagationPolicy对象，创建ResourceBinding，配置资源分发策略。
  - Binding Controller：监听ResourceBinding对象，并创建work对象响应资源清单。
  - Execution Controller：监听work对象，并将资源分发到成员集群中。

# 资源分发流程

**基本概念**

- 资源模板（Resource Template）：Karmada使用K8s原生API定义作为资源模板，便于快速对接K8s生态工具链。
- 分发策略（Propagaion Policy）：Karmada提供独立的策略API，用来配置资源分发策略。
- 差异化策略（Override Policy）：Karmada提供独立的差异化API，用来配置与集群相关的差异化配置。比如配置不同集群使用不同的镜像。

Karmada资源分发流程图：

![img](https://support.huaweicloud.com/productdesc-mcp/zh-cn_image_0000001141316765.png)





参考：

- https://github.com/karmada-io/karmada
- https://support.huaweicloud.com/productdesc-mcp/mcp_productdesc_0001.html

