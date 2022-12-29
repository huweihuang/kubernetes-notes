---
title: "资源配额"
linkTitle: "Pod限额"
weight: 2
catalog: true
date: 2018-6-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

# Pod限额（LimitRange） 

> `ResourceQuota`对象是限制某个namespace下`所有Pod(容器)`的资源限额
>
> `LimitRange`对象是限制某个namespace`单个Pod(容器`)的资源限额

`LimitRange`对象用来定义某个`命名空间`下某种`资源对象`的使用限额，其中资源对象包括：`Pod`、`Container`、`PersistentVolumeClaim`。

## 1. 为namespace配置CPU和内存的默认值

如果在一个拥有默认内存或CPU限额的命名空间中创建一个容器，并且这个容器未指定它自己的内存或CPU的`limit`， 它会被分配这个默认的内存或CPU的`limit`。既没有设置pod的`limit`和`request`才会分配默认的内存或CPU的`request`。

### 1.1. namespace的内存默认值

```shell
# 创建namespace
$ kubectl create namespace default-mem-example

# 创建LimitRange
$ cat memory-defaults.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: mem-limit-range
spec:
  limits:
  - default:
      memory: 512Mi
    defaultRequest:
      memory: 256Mi
    type: Container
  
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/memory-defaults.yaml --namespace=default-mem-example

# 创建Pod,未指定内存的limit和request
$ cat memory-defaults-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: default-mem-demo
spec:
  containers:
  - name: default-mem-demo-ctr
    image: nginx
    
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/memory-defaults-pod.yaml --namespace=default-mem-example

# 查看Pod
$ kubectl get pod default-mem-demo --output=yaml --namespace=default-mem-example
containers:
- image: nginx
  imagePullPolicy: Always
  name: default-mem-demo-ctr
  resources:
    limits:
      memory: 512Mi
    requests:
      memory: 256Mi
```

### 1.2. namespace的CPU默认值

```shell
# 创建namespace
$ kubectl create namespace default-cpu-example

# 创建LimitRange
$ cat cpu-defaults.yaml 
apiVersion: v1
kind: LimitRange
metadata:
  name: cpu-limit-range
spec:
  limits:
  - default:
      cpu: 1
    defaultRequest:
      cpu: 0.5
    type: Container
    
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/cpu-defaults.yaml --namespace=default-cpu-example    

# 创建Pod，未指定CPU的limit和request
$ cat cpu-defaults-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: default-cpu-demo
spec:
  containers:
  - name: default-cpu-demo-ctr
    image: nginx

$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/cpu-defaults-pod.yaml --namespace=default-cpu-example

# 查看Pod
$ kubectl get pod default-cpu-demo --output=yaml --namespace=default-cpu-example
containers:
- image: nginx
  imagePullPolicy: Always
  name: default-cpu-demo-ctr
  resources:
    limits:
      cpu: "1"
    requests:
      cpu: 500m
```

### 1.3 说明

1. 如果没有指定pod的`request`和`limit`，则创建的pod会使用`LimitRange`对象定义的默认值（request和limit）
2. 如果指定pod的`limit`但未指定`request`，则创建的pod的`request`值会取`limit`的值，而不会取LimitRange对象定义的request默认值。
3. 如果指定pod的`request`但未指定`limit`，则创建的pod的`limit`值会取`LimitRange`对象定义的`limit`默认值。

**默认Limit和request的动机**

如果命名空间具有`资源配额（ResourceQuota）`, 它为内存限额（CPU限额）设置默认值是有意义的。 以下是资源配额对命名空间施加的两个限制：

- 在命名空间运行的每一个容器必须有它自己的内存限额（CPU限额）。
- 在命名空间中所有的容器使用的内存总量（CPU总量）不能超出指定的限额。

如果一个容器没有指定它自己的内存限额（CPU限额），它将被赋予默认的限额值，然后它才可以在被配额限制的命名空间中运行。

