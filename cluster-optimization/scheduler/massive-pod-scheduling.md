---
title: "大规模Pod调度优化"
weight: 1
catalog: true
date: 2025-06-07 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

假设在 Kubernetes 集群中一次性调度 1 万个 Pod， 这是一项极具挑战性的任务。如果管理不当，可能会导致调度器瓶颈、API Server 过载，甚至整个集群崩溃。

本文将探讨优化大规模 Pod 调度的最佳实践与技术手段。

---

# 🚀 面临的挑战

- **调度器压力大**：大量 Pod 同时进入 Pending 状态，调度器处理不过来。
- **API Server 压力大**：高频的 CREATE/GET/LIST 请求可能触发限流。
- **etcd 延迟增加**：写入及状态变化频繁，导致存储后端压力过大。
- **节点压力不均衡**：调度不均可导致部分节点 CPU/内存/磁盘 IO 资源打爆。
- **网络插件瓶颈**：CNI 插件无法处理大量并发的 IP 分配。

---

# 1. 调度器优化

## 🔧 1.1. 控制 Pod 创建速率

不要一次性启动 10,000 个 Pod，而是：

- **分批创建**：例如每批创建 500–1000 个 Pod。
- **控制速率**：通过脚本或 Job 控制器引入 `sleep` 等时间间隔。

### 示例 Shell 脚本：

```bash
for file in batches/batch_*.yaml; do
  kubectl apply -f "$file"
  sleep 10
done
```


## ⚙️ 1.2. 调优默认调度器

默认调度器（`kube-scheduler`）在高并发场景下可能成为瓶颈。为了高效调度 1 万个以上的 Pod，可以从以下几个方面进行深入调优：

### ✅ 1. 提高并发调度能力

Kubernetes v1.19+ 支持配置并行调度线程数：

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  parallelism: 64
```

> 推荐值为 CPU 核心数的 2~4 倍（视调度密集度而定）。  
> 注意：并发过高可能导致内存激增或 etcd 压力过大，建议结合压测评估。

### ✅ 2. 启用缓存调度器（Scheduling Queue 优化）

调度器内部维护了 Pending Pod 的优先队列（`PriorityQueue`）与 Node 信息缓存。

- **确保使用优先级调度**（PodPriority）可帮助调度器优先处理重要任务。

- 配置调度器时可启用 `permit` 插件阶段，在调度决策前提前控制调度流量。

### ✅ 3. 关闭或精简耗时插件

某些默认启用的插件在调度高峰时会带来性能负担：

| 插件               | 类型     | 说明             |
| ---------------- | ------ | -------------- |
| VolumeBinding    | Bind   | 持久化卷绑定，需访问 API |
| NodeResourcesFit | Filter | 检查资源是否满足       |
| InterPodAffinity | Filter | Pod 之间亲和性计算复杂  |

⚠️ **优化建议**：

- 无状态服务建议 **关闭 VolumeBinding** 插件。

- 只使用必要的 Score 插件（如 `LeastAllocated`、`BalancedAllocation`）。

配置方式：

```yaml
plugins:
  score:
    disabled:
    - name: "NodeResourcesBalancedAllocation"
    enabled:
    - name: "NodeResourcesLeastAllocated"
```

### ✅ 4. 预选节点集范围（节点剪枝）

调度器默认会评估所有可调度节点，1 万 Pod × 1 千节点的组合极其耗时。

优化方法：

- **NodeAffinity**：提前通过标签筛掉不符合的节点。

- **使用 preFilter 插件** 自定义节点集合。

示例：

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/worker
          operator: In
          values:
          - batch
```


### ✅ 5. 启用拓扑感知与亲和性缓存

