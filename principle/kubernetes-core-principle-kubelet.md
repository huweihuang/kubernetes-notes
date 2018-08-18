---
title: "[Kubernetes] Kubernetes核心原理（四）之kubelet"
catalog: true
date: 2017-08-16 10:50:57
type: "categories"
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. kubelet简介

在kubernetes集群中，每个Node节点都会启动kubelet进程，用来处理Master节点下发到本节点的任务，管理Pod和其中的容器。kubelet会在API Server上注册节点信息，定期向Master汇报节点资源使用情况，并通过cAdvisor监控容器和节点资源。可以把kubelet理解成【Server-Agent】架构中的agent，是Node上的pod管家。

更多kubelet配置参数信息可参考kubelet --help

## 2. 节点管理

节点通过设置kubelet的启动参数“--register-node”，来决定是否向API Server注册自己，默认为true。可以通过kubelet --help或者查看kubernetes源码【cmd/kubelet/app/server.go中】来查看该参数。

**kubelet的配置文件**

默认配置文件在/etc/kubernetes/kubelet中，其中

- --api-servers：用来配置Master节点的IP和端口。
- --kubeconfig：用来配置kubeconfig的路径，kubeconfig文件常用来指定证书。
- --hostname-override：用来配置该节点在集群中显示的主机名。
- --node-status-update-frequency：配置kubelet向Master心跳上报的频率，默认为10s。

## 3. Pod管理

kubelet有几种方式获取自身Node上所需要运行的Pod清单。但本文只讨论通过API Server监听etcd目录，同步Pod列表的方式。

kubelet通过API Server Client使用WatchAndList的方式监听etcd中/registry/nodes/${当前节点名称}和/registry/pods的目录，将获取的信息同步到本地缓存中。

kubelet监听etcd，执行对Pod的操作，对容器的操作则是通过Docker Client执行，例如启动删除容器等。

**kubelet创建和修改Pod流程：**

1. 为该Pod创建一个数据目录。
2. 从API Server读取该Pod清单。
3. 为该Pod挂载外部卷（External Volume）
4. 下载Pod用到的Secret。
5. 检查运行的Pod，执行Pod中未完成的任务。
6. 先创建一个Pause容器，该容器接管Pod的网络，再创建其他容器。
7. Pod中容器的处理流程：
   1）比较容器hash值并做相应处理。
   2）如果容器被终止了且没有指定重启策略，则不做任何处理。
   3）调用Docker Client下载容器镜像，调用Docker Client运行容器。

## 4. 容器健康检查

Pod通过探针的方式来检查容器的健康状态，具体可参考[Pod详解#Pod健康检查](http://wiki.haplat.net/pages/viewpage.action?pageId=18233849#Pod详解-Pod健康检查)。

## 5. cAdvisor资源监控

kubelet通过cAdvisor获取本节点信息及容器的数据。cAdvisor为谷歌开源的容器资源分析工具，默认集成到kubernetes中。

cAdvisor自动采集CPU,内存，文件系统，网络使用情况，容器中运行的进程，默认端口为4194。可以通过Node IP+Port访问。

更多参考：[http://github.com/google/cadvisor](http://github.com/google/cadvisor)

 

参考《Kubernetes权威指南》

 