---
title: "ingress-controller原理"
weight: 3
catalog: true
date: 2022-09-10 10:50:57
subtitle:
header-img: 
tags:
- ApiSix
catagories:
- ApiSix
---

## ingress-controller架构图

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1661409689/article/kubernetes/network/apisix/scene.png)

## ingress-controller流程图

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1661409688/article/kubernetes/network/apisix/flow.png)

## ApisixRoute同步逻辑

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1661409688/article/kubernetes/network/apisix/sync-logic-controller.png)

## 数据结构转换

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1661409896/article/kubernetes/network/apisix/struct-compare.png)

参考：

- https://apisix.apache.org/zh/docs/ingress-controller/getting-started/

- https://apisix.apache.org/zh/docs/ingress-controller/design/