使用拓扑调度建议：

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway
```


### ✅ 6. 控制调度队列压力（Backoff & Retry）

Pod 多次调度失败会进入 backoff 队列，默认退避时间为：

```go
InitialBackoff = 1 * time.Second 
MaxBackoff = 10 * time.Second
```

调大 `MaxBackoff` 可减缓高频重试对调度器的压力。

### 🧪 调优效果验证建议：

- 使用 `--v=5` 级别运行 `kube-scheduler`，输出调度详细日志。

- 观察调度延迟指标（SchedulingLatencySeconds）：
  
  - `framework_extension_point_duration_seconds`
  
  - `scheduler_scheduling_duration_seconds_bucket`

## 🧩 1.3. 扩展调度器（Scheduling Framework 插件）

Kubernetes 支持通过调度框架插件机制自定义调度逻辑。

### ✨ 示例：快速 Filter 插件

自定义过滤插件，可只评估部分节点，从而减少调度延迟：

```go
func (f *FastFilterPlugin) Filter(...) *framework.Status {
  if strings.HasPrefix(node.Name, "compute-node-") {
    return framework.NewStatus(framework.Success)
  }
  return framework.NewStatus(framework.Unschedulable)
}
```


## 🧠 1.4. 使用多个调度器（调度器隔离）

并行部署多个调度器进程：

```yaml
spec:
  schedulerName: batch-scheduler
