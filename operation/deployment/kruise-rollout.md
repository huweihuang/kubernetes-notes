---
title: "Kruise Rollout发布"
weight: 2
catalog: true
date: 2024-11-23 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. kruise-rollout简介

`金丝雀发布`是逐步将流量导向新版本的应用，以最小化风险。具体过程包括：

- 部署新版本的 Pod。
- 将一部分流量分配到新版本（通常比例很小）。
- 逐步增加新版本的流量比例，直到完成全量发布。

`Kruise Rollouts` 是一个 **Bypass(旁路)** 组件，提供 **高级渐进式交付功能** 。可以通过Kruise Rollouts插件来实现金丝雀发布的能力。

| 组件         | **Kruise Rollouts**                                          |
| ------------ | ------------------------------------------------------------ |
| 核心概念     | 增强现有的工作负载                                           |
| 架构         | Bypass                                                       |
| 插拔和热切换 | 是                                                           |
| 发布类型     | 多批次、金丝雀、A/B测试、全链路灰度                          |
| 工作负载类型 | Deployment、StatefulSet、CloneSet、Advanced StatefulSet、Advanced DaemonSet |
| 流量类型     | Ingress、GatewayAPI、CRD（需要 Lua 脚本）                    |
| 迁移成本     | 无需迁移工作负载和Pods                                       |
| HPA 兼容性   | 是                                                           |

# 2. 安装kruise-rollout

## 2.1. helm安装kruise-rollout

```bash
helm repo add openkruise https://openkruise.github.io/charts/

helm repo update

kubectl create ns openkruise
helm install kruise-rollout openkruise/kruise-rollout -n openkruise

# 升级到指定版本
helm upgrade kruise-rollout openkruise/kruise-rollout --version 0.5.0
```

查看部署结果

通过`helm`和`kubectl`的命令可以看到创建了几个`crd`和`kruise-rollout-controller-manager`的pod来提供rollout的功能。

```bash
# helm list -A
NAME          	NAMESPACE 	REVISION	UPDATED                                	STATUS  	CHART               	APP VERSION
kruise-rollout	openkruise	1       	2024-11-24 16:52:36.067327844 +0800 +08	deployed	kruise-rollout-0.5.0	0.5.0

# kubectl get po -n kruise-rollout
NAME                                                READY   STATUS    RESTARTS   AGE
kruise-rollout-controller-manager-875654888-rpxds   1/1     Running   0          87s
kruise-rollout-controller-manager-875654888-w75xj   1/1     Running   0          87s

# kubectl get crd |grep kruise
batchreleases.rollouts.kruise.io                      2024-11-24T08:52:36Z
rollouthistories.rollouts.kruise.io                   2024-11-24T08:52:36Z
rollouts.rollouts.kruise.io                           2024-11-24T08:52:36Z
trafficroutings.rollouts.kruise.io                    2024-11-24T08:52:36Z
```

## 2.2. 安装kubectl-kruise

kubectl-kruise用于执行rollout发版和回退等操作的二进制命令。

- `kubectl-kruise rollout approve`：执行下一批版本发布
- `kubectl-kruise rollout undo`：回退全部发版批次

```bash
wget https://github.com/openkruise/kruise-tools/releases/download/v1.1.7/kubectl-kruise-linux-amd64-v1.1.7.tar.gz
tar -zvxf kubectl-kruise-linux-amd64-v1.1.7.tar.gz
mv linux-amd64/kubectl-kruise /usr/local/bin/
```

# 3. 使用指南

先部署一个k8s deployment对象，例如部署10个nginx:1.26的容器。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx
  name: nginx
  namespace: default
spec:
  replicas: 10
  selector:
    matchLabels:
      app: nginx
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx:1.26
        imagePullPolicy: IfNotPresent
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
```

## 3.1. 创建发布策略(rollout对象)

我们以使用`多批次灰度发布`为例。

1. `workloadRef`定义作用于哪个deployment对象。
2. `strategy`定义发布策略。

以下是发布策略示例描述：

- 在第一批次：只升级 **1个Pod**；
- 在第二批次：升级 **50%** 的 Pods，即 **5个已更新的Pod**；
- 在第三批次：升级 **100%** 的 Pods，即 **10个已更新的Pod**。

```bash
$ kubectl apply -f - <<EOF
apiVersion: rollouts.kruise.io/v1beta1
kind: Rollout
metadata:
  name: rollouts-nginx
  namespace: default
spec:
  workloadRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx
  strategy:
    canary:
      enableExtraWorkloadForCanary: false
      steps:
      - replicas: 1
      - replicas: 50%
      - replicas: 100%
