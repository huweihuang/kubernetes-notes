---
title: "Raft算法"
weight: 2
catalog: true
date: 2019-07-10 10:50:57
subtitle:
header-img: 
tags:
- Etcd
catagories:
- Etcd
---


# 1. Raft协议[分布式一致性算法]

![raft](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578532/article/etcd/raft.png)

raft算法中涉及三种角色，分别是：

- `follower`: 跟随者
- `candidate`: 候选者，选举过程中的中间状态角色
- `leader`: 领导者

# 2. 过程

## 2.1. 选举

有两个timeout来控制选举，第一个是`election timeout`，该时间是节点从follower到成为candidate的时间，该时间是150到300毫秒之间的随机值。另一个是`heartbeat timeout`。

- 当某个节点经历完`election timeout`成为candidate后，开启新的一个选举周期，他向其他节点发起投票请求（Request Vote），如果接收到消息的节点在该周期内还没投过票则给这个candidate投票，然后节点重置他的election timeout。
- 当该candidate获得大部分的选票，则可以当选为leader。
- leader就开始发送`append entries`给其他follower节点，这个消息会在内部指定的`heartbeat timeout`时间内发出，follower收到该信息则响应给leader。
- 这个选举周期会继续，直到某个follower没有收到心跳，并成为candidate。
- 如果某个选举周期内，有两个candidate同时获得相同多的选票，则会等待一个新的周期重新选举。

## 2.2. 同步

当选举过程结束，选出了leader，则leader需要把所有的变更同步的系统中的其他节点，该同步也是通过发送`Append Entries`的消息的方式。

- 首先一个客户端发送一个更新给leader，这个更新会添加到leader的日志中。
- 然后leader会在给follower的下次心跳探测中发送该更新。
- 一旦大多数follower收到这个更新并返回给leader，leader提交这个更新，然后返回给客户端。 

## 2.3. 网络分区

- 当发生网络分区的时候，在不同分区的节点接收不到leader的心跳，则会开启一轮选举，形成不同leader的多个分区集群。
- 当客户端给不同leader的发送更新消息时，不同分区集群中的节点个数小于原先集群的一半时，更新不会被提交，而节点个数大于集群数一半时，更新会被提交。
- 当网络分区恢复后，被提交的更新会同步到其他的节点上，其他节点未提交的日志会被回滚并匹配新leader的日志，保证全局的数据是一致的。


参考：

- http://thesecretlivesofdata.com/raft/
- https://raft.github.io/raft.pdf
- https://raft.github.io/