```

每类工作负载使用不同调度器进行处理，实现并行调度和资源隔离。


## 🛠 1.5. 使用高性能调度系统

### Koordinator

- 支持批量调度、NUMA 感知、QoS 资源分级
- 与 Kubernetes 调度框架兼容，部署简单

### Volcano

- 面向大规模批处理、AI/ML、HPC 任务调度
- 支持抢占、任务优先级、依赖关系等


## 📊 1.6. 监控与验证建议

- 使用 `kubectl get pods -w` 实时观察 Pending 状态
- 关注调度事件 `FailedScheduling`
- 跟踪 API Server 指标：QPS、延迟、内存占用
- 部署 Prometheus + Grafana 进行系统监控与可视化


## ✅ 1.7. 总结对比

| 优化方式                   | 效果              |
| ---------------------- | --------------- |
| 控制 Pod 创建速率            | 避免控制面组件过载       |
| 提高调度器并发度               | 提升每秒调度吞吐        |
| 编写调度器插件                | 降低单次调度复杂度       |
| 多调度器架构                 | 实现任务隔离与并行调度     |
| 使用 Koordinator/Volcano | 面向 AI/批处理等高负载场景 |

---

# 2. Etcd优化

etcd 是 Kubernetes 控制平面的核心存储引擎，一旦在大规模 Pod 创建、调度过程中出现 **写入延迟增加**，会直接影响 API Server 性能，进而拖慢调度器和控制器反应速度，甚至引发集群不可用。

## 🔧 2.1. 基础配置优化

### ✅ 1. 启用自动压缩历史数据

etcd 默认会保留历史版本，随着对象变化增多，存储膨胀，导致延迟升高。

```bash
--auto-compaction-retention=1h   # 每小时清理历史
--snapshot-count=10000           # 控制何时触发快照
```

### ✅ 2. 启用 WAL 压缩

压缩 Write-Ahead Log，减少磁盘 I/O 开销：

```bash
--experimental-initial-corrupt-check=true
--experimental-compact-hash-check-enabled=true
```


## 💽 2.2. 硬件层优化（非常关键）

etcd 对 **磁盘 IOPS 和延迟** 敏感，推荐：

- **使用 SSD**（NVMe 最佳）

- etcd 独立磁盘，避免和 kubelet 或 container runtime 共用

- 提升内存（建议 16G+）、CPU 性能（至少 4 核）

- 开启 NUMA 亲和配置，减少跨核调度


## 🧱 2.3. 集群部署架构优化

### ✅ 1. 隔离部署 etcd

etcd不要与 `kube-apiserver`、`controller-manager` 等组件共节点运行。

1）**etcd 对磁盘 IO、内存和 CPU 的性能非常敏感**，特别是磁盘延迟对 etcd 性能和稳定性有显著影响。

- kube-apiserver、controller-manager、scheduler 等组件也会频繁访问 etcd，产生较大 CPU 和内存负载。

- 如果它们部署在同一节点，容易导致 **资源竞争（尤其是 IO）**，影响 etcd 的响应能力和稳定性，进而影响整个集群的控制面。

2） **Kubernetes 通常运行在高速局域网内，访问 etcd 的延迟很小**

- 网络延迟在现代数据中心或云环境中通常是**微秒到毫秒级别**。

- 只要保证 etcd 集群网络稳定，控制面组件即使不在同一个节点也能快速访问。

3） **不在一个节点，可以避免“局部高负载”导致连锁影响**

- 如果 kube-apiserver 跟 etcd 同节点，一旦 kube-apiserver 突发流量（比如创建大量资源），会导致 **etcd 所在节点资源被占满**，从而影响 etcd 响应。

- 反之亦然，etcd 的 GC 或 compaction 操作也可能影响 apiserver 的性能。

### ✅ 2. 多副本部署（3~5个节点）

避免单点瓶颈，并启用高可用。

# 3. kube-apiserver优化

在大量 Pod 同时调度时，**API Server 压力大** 是造成集群卡顿或异常的核心瓶颈之一，主要表现为：

- 创建、更新、查询 Pod 等请求响应变慢

- kubelet、controller-manager 与 API Server 通信超时

- etcd QPS 激增、延迟升高，甚至触发熔断

以下是具体的优化策略，从集群参数、限流、组件解耦等多个层面展开：

## 🧱 3.1. 控制请求速率（限流）

### ✅ 1. 控制客户端创建速率

比如大量 Job/Deployment 控制器、脚本同时发出 `kubectl apply` 请求：

**解决方法：**

- 采用 `kubectl --wait=false` 异步创建

- 使用分批 apply 或 sleep 控制速率

- 使用 controller（例如自定义 CRD + controller）分批分组管理 pod/job


## ⚙️ 3.2. 调优 API Server 参数

在 kube-apiserver 启动参数中：

### ✅ 1. 增加最大并发 QPS

```bash
--max-requests-inflight=4000              # 默认 400，增加吞吐能力
--max-mutating-requests-inflight=2000     # 默认 200，调大写请求容量
```

### ✅ 2. 增加缓存时间与响应窗口

```bash
--request-timeout=1m
--min-request-timeout=300
```

## 3.3. operator优化

如果有开发自定义的operator，则需要对operator的逻辑进行优化。

### ✅ 1. 使用 informer 缓存机制（client-go 默认支持）

自定义控制器或调度插件中应使用共享缓存，而非频繁 `GET`：

```bash
informer := factory.Core().V1().Pods().Informer()
```

### ✅ 2. 减少不必要的 Watch 或频繁 List 请求

- 调度器插件中不要频繁访问 Pod 列表

- 减少 metrics 或审计日志系统对 API 的高频采集

# 4. 网络插件优化

Kubernetes 网络插件（CNI）在大规模部署或高并发场景下，若处理能力跟不上，会出现 **调度成功但网络不通、服务连接慢、跨节点通信异常** 等问题。

## 🧭 4.1. 网络瓶颈表现

| 现象                            | 可能原因                          |
| ----------------------------- | ----------------------------- |
| Pod 创建卡住在 `ContainerCreating` | CNI 插件调用超时，网络设备未初始化           |
| 跨节点服务访问慢或超时                   | 网络插件转发路径性能不足，iptables/ebpf 累积 |
| 集群中 ping 某些 Pod 慢             | 某些节点流量瓶颈，或者 VXLAN 隧道高延迟       |
| `kube-proxy` CPU 占满           | iptables 规则过多或频繁变更            |

## ✅ 4.2. 选型优化：选择高性能 CNI 插件

| 插件                          | 性能特点                             |
| --------------------------- | -------------------------------- |
| [Cilium](https://cilium.io) | eBPF 驱动，无需 iptables，极高性能，支持大规模节点 |
| Calico (BPF 模式)             | 支持 eBPF 模式，性能更好于传统 iptables      |
| Flannel                     | 适用于小规模集群，性能普通，不推荐大集群使用           |
| Multus                      | 支持多网卡/多 CNI，适合边缘场景但调试复杂          |

> 💡 推荐使用 **Cilium 或 Calico（eBPF 模式）**，避免使用传统 Flannel/VXLAN。

## ⚙️ 4.3. 网络插件参数调优

### 🔹 Cilium 示例

配置 `/etc/cilium/cilium-config`：

```bash
enable-bpf-masquerade: "true"
enable-ipv4-masquerade: "false"
bpf-lb-map-max: "65536"
bpf-ct-global-tcp-max: "524288"
bpf-ct-global-any-max: "262144"
```

并启用 kube-proxy 替代模式（kube-proxy-free）：

```yaml
kubeProxyReplacement: "strict"
```


## 🔄 4.4. 跨节点通信优化

### ✅ 1. 减少 VXLAN 封装（或改为 Native Routing）

- Flannel/Calico VXLAN 模式性能差

- 推荐切换为 Calico 的 **BGP 模式**（路由直达，无封装）

### ✅ 2. 使用 Direct Server Return（DSR）+ ECMP 路由

大流量服务部署时，避免中心化转发。

## 🔃 4.5. kube-proxy 优化

### ✅ 1. 使用 `ipvs` 模式代替 `iptables`

```bash
--proxy-mode=ipvs
--ipvs-scheduler=rr
```

相比 `iptables`，`ipvs` 处理服务转发在大规模集群下 CPU 更省、延迟更低。

### ✅ 2. 配合 eBPF 替代 kube-proxy（Cilium 推荐）

Cilium 的 `kube-proxy-replacement=strict` 直接使用 BPF 加速服务调度。

## 🔧 4.6. 节点系统参数优化

设置节点的内核参数，提升大流量下系统处理能力：

```bash
# 提高 conntrack 表容量
sysctl -w net.netfilter.nf_conntrack_max=262144
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=86400

