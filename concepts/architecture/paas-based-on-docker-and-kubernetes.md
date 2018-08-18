---
title: "[Kubernetes] 基于Docker及Kubernetes技术构建容器云（PaaS）平台"
catalog: true
date: 2017-09-19 10:50:57
type: "categories"
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

[编者的话]

目前很多的容器云平台通过Docker及Kubernetes等技术提供应用运行平台，从而实现运维自动化，快速部署应用、弹性伸缩和动态调整应用环境资源，提高研发运营效率。

从宏观到微观（从抽象到具体）的思路来理解：云计算→PaaS→ App Engine→XAE[XXX App Engine] （XAE泛指一类应用运行平台，例如GAE、SAE、BAE等）。

本文简要介绍了与容器云相关的几个重要概念：PaaS、App Engine、Dokcer、Kubernetes。

## 1. PaaS概述

### 1.1. PaaS概念

1. PaaS(Platform as a service)，平台即服务，指将软件研发的平台（或业务基础平台）作为一种服务，以SaaS的模式提交给用户。
2. PaaS是云计算服务的其中一种模式，云计算是一种按使用量付费的模式的服务，类似一种租赁服务，服务可以是基础设施计算资源（IaaS），平台（PaaS），软件（SaaS）。租用IT资源的方式来实现业务需要，如同水力、电力资源一样，计算、存储、网络将成为企业IT运行的一种被使用的资源，无需自己建设，可按需获得。
3. PaaS的实质是将互联网的资源服务化为可编程接口，为第三方开发者提供有商业价值的资源和服务平台。简而言之，**IaaS就是卖硬件及计算资源，PaaS就是卖开发、运行环境，SaaS就是卖软件**。

### 1.2. IaaS/PaaS/SaaS说明

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577867/article/caas/cloud-computing.jpg" width="40%">

| 类型                                       | 说明                     | 比喻          | 例子                   |
| ---------------------------------------- | ---------------------- | ----------- | -------------------- |
| IaaS:Infrastructure-as-a-Service(基础设施即服务) | 提供的服务是计算基础设施           | 地皮，需要自己盖房子  | Amazon EC2（亚马逊弹性云计算） |
| PaaS: Platform-as-a-Service(平台即服务)       | 提供的服务是软件研发的平台或业务基础平台   | 商品房，需要自己装修  | GAE（谷歌开发者平台）         |
| SaaS: Software-as-a-Service(软件即服务)       | 提供的服务是运行在云计算基础设施上的应用程序 | 酒店套房，可以直接入住 | 谷歌的Gmail邮箱           |

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577869/article/caas/paas.jpg" width="70%">

### 1.3. PaaS的特点（三种层次）

| 特点    | 说明                                  |
| ----- | ----------------------------------- |
| 平台即服务 | PaaS提供的服务就是个基础平台，一个环境，而不是具体的应用      |
| 平台及服务 | 不仅提供平台，还提供对该平台的技术支持、优化等服务           |
| 平台级服务 | “平台级服务”即强大稳定的平台和专业的技术支持团队，保障应用的稳定使用 |

## 2. App Engine概述

### 2.1. App Engine概念

App Engine是PaaS模式的一种实现方式，App Engine将应用运行所需的 IT 资源和基础设施以服务的方式提供给用户，包括了中间件服务、资源管理服务、弹性调度服务、消息服务等多种服务形式。App Engine的目标是对应用提供完整生命周期（包括设计、开发、测试和部署等阶段）的支持，从而减少了用户在购置和管理应用生命周期内所必须的软硬件以及部署应用和IT 基础设施的成本，同时简化了以上工作的复杂度。常见的App Engine有：GAE(Google App Engine)，SAE(Sina App Engine)，BAE(Baidu App Engine)。

App Engine利用虚拟化与自动化技术实现快速搭建部署应用运行环境和动态调整应用运行时环境资源这两个目标。一方面实现即时部署以及快速回收，降低了环境搭建时间，避免了手工配置错误，快速重复搭建环境，及时回收资源， 减少了低利用率硬件资源的空置。另一方面，根据应用运行时的需求对应用环境进行动态调整，实现了应用平台的弹性扩展和自优化，减少了非高峰时硬件资源的空置。

