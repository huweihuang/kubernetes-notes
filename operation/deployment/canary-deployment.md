---
title: "金丝雀发布"
weight: 1
catalog: true
date: 2023-05-31 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# Deployment配置金丝雀发布

金丝雀发布是指控制更新过程中的滚动节奏，通过“暂停”（pause）或“继续”（resume）更新发布操作。通过一小部分的版本发布实例来观察新版本是否有异常，如果没有异常则依次发布剩余的实例。

# 1. 设置发版节奏

主要是以下字段的设置：

- **maxSurge**：最大发版实例数，可以创建的超出期望 Pod 个数的 Pod 数量。可以是百分比或者是数字。
- **maxUnavailable**：最大不可用实例数。可以是百分比或数字。
- **minReadySeconds** ：新建的 Pod 在没有任何容器崩溃的情况下就绪并被系统视为可用的最短秒数。 默认为 0（Pod 就绪后即被视为可用）。可将该值设置为5-10（秒），防止新起的pod发生crash，进而影响服务的可用性，保证集群在更新过程的稳定性。

```bash
# 例如将maxSurge设置为1，maxUnavailable设置为0
$ kubectl patch deployment myapp-deploy -p '{"spec": {"strategy": {"rollingUpdate": {"maxSurge": 1, "maxUnavailable": 0}}}}'
```

# 2. 升级版本并暂停

```bash
kubectl set image deployment myapp-deploy myapp=kubernetes/myapp:v3 && \
kubectl rollout pause deployments myapp-deploy
```

# 3. 查看升级状态

```bash
$ kubectl rollout status deployment myapp-deploy
Waiting for deployment "myapp-deploy" rollout to finish: 1 out of 3 new replicas have been updated...
```

# 4. 恢复继续发版

观察灰度的实例的流量是否正常，如果正常则继续发版，如果不正常则回滚之前的升级。

```bash
$ kubectl rollout resume deployments myapp-deploy
```

# 5. 回滚发布

## 5.1. 回滚上一个版本

```bash
kubectl rollout undo deployments myapp-deploy
```

## 5.2. 查看历史版本

```bash
$ kubectl rollout history deployment myapp-deploy
deployment.apps/myapp-deploy
REVISION  CHANGE-CAUSE
3         <none>
5         <none>
6         <none>
```

## 5.3. 回滚指定版本

```bash
kubectl rollout undo deployment myapp-deploy --to-revision 3
```





参考：

- https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/deployment/
- https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/manage-deployment/#canary-deployments
- https://kubernetes.renkeju.com/chapter_5/5.3.4.Canary_release.html
- https://kubernetes.io/zh-cn/docs/reference/kubernetes-api/workload-resources/deployment-v1/#DeploymentSpec