# 允许更多文件描述符
ulimit -n 1048576

# 调高队列长度
sysctl -w net.core.somaxconn=1024
sysctl -w net.core.netdev_max_backlog=250000
```

## 📊 4.7. 监控关键指标

通过 Cilium/Calico 自带 metrics 或 Prometheus 采集：

| 指标                                  | 说明               |
| ----------------------------------- | ---------------- |
| `cilium_forwarding_latency_seconds` | 转发延迟             |
| `cilium_drop_count_total`           | 数据包被丢弃的原因        |
| `iptables_rule_count`               | kube-proxy 中规则数量 |
| `conntrack_entries`                 | 当前连接跟踪表大小        |

## ✅ 4.8. 总结优化建议表

| 方向   | 方案                               |
| ---- | -------------------------------- |
| 插件选型 | 使用 Cilium/Calico eBPF，避免 Flannel |
| 插件配置 | 优化转发表、连接跟踪表大小                    |
| 网络架构 | BGP 替代 VXLAN，开启 kube-proxy-free  |
| 系统内核 | 调高 conntrack / backlog 等参数       |
| 转发模式 | 使用 ipvs 或 eBPF 加速 kube-proxy     |
| 监控排查 | 开启 drop 分析、BPF 路径追踪              |

---

# 5. 总结

大规模 Pod 调度不仅仅是追求速度，更重要的是在高压下保持系统的稳定性与正确性。需要从各个方面进行集群优化才能承受大规模pod集群的性能压力。本文分别从以下几个方面进行优化：

- 调度器及扩展调度器

- ETCD优化

- kube-apiserver优化

- 网络插件及节点优化

只要设计合理，Kubernetes 完全可以稳定高效地调度数万个 Pod。