EOF
```

## 3.2. 升级发布版本(发布第一批次)

升级nginx:1.26到nginx:1.27

```bash
kubectl set image deployment nginx nginx=nginx:1.27
```

查看灰度结果：

```bash
# kubectl get rs -L pod-template-hash -w
NAME               DESIRED   CURRENT   READY   AGE   POD-TEMPLATE-HASH
nginx-68556bc579   1         1         1       8s    68556bc579   # nginx:1.27
nginx-d7f5d89c9    9         9         9       24m   d7f5d89c9    # nginx:1.26
```

查看rollout状态：

`rollout对象的状态主要描述了当前处于哪个rollout阶段及总状态和子阶段状态的信息。`

```yaml
# kubectl get rollout rollouts-nginx -oyaml
apiVersion: rollouts.kruise.io/v1beta1
kind: Rollout
metadata:
  name: rollouts-nginx
  namespace: default
spec:
  disabled: false
  strategy:
    canary:
      steps:
      - pause: {}
        replicas: 1
      - pause: {}
        replicas: 50%
      - pause: {}
        replicas: 100%
  workloadRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx
status:
  canaryStatus:
    canaryReadyReplicas: 1
    canaryReplicas: 1
    canaryRevision: 5c9556986d
    currentStepIndex: 1
    currentStepState: StepPaused  # 当前步骤状态
    lastUpdateTime: "2024-11-24T11:52:56Z"
    message: BatchRelease is at state Ready, rollout-id , step 1
    observedWorkloadGeneration: 36
    podTemplateHash: d7f5d89c9
    rolloutHash: 77cxd69w47b7bwddwv2w7vxvb4xxdbwcx9x289vw69w788w4w6z4x8dd4vbz2zbw
    stableRevision: 68556bc579
  conditions:
  - lastTransitionTime: "2024-11-24T11:52:47Z"
    lastUpdateTime: "2024-11-24T11:52:47Z"
    message: Rollout is in Progressing
    reason: InRolling
    status: "True"
    type: Progressing
  message: Rollout is in step(1/3), and you need manually confirm to enter the next
    step  # rollout信息
  observedGeneration: 2
  phase: Progressing   # 整体状态
```

## 3.3. 发布第二批次

```bash
kubectl-kruise rollout approve rollout/rollouts-nginx -n default
```

查看灰度结果：

```bash
# kubectl get rs -L pod-template-hash -w
NAME               DESIRED   CURRENT   READY   AGE     POD-TEMPLATE-HASH
nginx-68556bc579   5         5         5       7m24s   68556bc579  # nginx:1.27
nginx-d7f5d89c9    5         5         5       32m     d7f5d89c9   # nginx:1.26

# kubectl get po
NAME                     READY   STATUS    RESTARTS   AGE
nginx-68556bc579-24lpl   1/1     Running   0          7m34s  # nginx:1.27 第一批次
nginx-68556bc579-2dph8   1/1     Running   0          14s    # nginx:1.27 第二批次
nginx-68556bc579-57pqt   1/1     Running   0          14s    # nginx:1.27 第二批次
nginx-68556bc579-879s9   1/1     Running   0          14s    # nginx:1.27 第二批次
nginx-68556bc579-fwt52   1/1     Running   0          14s    # nginx:1.27 第二批次
nginx-d7f5d89c9-5fbfp    1/1     Running   0          30m    # 其余为第三批次
nginx-d7f5d89c9-gkz9p    1/1     Running   0          30m
nginx-d7f5d89c9-jhxwl    1/1     Running   0          30m
nginx-d7f5d89c9-vrqfz    1/1     Running   0          30m
nginx-d7f5d89c9-zk2sj    1/1     Running   0          30m
```

## 3.4. 发布第三批次

```bash
kubectl-kruise rollout approve rollout/rollouts-nginx -n default
```

查看结果：

```bash
# kubectl get rs -L pod-template-hash -w
NAME               DESIRED   CURRENT   READY   AGE   POD-TEMPLATE-HASH
nginx-68556bc579   10        10        10      12m   68556bc579   #  nginx:1.27
nginx-d7f5d89c9    0         0         0       37m   d7f5d89c9
```

## 3.5. 发布回滚

该回滚会把全部批次的pod都回滚到第一批发版前的版本。

```bash
kubectl-kruise rollout undo rollout/rollouts-nginx -n default
```

# 4. k8s对象变更

kruise-rollout的原理主要还是劫持`Deployment`和`ReplicaSet`的操作，例如在升级deployment的时候会把deployment原先的`strategy`策略放在annotations中暂存，再增加`paused=true`的参数暂停deployment的发布。在rollout全部结束后再恢复原先的deployment参数，主要包括`paused`和`strategy`。

以下是rollout中间阶段的deployment信息：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    batchrelease.rollouts.kruise.io/control-info: '{"apiVersion":"rollouts.kruise.io/v1beta1","kind":"BatchRelease","name":"rollouts-nginx","uid":"8f29624b-ab77-49d1-abbe-aa92bb3998e2","controller":true,"blockOwnerDeletion":true}'
    deployment.kubernetes.io/revision: "5"
    rollouts.kruise.io/deployment-extra-status: '{"updatedReadyReplicas":1,"expectedUpdatedReplicas":1}'
    rollouts.kruise.io/deployment-strategy: '{"rollingStyle":"Partition","rollingUpdate":{"maxUnavailable":"25%","maxSurge":"25%"},"partition":1}'  # deployment原本的strategy策略
    rollouts.kruise.io/in-progressing: '{"rolloutName":"rollouts-nginx"}'
  generation: 36
  labels:
    app: nginx
    rollouts.kruise.io/controlled-by-advanced-deployment-controller: "true"
    rollouts.kruise.io/stable-revision: 68556bc579
    rollouts.kruise.io/workload-type: deployment
  name: nginx
  namespace: default
spec:
  paused: true   # 增加了paused参数
  progressDeadlineSeconds: 600
  replicas: 10
  revisionHistoryLimit: 10
```

