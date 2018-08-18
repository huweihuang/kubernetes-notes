---
title: "[Kubernetes] kubernetes指定节点调度与隔离"
catalog: true
date: 2018-6-23 16:22:24
type: "tags"
subtitle:
header-img: "http://ozilwgpje.bkt.clouddn.com/scenery/building.jpg?imageslim"
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. NodeSelector

### 1.1. 概念

如果需要`限制Pod到指定的Node`上运行，则可以给Node打标签并给Pod配置NodeSelector。

### 1.2. 使用方式

#### 1.2.1. 给Node打标签

```shell
# get node的name
kubectl get nodes

# 设置Label
kubectl label nodes <node-name> <label-key>=<label-value>
# 例如
kubectl label nodes node-1 disktype=ssd

# 查看Node的Label
kubectl get nodes --show-labels
```

#### 1.2.2. 给Pod设置NodeSelector

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    env: test
spec:
  containers:
  - name: nginx
    image: nginx
    imagePullPolicy: IfNotPresent
  nodeSelector:
    disktype: ssd    # 对应Node的Label
```

### 1.3. 亲和性（Affinity）和反亲和性（Anti-affinity）

> 待补充

## 2. Taint 和 Toleration

### 2.1. 概念

`nodeSelector`可以通过`打标签`的形式让Pod被调度到指定的Node上，`Taint `则相反，它使节点能够排斥一类特定的Pod，除非Pod被指定了`toleration`的标签。（`taint`即污点，Node被打上污点；只有容忍[toleration]这些污点的Pod才可能被调度到该Node）。

### 2.2. 使用方式

#### 2.2.1. kubectl taint

```shell
# 给节点增加一个taint，它的key是<key>，value是<value>，effect是NoSchedule。
kubectl taint nodes <node_name> <key>=<value>:NoSchedule
```

只有拥有和这个`taint`相匹配的`toleration`的pod才能够被分配到 `node_name` 这个节点。

例如，在 `PodSpec` 中定义 pod 的 toleration：

```yaml
tolerations:
- key: "key"
  operator: "Equal"
  value: "value"
  effect: "NoSchedule"
```

```yaml
tolerations:
- key: "key"
  operator: "Exists"
  effect: "NoSchedule"
```

#### 2.2.2. 匹配规则：

一个 toleration 和一个 taint 相“匹配”是指它们有一样的 key 和 effect ，并且：

- 如果 `operator` 是 `Exists` （此时 toleration 不能指定 `value`）
- 如果 `operator` 是 `Equal` ，则它们的 `value` 应该相等

**特殊情况：**

- 如果一个 toleration 的 `key` 为空且 operator 为 `Exists` ，表示这个 toleration 与任意的 key 、 value 和 effect 都匹配，即这个 toleration 能容忍任意 taint。

  ```yaml
  tolerations:
  - operator: "Exists"
  ```

- 如果一个 toleration 的 `effect` 为空，则 `key` 值与之相同的相匹配 taint 的 `effect` 可以是任意值。

  ```yaml
  tolerations:
  - key: "key"
    operator: "Exists"
  ```

一个节点可以设置多个taint，一个pod也可以设置多个toleration。Kubernetes 处理多个 taint 和 toleration 的过程就像一个过滤器：从一个节点的所有 taint 开始遍历，过滤掉那些 pod 中存在与之相匹配的 toleration 的 taint。余下未被过滤的 taint 的 effect 值决定了 pod 是否会被分配到该节点，特别是以下情况：

- 如果未被过滤的 taint 中存在一个以上 effect 值为 `NoSchedule` 的 taint，则 Kubernetes 不会将 pod 分配到该节点。
- 如果未被过滤的 taint 中不存在 effect 值为 `NoSchedule` 的 taint，但是存在 effect 值为 `PreferNoSchedule` 的 taint，则 Kubernetes 会*尝试*将 pod 分配到该节点。
- 如果未被过滤的 taint 中存在一个以上 effect 值为 `NoExecute` 的 taint，则 Kubernetes 不会将 pod 分配到该节点（如果 pod 还未在节点上运行），或者将 pod 从该节点驱逐（如果 pod 已经在节点上运行）。

#### 2.2.3. effect的类型

- `NoSchedule`：只有拥有和这个 taint 相匹配的 toleration 的 pod 才能够被分配到这个节点。

- `PreferNoSchedule`：系统会*尽量*避免将 pod 调度到存在其不能容忍 taint 的节点上，但这不是强制的。

- `NoExecute` ：任何不能忍受这个 taint 的 pod 都会马上被驱逐，任何可以忍受这个 taint 的 pod 都不会被驱逐。Pod可指定属性 `tolerationSeconds` 的值，表示pod 还能继续在节点上运行的时间。

  ```yaml
  tolerations:
  - key: "key1"
    operator: "Equal"
    value: "value1"
    effect: "NoExecute"
    tolerationSeconds: 3600
  ```

### 2.3. 使用场景

#### 2.3.1. 专用节点

```shell
kubectl taint nodes <nodename> dedicated=<groupName>:NoSchedule
```

先给Node添加taint，然后给Pod添加相对应的 toleration，则该Pod可调度到taint的Node，也可调度到其他节点。

如果想**让Pod只调度某些节点且某些节点只接受对应的Pod**，则需要在Node上添加`Label`（例如：`dedicated=groupName`），同时给Pod的`nodeSelector`添加对应的`Label`。

#### 2.3.2. 特殊硬件节点

如果某些节点配置了特殊硬件（例如CPU），希望不使用这些特殊硬件的Pod不被调度该Node，以便保留必要资源。即可给Node设置`taint`和`label`，同时给Pod设置`toleration`和`label`来使得这些Node专门被指定Pod使用。

```shell
# kubectl taint
kubectl taint nodes nodename special=true:NoSchedule 
# 或者
kubectl taint nodes nodename special=true:PreferNoSchedule
```

#### 2.3.3. 基于taint驱逐

effect 值 `NoExecute` ，它会影响已经在节点上运行的 pod，即根据策略对Pod进行驱逐。

- 如果 pod 不能忍受effect 值为 `NoExecute` 的 taint，那么 pod 将马上被驱逐
- 如果 pod 能够忍受effect 值为 `NoExecute` 的 taint，但是在 toleration 定义中没有指定 `tolerationSeconds`，则 pod 还会一直在这个节点上运行。
- 如果 pod 能够忍受effect 值为 `NoExecute` 的 taint，而且指定了 `tolerationSeconds`，则 pod 还能在这个节点上继续运行这个指定的时间长度。



参考：

- https://kubernetes.io/docs/concepts/configuration/assign-pod-node/

- https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/