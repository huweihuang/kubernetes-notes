---
title: "[Kubernetes] 理解kubernetes对象"
catalog: true
date: 2018-03-01 10:50:57
type: "categories"
subtitle:
header-img: "http://ozilwgpje.bkt.clouddn.com/article2.jpg"
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. kubernetes对象概述

kubernetes中的对象是一些持久化的实体，可以理解为是对`集群状态的描述或期望`。

包括：

- 集群中哪些node上运行了哪些容器化应用
- 应用的资源是否满足使用
- 应用的执行策略，例如重启策略、更新策略、容错策略等。

**kubernetes的对象是一种意图（期望）的记录，kubernetes会始终保持预期创建的对象存在和集群运行在预期的状态下**。

操作kubernetes对象（增删改查）需要通过[kubernetes API](https://kubernetes.io/docs/reference/)，一般有以下几种方式：

- `kubectl`命令工具
- `Client library`的方式，例如 [client-go](https://github.com/kubernetes/client-go)

## 2. Spec and Status

每个kubernetes对象的结构描述都包含`spec`和`status`两个部分。

- `spec`：该内容由用户提供，描述用户期望的对象特征及集群状态。
- `status`：该内容由kubernetes集群提供和更新，描述kubernetes对象的实时状态。

任何时候，kubernetes都会控制集群的实时状态`status`与用户的预期状态`spec`一致。

例如：当你定义`Deployment`的描述文件，指定集群中运行3个实例，那么kubernetes会始终保持集群中运行3个实例，如果任何实例挂掉，kubernetes会自动重建新的实例来保持集群中始终运行用户预期的3个实例。

## 3. 对象描述文件

当你要创建一个kubernetes对象的时候，需要提供该对象的描述信息`spec`，来描述你的对象在kubernetes中的预期状态。

一般使用kubernetes API来创建kubernetes对象，其中`spec`信息可以以`JSON`的形式存放在`request body`中，也可以以`.yaml`文件的形式通过`kubectl`工具创建。

例如，以下为`Deployment`对象对应的`yaml`文件：

```yaml
apiVersion: apps/v1beta2 # for versions before 1.8.0 use apps/v1beta1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
```

执行`kubectl create`的命令

```shell
#create command
kubectl create -f https://k8s.io/docs/user-guide/nginx-deployment.yaml --record
#output
deployment "nginx-deployment" created
```

## 4. 必须字段

在对象描述文件`.yaml`中，必须包含以下字段。

- apiVersion：kubernetes API的版本
- kind：kubernetes对象的类型
- metadata：唯一标识该对象的元数据，包括`name`，UID，可选的`namespace`
- spec：标识对象的详细信息，不同对象的`spec`的格式不同，可以嵌套其他对象的字段。



文章参考：

[https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/](https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/)