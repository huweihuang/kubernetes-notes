---
title: "Pod伸缩与升级"
weight: 7
catalog: true
date: 2017-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. Pod伸缩

k8s中RC的用来保持集群中始终运行指定数目的实例，通过RC的scale机制可以完成Pod的扩容和缩容（伸缩）。

## 1.1. 手动伸缩（scale）

```bash
kubectl scale rc redis-slave --replicas=3
```

## 1.2. 自动伸缩（HPA）

Horizontal Pod Autoscaler（HPA）控制器用于实现基于CPU使用率进行自动Pod伸缩的功能。HPA控制器基于Master的kube-controller-manager服务启动参数--horizontal-pod-autoscaler-sync-period定义是时长（默认30秒），周期性监控目标Pod的CPU使用率，并在满足条件时对ReplicationController或Deployment中的Pod副本数进行调整，以符合用户定义的平均Pod CPU使用率。Pod CPU使用率来源于heapster组件，因此需安装该组件。

可以通过kubectl autoscale命令进行快速创建或者使用yaml配置文件进行创建。创建之前需已存在一个RC或Deployment对象，并且该RC或Deployment中的Pod必须定义resources.requests.cpu的资源请求值，以便heapster采集到该Pod的CPU。

### 1.2.1. 通过kubectl autoscale创建

例如：

php-apache-rc.yaml

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: php-apache
spec:
  replicas: 1
  template:
    metadata:
      name: php-apache
      labels:
        app: php-apache
    spec:
      containers:
      - name: php-apache
        image: gcr.io/google_containers/hpa-example
        resources:
          requests:
            cpu: 200m
        ports:
        - containerPort: 80
```

创建php-apache的RC

```bash
kubectl create -f php-apache-rc.yaml
```

php-apache-svc.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: php-apache
spec:
  ports:
  - port: 80
  selector:
    app: php-apache
```

创建php-apache的Service

```bash
kubectl create -f php-apache-svc.yaml
```

创建HPA控制器

```bash
kubectl autoscale rc php-apache --min=1 --max=10 --cpu-percent=50
```

### 1.2.2. 通过yaml配置文件创建

hpa-php-apache.yaml

```yaml
apiVersion: v1
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: v1
    kind: ReplicationController
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
```

创建hpa

```bash
kubectl create -f hpa-php-apache.yaml
```

查看hpa

```bash
kubectl get hpa
```

# 2. Pod滚动升级

k8s中的滚动升级通过执行kubectl rolling-update命令完成，该命令创建一个新的RC（与旧的RC在同一个命名空间中），然后自动控制旧的RC中的Pod副本数逐渐减少为0，同时新的RC中的Pod副本数从0逐渐增加到附加值，但滚动升级中Pod副本数（包括新Pod和旧Pod）保持原预期值。

## 2.1. 通过配置文件实现

redis-master-controller-v2.yaml

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: redis-master-v2
  labels:
    name: redis-master
    version: v2
spec:
  replicas: 1
  selector:
    name: redis-master
    version: v2
  template:
    metadata:
      labels:
        name: redis-master
        version: v2
    spec:
      containers:
      - name: master
        image: kubeguide/redis-master:2.0
        ports:
        - containerPort: 6371
```

注意事项：

1. RC的名字（name）不能与旧RC的名字相同
2. 在selector中应至少有一个Label与旧的RC的Label不同，以标识其为新的RC。例如本例中新增了version的Label。

运行kubectl rolling-update

```bash
kubectl rolling-update redis-master -f redis-master-controller-v2.yaml
```

## 2.2. 通过kubectl rolling-update命令实现

```bash
kubectl rolling-update redis-master --image=redis-master:2.0
```

与使用配置文件实现不同在于，该执行结果旧的RC被删除，新的RC仍使用旧的RC的名字。

## 2.3. 升级回滚

kubectl rolling-update加参数--rollback实现回滚操作

```bash
kubectl rolling-update redis-master --image=kubeguide/redis-master:2.0 --rollback
```


参考文章

- 《Kubernetes权威指南》  
