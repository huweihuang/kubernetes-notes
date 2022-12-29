---
title: "KubeEdge介绍"
weight: 1
catalog: true
date: 2021-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubeedge
catagories:
- Kubeedge
---

# 1. KubeEdge简介

`KubeEdge`是基于kubernetes之上将容器化应用的编排能力拓展到边缘主机或边缘设备，在云端和边缘端提供网络通信，应用部署、元数据同步等功能。同时支持**MQTT**协议，允许开发者在边缘端自定义接入边缘设备。

# 2. 功能

- 边缘计算：提供边缘节点自治能力，边缘节点数据处理能力。
- 便捷部署：开发者可以开发http或mqtt协议的应用，运行在云端和边缘端。
- k8s原生支持：可以通过k8s管理和监控边缘设备和边缘节点。
- 丰富的应用类型：可以在边缘端部署机器学习、图片识别、事件处理等应用。

# 3. 组件

## 3.1. 云端

- [CloudHub](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/cloud/cloudhub.md)：一个web socket服务器，负责监听云端的更新、缓存及向`EdgeHub`发送消息。

- [EdgeController](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/cloud/controller.md)：一个扩展的k8s控制器，负责管理边缘节点和pod元数据，同步边缘节点的数据，是`k8s-apiserver` 与`EdgeCore`的通信桥梁。

- [DeviceController](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/cloud/device_controller.md)：一个扩展的k8s控制器，负责管理节点设备，同步云端和边缘端的设备元数据和状态。

## 3.2. 边缘端

- [EdgeHub](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/edge/edgehub.md)：一个web socket客户端，负责云端与边缘端的信息交互，其中包括将云端的资源变更同步到边缘端及边缘端的状态变化同步到云端。
- [Edged](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/edge/edged.md)：运行在边缘节点，管理容器化应用的agent，负责pod生命周期的管理，类似kubelet。
- [EventBus](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/edge/eventbus.md)：一个MQTT客户端，与MQTT服务端交互，提供发布/订阅的能力。
- ServiceBus：一个HTTP客户端，与HTTP服务端交互。为云组件提供HTTP客户端功能，以访问在边缘运行的HTTP服务器。
- [DeviceTwin](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/edge/devicetwin.md)：负责存储设备状态并同步设备状态到云端，同时提供应用的接口查询。
- [MetaManager](https://github.com/kubeedge/kubeedge/blob/master/docs/modules/edge/metamanager.md)：`edged`和`edgehub`之间的消息处理器，负责向轻量数据库（SQLite）存储或查询元数据。

# 4. 架构图

![kubeedge-arch](https://res.cloudinary.com/dqxtn0ick/image/upload/v1580806242/article/kubernetes/kubeedge/kubeedge_arch.png)



参考：

- https://github.com/kubeedge/kubeedge

- https://kubeedge.readthedocs.io/en/latest/modules/kubeedge.html