简而言之，**App Engine主要目标是：Easy to maintain(维护), Easy to scale(扩容), Easy to build(构建)**。

### 2.2. 架构设计

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577868/article/caas/AppEngine.jpg" width="80%">

### 2.3. 组成模块说明

| 组成模块                    | 模块说明                                    |
| ----------------------- | --------------------------------------- |
| App Router[流量接入层]       | 接收用户请求，并转发到不同的App Runtime。              |
| App Runtime[应用运行层]      | 应用运行环境，为各个应用提供基本的运行引擎，从而让app能够运行起来。     |
| Services[基础服务层]         | 各个通用基础服务，主要是对主流的服务提供通用的接入，例如数据库等。       |
| Platform Control[平台控制层] | 整个平台的控制中心，实现业务调度，弹性扩容、资源审计、集群管理等相关工作。   |
| Manage System[管理界面层]    | 提供友好可用的管理操作界面方便平台管理员来控制管理整个平台。          |
| Platform Support[平台支持层] | 为应用提供相关的支持，比如应用监控、问题定位、分布式日志重建、统计分析等。   |
| Log Center[日志中心]        | 实时收集相关应用及系统的日志（日志收集），提供实时计算和分析平台（日志处理）。 |
| Code Center[代码中心]       | 完成代码存储、部署上线相关的工作。                       |

## 3. 容器云平台技术栈

| 功能组成部分 | 使用工具                                  |
| ------ | ------------------------------------- |
| 应用载体   | Docker                                |
| 编排工具   | Kubernetes                            |
| 配置数据   | Etcd                                  |
| 网络管理   | Flannel                               |
| 存储管理   | Ceph                                  |
| 底层实现   | Linux内核的Namespace[资源隔离]和CGroups[资源控制] |

- **Namespace[资源隔离]**
  Namespaces机制提供一种资源隔离方案。PID,IPC,Network等系统资源不再是全局性的，而是属于某个特定的Namespace。每个namespace下的资源对于其他namespace下的资源都是透明，不可见的。
- **CGroups[资源控制]**
  CGroup（control group）是将任意进程进行分组化管理的Linux内核功能。CGroup本身是提供将进程进行分组化管理的功能和接口的基础结构，I/O或内存的分配控制等具体的资源管理功能是通过这个功能来实现的。CGroups可以限制、记录、隔离进程组所使用的物理资源（包括：CPU、memory、IO等），为容器实现虚拟化提供了基本保证。CGroups本质是内核附加在程序上的一系列钩子（hooks），通过程序运行时对资源的调度触发相应的钩子以达到资源追踪和限制的目的。

## 4. Docker概述