## 2. 为namespace配置CPU和内存的最大最小值

### 2.1. 内存的最大最小值

**创建LimitRange**

```shell
# 创建namespace
$ kubectl create namespace constraints-mem-example

# 创建LimitRange
$ cat memory-constraints.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: mem-min-max-demo-lr
spec:
  limits:
  - max:
      memory: 1Gi
    min:
      memory: 500Mi
    type: Container
 
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/memory-constraints.yaml --namespace=constraints-mem-example

# 查看LimitRange
$ kubectl get limitrange cpu-min-max-demo --namespace=constraints-mem-example --output=yaml
...
  limits:
  - default:
      memory: 1Gi
    defaultRequest:
      memory: 1Gi
    max:
      memory: 1Gi
    min:
      memory: 500Mi
    type: Container
...
# LimitRange设置了最大最小值，但没有设置默认值，也会被自动设置默认值。
```

**创建符合要求的Pod**

```shell
# 创建符合要求的Pod
$ cat memory-constraints-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-mem-demo
spec:
  containers:
  - name: constraints-mem-demo-ctr
    image: nginx
    resources:
      limits:
        memory: "800Mi"
      requests:
        memory: "600Mi"
 
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/memory-constraints-pod.yaml --namespace=constraints-mem-example

# 查看Pod
$ kubectl get pod constraints-mem-demo --output=yaml --namespace=constraints-mem-example
...
resources:
  limits:
     memory: 800Mi
  requests:
    memory: 600Mi
...
```

**创建超过最大内存limit的pod**

```shell
$ cat memory-constraints-pod-2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-mem-demo-2
spec:
  containers:
  - name: constraints-mem-demo-2-ctr
    image: nginx
    resources:
      limits:
        memory: "1.5Gi"  # 超过最大值 1Gi
      requests:
        memory: "800Mi"
        
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/memory-constraints-pod-2.yaml --namespace=constraints-mem-example

# Pod创建失败，因为容器指定的limit过大
Error from server (Forbidden): error when creating "docs/tasks/administer-cluster/memory-constraints-pod-2.yaml":
pods "constraints-mem-demo-2" is forbidden: maximum memory usage per Container is 1Gi, but limit is 1536Mi.
```

**创建小于最小内存request的Pod**

```shell
$ cat memory-constraints-pod-3.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-mem-demo-3
spec:
  containers:
  - name: constraints-mem-demo-3-ctr
    image: nginx
    resources:
      limits:
        memory: "800Mi"
      requests:
        memory: "100Mi"   # 小于最小值500Mi
        
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/memory-constraints-pod-3.yaml --namespace=constraints-mem-example         

# Pod创建失败，因为容器指定的内存request过小
Error from server (Forbidden): error when creating "docs/tasks/administer-cluster/memory-constraints-pod-3.yaml":
pods "constraints-mem-demo-3" is forbidden: minimum memory usage per Container is 500Mi, but request is 100Mi.
```

**创建没有指定任何内存limit和request的pod**

```shell
$ cat memory-constraints-pod-4.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-mem-demo-4
spec:
  containers:
  - name: constraints-mem-demo-4-ctr
    image: nginx

$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/memory-constraints-pod-4.yaml --namespace=constraints-mem-example

# 查看Pod
$ kubectl get pod constraints-mem-demo-4 --namespace=constraints-mem-example --output=yaml
...
resources:
  limits:
    memory: 1Gi
  requests:
    memory: 1Gi
...
```

容器没有指定自己的 CPU 请求和限制，所以它将从 LimitRange 获取默认的 CPU 请求和限制值。

### 2.2. CPU的最大最小值

**创建LimitRange**

