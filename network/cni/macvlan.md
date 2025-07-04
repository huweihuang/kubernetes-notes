---
title: "Macvlan介绍"
weight: 3
catalog: true
date: 2021-07-10 10:50:57
subtitle:
header-img: 
tags:
- CNI
catagories:
- CNI
---

# 1. 简介

macvlan可以看做是物理接口eth（父接口）的子接口，每个macvlan都拥有独立的mac地址，可以被绑定IP作为正常的网卡接口使用。通过这个特性，可以实现在一个物理网络设备绑定多个IP，每个IP拥有独立的mac地址。该特性经常被应用在容器虚拟化中（容器可以配置macvlan的网络，将macvlan interface移动到容器的namespace中）。

示意图：

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1595764512/article/kubernetes/macvlan/macvlan.jpg">

# 2. 四种工作模式

## 2.1. VEPA (Virtual Ethernet Port Aggregator)

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1595764512/article/kubernetes/macvlan/macvlan_vepa.jpg">

VEPA为默认的工作模式，该模式下，所有macvlan发出的流量都会经过父接口，不管目的地是否与该macvlan共用一个父接口。

## 2.2. Bridge mode

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1595764512/article/kubernetes/macvlan/macvlan_bridge.jpg">

该bridge模式类似于传统的网桥模式，拥有相同父接口的macvlan可以直接进行通信，不需要将数据发给父接口转发。该模式下不需要交换机支持hairpin模式，性能比VEPA模式好。另外相对于传统的网桥模式，该模式不需要学习mac地址，不需要STP，使得其性能比传统的网桥性能好得多。但是如果父接口down掉，则所有子接口也会down，同时无法通信。

## 2.3. Private mode

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1595764512/article/kubernetes/macvlan/macvlan_private.jpg">

该模式是VEPA模式的增强版，

## 2.4. Passthru mode

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1595764512/article/kubernetes/macvlan/macvlan_passthru.jpg">

. 

>  待完善



参考：

- https://backreference.org/2014/03/20/some-notes-on-macvlanmacvtap/
- https://github.com/containernetworking/plugins/tree/master/plugins/main/macvlan
- https://github.com/containernetworking/plugins/blob/master/plugins/main/macvlan/macvlan.go
- http://wikibon.org/wiki/v/Edge_Virtual_Bridging
- [Linux 虚拟网卡技术：Macvlan](https://juejin.im/post/5ca183ad6fb9a05e5343a7e8)
- http://hicu.be/bridge-vs-macvlan
- http://hicu.be/docker-networking-macvlan-bridge-mode-configuration


