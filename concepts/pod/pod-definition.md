---
title: "Pod定义文件"
weight: 2
catalog: true
date: 2017-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---


# 1. Pod的基本用法

## 1.1. 说明

1. Pod实际上是**容器的集合**，在k8s中对运行容器的要求为：容器的主程序需要一直在前台运行，而不是后台运行。应用可以改造成前台运行的方式，例如Go语言的程序，直接运行二进制文件；java语言则运行主类；tomcat程序可以写个运行脚本。或者通过supervisor的进程管理工具，即supervisor在前台运行，应用程序由supervisor管理在后台运行。具体可参考[supervisord](http://blog.csdn.net/huwh_/article/details/77108245)。
2. 当多个应用之间是紧耦合的关系时，可以将多个应用一起放在一个Pod中，同个Pod中的多个容器之间互相访问可以通过localhost来通信（可以把Pod理解成一个虚拟机，共享网络和存储卷）。

## 1.2. Pod相关命令

| 操作        | 命令                                       | 说明                   |
| --------- | ---------------------------------------- | -------------------- |
| 创建        | kubectl create -f frontend-localredis-pod.yaml |                      |
| 查询Pod运行状态 | kubectl get pods --namespace=`<NAMESPACE>` |                      |
| 查询Pod详情   | kebectl describe pod `<POD_NAME>` --namespace=`<NAMESPACE>` | 该命令常用来排查问题，查看Event事件 |
| 删除        | kubectl delete pod `<POD_NAME>` ;kubectl delete pod --all |                      |
| 更新        | kubectl replace pod.yaml                 |      -                |

# 2. Pod的定义文件

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: string
  namaspace: string
  labels:
  - name: string
      annotations:
  - name: string
  spec:
    containers:
  - name: string
    images: string
    imagePullPolice: [Always | Never | IfNotPresent]
    command: [string]
    args: [string]
    workingDir: string
    volumeMounts:
    - name: string
      mountPath: string
      readOnly: boolean
      ports:
    - name: string
      containerPort: int
      hostPort: int
      protocol: string
      env:
    - name: string
      value: string
      resources:
      limits:
        cpu: string
        memory: string
      requests:
        cpu: string
        memory: string
      livenessProbe:
      exec:
        command: [string]
      httpGet:
        path: string
        port: int
        host: string
        scheme: string
        httpHeaders:
        - name: string
          value: string
          tcpSocket:
            port: int
          initialDelaySeconds: number
          timeoutSeconds: number
          periodSeconds: number
          successThreshold: 0
          failureThreshold: 0
          securityContext:
          privileged: false
          restartPolicy: [Always | Never | OnFailure]   
          nodeSelector: object
          imagePullSecrets:
  - name: string
      hostNetwork: false
        volumes:
  - name: string
    emptyDir: {}
    hostPath:
      path: string
    secret:
      secretName: string
      items:
      - key: string
        path: string
        configMap:
          name: string
          items:
      - key: string
        path: string
```


# 3. 静态pod

静态Pod是由kubelet进行管理，仅存在于特定Node上的Pod。它们不能通过API Server进行管理，无法与ReplicationController、Deployment或DaemonSet进行关联，并且kubelet也无法对其健康检查。

静态Pod总是由kubelet创建，并且总在kubelet所在的Node上运行。

创建静态Pod的方式：

## 3.1. 通过配置文件方式

需要设置kubelet的启动参数“–config”，指定kubelet需要监控的配置文件所在目录，kubelet会定期扫描该目录，并根据该目录的.yaml或.json文件进行创建操作。静态Pod无法通过API Server删除（若删除会变成pending状态），如需删除该Pod则将yaml或json文件从这个目录中删除。

例如：

配置目录为/etc/kubelet.d/，配置启动参数：--config=/etc/kubelet.d/，该目录下放入static-web.yaml。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  labels:
    name: static-web
spec:
  containers:
  - name: static-web
  image: nginx
  ports:
  - name: web
    containerPort: 80
```


参考文章

- 《Kubernetes权威指南》  