```shell
# 创建namespace
$ kubectl create namespace constraints-cpu-example

# 创建LimitRange
$ cat cpu-constraints.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: cpu-min-max-demo-lr
spec:
  limits:
  - max:
      cpu: "800m"
    min:
      cpu: "200m"
    type: Container
    
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/cpu-constraints.yaml --namespace=constraints-cpu-example

# 查看LimitRange
$ kubectl get limitrange cpu-min-max-demo-lr --output=yaml --namespace=constraints-cpu-example
...
limits:
- default:
    cpu: 800m
  defaultRequest:
    cpu: 800m
  max:
    cpu: 800m
  min:
    cpu: 200m
  type: Container
...

```

**创建符合要求的Pod**

```shell
$ cat cpu-constraints-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-cpu-demo
spec:
  containers:
  - name: constraints-cpu-demo-ctr
    image: nginx
    resources:
      limits:
        cpu: "800m"
      requests:
        cpu: "500m"
        
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/cpu-constraints-pod.yaml --namespace=constraints-cpu-example

# 查看Pod
$ kubectl get pod constraints-cpu-demo --output=yaml --namespace=constraints-cpu-example
...
resources:
  limits:
    cpu: 800m
  requests:
    cpu: 500m
...
```

**创建超过最大CPU limit的Pod**

```shell
$ cat cpu-constraints-pod-2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-cpu-demo-2
spec:
  containers:
  - name: constraints-cpu-demo-2-ctr
    image: nginx
    resources:
      limits:
        cpu: "1.5"
      requests:
        cpu: "500m"
        
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/cpu-constraints-pod-2.yaml --namespace=constraints-cpu-example

# Pod创建失败，因为容器指定的CPU limit过大
Error from server (Forbidden): error when creating "docs/tasks/administer-cluster/cpu-constraints-pod-2.yaml":
pods "constraints-cpu-demo-2" is forbidden: maximum cpu usage per Container is 800m, but limit is 1500m.
```

**创建小于最小CPU request的Pod**

```shell
$ cat cpu-constraints-pod-3.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-cpu-demo-4
spec:
  containers:
  - name: constraints-cpu-demo-4-ctr
    image: nginx
    resources:
      limits:
        cpu: "800m"
      requests:
        cpu: "100m"
        
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/cpu-constraints-pod-3.yaml --namespace=constraints-cpu-example

# Pod创建失败，因为容器指定的CPU request过小
Error from server (Forbidden): error when creating "docs/tasks/administer-cluster/cpu-constraints-pod-3.yaml":
pods "constraints-cpu-demo-4" is forbidden: minimum cpu usage per Container is 200m, but request is 100m.
```

**创建没有指定任何CPU limit和request的pod**

```shell
$ cat cpu-constraints-pod-4.yaml
apiVersion: v1
kind: Pod
metadata:
  name: constraints-cpu-demo-4
spec:
  containers:
  - name: constraints-cpu-demo-4-ctr
    image: vish/stress
    
$ kubectl create -f https://k8s.io/docs/tasks/administer-cluster/cpu-constraints-pod-4.yaml --namespace=constraints-cpu-example    

# 查看Pod
kubectl get pod constraints-cpu-demo-4 --namespace=constraints-cpu-example --output=yaml
...
resources:
  limits:
    cpu: 800m
  requests:
    cpu: 800m
...
```

容器没有指定自己的 CPU 请求和限制，所以它将从 LimitRange 获取默认的 CPU 请求和限制值。

### 2.3. 说明

LimitRange 在 namespace 中施加的最小和最大内存（CPU）限制只有在创建和更新 Pod 时才会被应用。改变 LimitRange 不会对之前创建的 Pod 造成影响。

Kubernetes 都会执行下列步骤：

- 如果容器没有指定自己的内存（CPU）请求（request）和限制（limit），系统将会为其分配默认值。
- 验证容器的内存（CPU）请求大于等于最小值。
- 验证容器的内存（CPU）限制小于等于最大值。

参考文章：
- https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/

- https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/cpu-default-namespace/

- https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-constraint-namespace/

- https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/cpu-constraint-namespace/

- https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace/
  