# 5. Rollout流量灰度

## 5.1. 添加pod 版本标签

为了适配`Apisix`或`Nginx`等k8s流量网关的灰度逻辑，我们通过`k8s service`的方式来动态获取Pod的IP（即endpoint）,其中包括全量pod，灰度pod和非灰度pod。因此我们在每次发版的deployment`给pod加上所属的版本标签`。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx
  name: nginx
  namespace: default
spec:
  replicas: 10
  selector:
    matchLabels:
      app: nginx
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: nginx
        version: "1.26"  # 增加pod对应的版本标签，用于service联动
    spec:
      containers:
      - image: nginx:1.26
        imagePullPolicy: IfNotPresent
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
```

## 5.2. 添加灰度pod的service

创建三个service来对应全量pod，灰度pod和非灰度pod。

**全量pod的service**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: default
spec:
  selector:
    app: nginx  # 全量pod的标签
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
```

**灰度pod的service**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-canary
  namespace: default
  labels:
    version: canary
spec:
  selector:
    app: nginx
    version: "1.27"  # 增加灰度版本的标签，对应灰度的pod
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
```

**非灰度pod的service**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-stable
  namespace: default
spec:
  selector:
    app: nginx
    version: "1.26"  # 增加非灰度版本的标签，对应非灰度的pod
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
```

## 5.3. 动态获取灰度的endpoint

通过以上service的配置，可以在灰度的过程中动态获取灰度pod的endpoint，然后动态集成到流量网关中。

- `全量pod的service`：在流量灰度前和流量灰度完成后可以把流量调度到这个service下的pod。
- `灰度pod的service`：可以设置把灰度流量调度到canary的service的pod。
- `非灰度pod的service`：可以把非灰度流量调度到stable的service的pod。

以下是灰度前后endpoint的变化：

```bash
# kubectl get endpoints
# 灰度前：canary的pod为0
nginx          10.0.1.139:80,10.0.1.202:80,10.0.1.203:80 + 7 more...      2d
nginx-canary   <none>                                                     2d
nginx-stable   10.0.1.139:80,10.0.1.202:80,10.0.1.203:80 + 7 more...      47h

# 灰度中：canary的pod增加
nginx          10.0.1.202:80,10.0.1.203:80,10.0.1.204:80 + 7 more...      2d     <none>
nginx-canary   10.0.1.5:80                                                2d     version=canary
nginx-stable   10.0.1.202:80,10.0.1.203:80,10.0.1.204:80 + 6 more...      47h    version=stable

# 灰度完成：stable的pod为0
NAME           ENDPOINTS                                                  AGE
nginx          10.0.1.139:80,10.0.1.202:80,10.0.1.203:80 + 7 more...      2d
nginx-canary   10.0.1.139:80,10.0.1.202:80,10.0.1.203:80 + 7 more...      2d
nginx-stable   <none>                                                     47h
```

# 6. 总结

k8s的deployment默认支持`金丝雀发布`，可以通过`kubectl rollout`的命令实现，通过配置deployment中的`maxSurge`和`maxUnavailable`来控制发版的节奏，可以通过以下命令来控制发版批次：

- `kubectl rollout pause`：暂停发版
- `kubectl rollout resume`：继续发版
- `kubectl rollout undo`：回滚版本

但相对来讲，控制粒度没有那么精确，而[OpenKruise](https://openkruise.io/zh/)的`Rollouts`插件提供了一种更加轻便，可控的发版工具，个人认为`最大的优势是配置简单，且无需迁移工作负载和Pods`，可以更好的集成到现有的容器平台中。因此可以通过该工具来实现金丝雀发版（多批次发版），实现灰度的能力。



参考：

- https://openkruise.io/zh/rollouts/introduction
- https://openkruise.io/zh/rollouts/installation
- https://openkruise.io/zh/rollouts/user-manuals/basic-usage