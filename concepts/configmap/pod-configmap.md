---
title: "ConfigMap"
weight: 1
catalog: true
date: 2017-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# Pod的配置管理

Kubernetes v1.2的版本提供统一的集群配置管理方案–ConfigMap。

## 1. ConfigMap：容器应用的配置管理

使用场景：

1. 生成为容器内的环境变量。
2. 设置容器启动命令的启动参数（需设置为环境变量）。
3. 以Volume的形式挂载为容器内部的文件或目录。

ConfigMap以一个或多个key:value的形式保存在kubernetes系统中供应用使用，既可以表示一个变量的值（例如：apploglevel=info），也可以表示完整配置文件的内容（例如：server.xml=<?xml...>...）。

可以通过yaml配置文件或者使用kubectl create configmap命令的方式创建ConfigMap。

## 2. 创建ConfigMap

### 2.1. 通过yaml文件方式

cm-appvars.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cm-appvars
data:
  apploglevel: info
  appdatadir: /var/data
```

常用命令

kubectl create -f cm-appvars.yaml

kubectl get configmap

kubectl describe configmap cm-appvars

kubectl get configmap cm-appvars -o yaml

### 2.2. 通过kubectl命令行方式

通过kubectl create configmap创建，使用参数--from-file或--from-literal指定内容，可以在一行中指定多个参数。

1）通过--from-file参数从文件中进行创建，可以指定key的名称，也可以在一个命令行中创建包含多个key的ConfigMap。

kubectl create configmap NAME --from-file=[key=]source --from-file=[key=]source

2）通过--from-file参数从目录中进行创建，该目录下的每个配置文件名被设置为key，文件内容被设置为value。

kubectl create configmap NAME --from-file=config-files-dir

3）通过--from-literal从文本中进行创建，直接将指定的key=value创建为ConfigMap的内容。

kubectl create configmap NAME --from-literal=key1=value1 --from-literal=key2=value2

 

容器应用对ConfigMap的使用有两种方法：

1. 通过环境变量获取ConfigMap中的内容。
2. 通过Volume挂载的方式将ConfigMap中的内容挂载为容器内部的文件或目录。

### 2.3. 通过环境变量的方式

ConfigMap的yaml文件:cm-appvars.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cm-appvars
data:
  apploglevel: info
  appdatadir: /var/data
```

Pod的yaml文件：cm-test-pod.yaml

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cm-test-pod
spec:
  containers:
  - name: cm-test
    image: busybox
    command: ["/bin/sh","-c","env|grep APP"]
    env:
    - name: APPLOGLEVEL
      valueFrom:
        configMapKeyRef:
          name: cm-appvars
          key: apploglevel
    - name: APPDATADIR
      valueFrom:
        configMapKeyRef:
          name: cm-appvars
          key: appdatadir
```

创建命令：

kubectl create -f cm-test-pod.yaml

kubectl get pods --show-all

kubectl logs cm-test-pod

## 3. 使用ConfigMap的限制条件

- ConfigMap必须在Pod之前创建
- ConfigMap也可以定义为属于某个Namespace。只有处于相同Namespace中的Pod可以引用它。
- kubelet只支持可以被API Server管理的Pod使用ConfigMap。静态Pod无法引用。
- 在Pod对ConfigMap进行挂载操作时，容器内只能挂载为“目录”，无法挂载为文件。

  
参考文章

- 《Kubernetes权威指南》  
