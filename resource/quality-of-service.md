---
title: "资源服务质量"
linkTitle: "资源服务质量"
weight: 3
catalog: true
date: 2018-6-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

# Resource Quality of Service 

## 1. 资源QoS简介

`request`值表示容器保证可被分配到资源。`limit`表示容器可允许使用的最大资源。Pod级别的`request`和`limit`是其所有容器的request和limit之和。

## 2. Requests and Limits

Pod可以指定`request`和`limit`资源。其中`0 <= request <=`[`Node Allocatable`](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/node/node-allocatable.md) & `request <= limit <= Infinity`。调度是基于`request`而不是`limit`，即如果Pod被成功调度，那么可以保证Pod分配到指定的 `request`的资源。Pod使用的资源能否超过指定的`limit`值取决于该资源是否可被压缩。

### 2.1. 可压缩的资源

- 目前只支持CPU
- pod可以保证获得它们请求的CPU数量，它们可能会也可能不会获得额外的CPU时间(取决于正在运行的其他作业)。因为目前CPU隔离是在容器级别而不是pod级别。

### 2.2. 不可压缩的资源

- 目前只支持内存
- pod将获得它们请求的内存数量，如果超过了它们的内存请求，它们可能会被杀死(如果其他一些pod需要内存)，但如果pod消耗的内存小于请求的内存，那么它们将不会被杀死(除非在系统任务或守护进程需要更多内存的情况下)。

## 3. QoS 级别

在机器资源超卖的情况下（limit的总量大于机器的资源容量），即CPU或内存耗尽，将不得不杀死部分不重要的容器。因此对容器分成了3个`QoS`的级别：`Guaranteed`,` Burstable`,  `Best-Effort`，三个级别的优先级依次递减。

当CPU资源无法满足，pod不会被杀死可能被短暂控制。

内存是不可压缩的资源，当内存耗尽的情况下，会依次杀死优先级低的容器。Guaranteed的级别最高，不会被杀死，除非容器使用量超过limit限值或者资源耗尽，已经没有更低级别的容器可驱逐。

### 3.1. Guaranteed

所有的容器的`limit`值和`request`值被配置且两者相等（如果只配置limit没有request，则request取值于limit）。

例如：

```yaml
# 示例1
containers:
  name: foo
    resources:
      limits:
        cpu: 10m
        memory: 1Gi
  name: bar
    resources:
      limits:
        cpu: 100m
        memory: 100Mi
# 示例2
containers:
  name: foo
    resources:
      limits:
        cpu: 10m
        memory: 1Gi
      requests:
        cpu: 10m
        memory: 1Gi

  name: bar
    resources:
      limits:
        cpu: 100m
        memory: 100Mi
      requests:
        cpu: 100m
        memory: 100Mi
```

### 3.2. Burstable

如果一个或多个容器的limit和request值被配置且两者不相等。

例如：

```yaml
# 示例1
containers:
  name: foo
    resources:
      limits:
        cpu: 10m
        memory: 1Gi
      requests:
        cpu: 10m
        memory: 1Gi

  name: bar
  
# 示例2
containers:
  name: foo
    resources:
      limits:
        memory: 1Gi

  name: bar
    resources:
      limits:
        cpu: 100m

# 示例3
containers:
  name: foo
    resources:
      requests:
        cpu: 10m
        memory: 1Gi

  name: bar
```

### 3.3. Best-Effort

所有的容器的`limit`和`request`值都没有配置。

例如：

```yaml
containers:
  name: foo
    resources:
  name: bar
    resources:
```

参考文章：
-  https://github.com/kubernetes/community/blob/master/contributors/design-proposals/node/resource-qos.md
  