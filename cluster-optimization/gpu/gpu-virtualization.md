> 本文主要描述如何实现GPU资源的虚拟化。基于volcano官方文档整理。

# 1. 背景

随着大模型和AI的发展，GPU算力的需求越来越高，但是GPU成本高昂，对于小型工作负载，单个GPU可能造成资源浪费；而对于大型工作负载，单个GPU的算力又可能未被充分挖掘。因此需要通过GPU虚拟化的技术来提高GPU的利用率。

# 2. Volcano虚拟化方式

Volcano主要支持硬件和软件两种GPU共享模式，用以实现vGPU调度并满足不同的硬件能力与性能需求：

## 2.1. HAMI-core（基于软件的vGPU）

**描述**： 通过VCUDA (一种CUDA API劫持技术) 对GPU核心与显存的使用进行限制，从而实现软件层面的虚拟GPU切片。

**使用场景**： 适用于需要细粒度GPU共享的场景，`兼容所有类型的GPU`。

## 2.2. Dynamic MIG（硬件级GPU切片）

**描述**： 采用`NVIDIA的MIG (Multi-Instance GPU)`技术，可将单个物理GPU分割为多个具备硬件级性能保障的隔离实例。

**使用场景**： 尤其适用于对性能敏感的工作负载，`要求GPU支持MIG特性`（如A100、H100系列）。

## 2.3. 对比

| 模式          | 隔离级别       | 是否依赖MIG GPU | 需注解指定模式 | 核心/显存控制方式     | 推荐应用场景     |
| ----------- | ---------- | ----------- | ------- | ------------- | ---------- |
| HAMI-core   | 软件 (VCUDA) | 否           | 否       | 用户自定义 (核心/显存) | 通用型工作负载    |
| Dynamic MIG | 硬件 (MIG)   | 是           | 是       | MIG实例规格决定     | 对性能敏感的工作负载 |

# 3. 部署

1、 部署volcano，参考：[Volcano的使用](https://blog.huweihuang.com/kubernetes-notes/cluster-optimization/scheduler/volcano-usage/#4-%E9%83%A8%E7%BD%B2)

2、 部署[`volcano-vgpu-device-plugin`](https://github.com/Project-HAMi/volcano-vgpu-device-plugin)。

该组件是一个DaemonSet。

```bash
wget https://raw.githubusercontent.com/Project-HAMi/volcano-vgpu-device-plugin/refs/heads/main/volcano-vgpu-device-plugin.yml
kubectl apply -f volcano-vgpu-device-plugin.yml
```

# 4. 使用





参考：

- [GPU虚拟化 | Volcano](https://volcano.sh/zh/docs/gpu_virtualization/)

- https://github.com/tkestack/gpu-manager

- [volcano-vgpu-device-plugin: Device-plugin for volcano vgpu which support hard resource isolation](https://github.com/Project-HAMi/volcano-vgpu-device-plugin)

- [使用GPU虚拟化 云容器引擎 CCE-华为云](https://support.huaweicloud.com/usermanual-cce/cce_10_0646.html)