更多详情请参考：[Docker整体架构图](http://www.huweihuang.com/article/docker/docker-architecture/)

### 4.1. Docker介绍

1. Docker - Build, Ship, and Run Any App, Anywhere
2. Docker是一种Linux容器工具集，它是为“构建（Build）、交付（Ship）和运行（Run）”分布式应用而设计的。
3. Docker相当于把应用以及应用所依赖的环境完完整整地打成了一个包，这个包拿到哪里都能原生运行。因此可以在开发、测试、运维中保证环境的一致性。
4. **Docker的本质：Docker=LXC(Namespace+CGroups)+Docker Images，即在Linux内核的Namespace[资源隔离]和CGroups[资源控制]技术的基础上通过镜像管理机制来实现轻量化设计。**

### 4.2. Docker的基本概念

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577868/article/caas/docker.png" width="70%">

#### 4.2.1. 镜像

Docker 镜像就是一个只读的模板，可以把镜像理解成一个模子（模具），由模子（镜像）制作的成品（容器）都是一样的（除非在生成时加额外参数），修改成品（容器）本身并不会对模子（镜像）产生影响（除非将成品提交成一个模子），容器重启时，即由模子（镜像）重新制作成一个成品（容器），与其他由该模子制作成的成品并无区别。

例如：一个镜像可以包含一个完整的 ubuntu 操作系统环境，里面仅安装了 Apache 或用户需要的其它应用程序。镜像可以用来创建 Docker 容器。Docker 提供了一个很简单的机制来创建镜像或者更新现有的镜像，用户可以直接从其他人那里下载一个已经做好的镜像来直接使用。

#### 4.2.2. 容器

Docker 利用容器来运行应用。容器是从镜像创建的运行实例。它可以被启动、开始、停止、删除。每个容器都是相互隔离的、保证安全的平台。可以把容器看做是一个简易版的 Linux 环境（包括root用户权限、进程空间、用户空间和网络空间等）和运行在其中的应用程序。

#### 4.2.3. 仓库

仓库是集中存放镜像文件的场所。有时候会把仓库和仓库注册服务器（Registry）混为一谈，并不严格区分。实际上，仓库注册服务器上往往存放着多个仓库，每个仓库中又包含了多个镜像，每个镜像有不同的标签（tag）。

### 4.3. Docker的优势

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577868/article/caas/ContainerVSVMs.jpg" width="80%">

1. 容器的快速轻量

   容器的启动，停止和销毁都是以秒或毫秒为单位的，并且相比传统的虚拟化技术，使用容器在CPU、内存，网络IO等资源上的性能损耗都有同样水平甚至更优的表现。

2. 一次构建，到处运行

   当将容器固化成镜像后，就可以非常快速地加载到任何环境中部署运行。而构建出来的镜像打包了应用运行所需的程序、依赖和运行环境， 这是一个完整可用的应用集装箱，在任何环境下都能保证环境一致性。

3. 完整的生态链

   容器技术并不是Docker首创，但是以往的容器实现只关注于如何运行，而Docker站在巨人的肩膀上进行整合和创新，特别是Docker镜像的设计，完美地解决了容器从构建、交付到运行，提供了完整的生态链支持。

## 5. Kubernetes概述

更多详情请参考：[Kubernetes总架构图](http://www.huweihuang.com/article/kubernetes/kubernetes-architecture/)

### 5.1. Kubernetes介绍

Kubernetes是Google开源的容器集群管理系统。它构建Docker技术之上，为容器化的应用提供资源调度、部署运行、服务发现、扩容缩容等整一套功能，本质上可看作是基于容器技术的Micro-PaaS平台，即第三代PaaS的代表性项目。

### 5.2. Kubernetes的基本概念

#### 5.2.1. Pod

Pod是若干个相关容器的组合，是一个逻辑概念，Pod包含的容器运行在同一个宿主机上，这些容器使用相同的网络命名空间、IP地址和端口，相互之间能通过localhost来发现和通信，共享一块存储卷空间。在Kubernetes中创建、调度和管理的最小单位是Pod。一个Pod一般只放一个业务容器和一个用于统一网络管理的网络容器。

#### 5.2.2. Replication Controller

Replication Controller是用来控制管理Pod副本(Replica，或者称实例)，Replication Controller确保任何时候Kubernetes集群中有指定数量的Pod副本在运行，如果少于指定数量的Pod副本，Replication Controller会启动新的Pod副本，反之会杀死多余的以保证数量不变。另外Replication Controller是弹性伸缩、滚动升级的实现核心。

#### 5.2.3. Service

Service是真实应用服务的抽象，定义了Pod的逻辑集合和访问这个Pod集合的策略，Service将代理Pod对外表现为一个单一访问接口，外部不需要了解后端Pod如何运行，这给扩展或维护带来很大的好处，提供了一套简化的服务代理和发现机制。

#### 5.2.4. Label

Label是用于区分Pod、Service、Replication Controller的Key/Value键值对，实际上Kubernetes中的任意API对象都可以通过Label进行标识。每个API对象可以有多个Label，但是每个Label的Key只能对应一个Value。Label是Service和Replication Controller运行的基础，它们都通过Label来关联Pod，相比于强绑定模型，这是一种非常好的松耦合关系。

#### 5.2.5. Node

Kubernets属于主从的分布式集群架构，Kubernets Node（简称为Node，早期版本叫做Minion）运行并管理容器。Node作为Kubernetes的操作单元，将用来分配给Pod（或者说容器）进行绑定，Pod最终运行在Node上，Node可以认为是Pod的宿主机。

### 5.3. Kubernetes架构

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1512807966/article/caas/architecture.png" width="100%">

 