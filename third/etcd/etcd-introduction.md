# 1. Etcd是什么（what）

## 1.1. 概述

etcd is a distributed, consistent key-value store for shared configuration and service discovery, with a focus on being:

- Secure: automatic TLS with optional client cert authentication[可选的SSL客户端证书认证：支持https访问 ]
- Fast: benchmarked 10,000 writes/sec[单实例每秒 1000 次写操作]
- Reliable: properly distributed using Raft[使用Raft保证一致性]

etcd是一个分布式、一致性的键值存储系统，主要用于配置共享和服务发现。[以上内容来自etcd官网]

## 1.2. Raft协议[分布式一致性算法]

![raft](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578532/article/etcd/raft.png)

raft算法中涉及三种角色，分别是：

- `follower`: 跟随者
- `candidate`: 候选者，选择过程中的中间状态角色
- `leader`: 领导者

### 1.2.1. 选举

有两个timeout来控制选举，第一个是`election timeout`，该时间是节点从follower到成为candidate的时间，该时间是150到300毫秒之间的随机值。另一个是`heartbeat timeout`。

- 当某个节点经历完`election timeout`成为candidate后，开启新的一个选举周期，他向其他节点发起投票请求（Request Vote），如果接收到消息的节点在该周期内还没投过票则给这个candidate投票，然后节点重置他的election timeout。
- 当该candidate获得大部分的选票，则可以当选为leader。
- leader就开始发送`append entries`给其他follower节点，这个消息会在内部指定的`heartbeat timeout`时间内发出，follower收到该信息则响应给leader。
- 这个选举周期会继续，直到某个follower没有收到心跳，并成为candidate。
- 如果某个选举周期内，有两个candidate同时获得相同多的选票，则会等待一个新的周期重新选举。

### 1.2.2. 同步

当选举过程结束，选出了leader，则leader需要把所有的变更同步的系统中的其他节点，该同步也是通过发送`Append Entries`的消息的方式。

- 首先一个客户端发送一个更新给leader，这个更新会添加到leader的日志中。
- 然后leader会在给follower的下次心跳探测中发送该更新。
- 一旦大多数follower收到这个更新并返回给leader，leader提交这个更新，然后返回给客户端。 

### 1.2.3. 网络分区

- 当发生网络分区的时候，在不同分区的节点接收不到leader的心跳，则会开启一轮选举，形成不同leader的多个分区集群。
- 当客户端给不同leader的发送更新消息时，不同分区集群中的节点个数小于原先集群的一半时，更新不会被提交，而节点个数大于集群数一半时，更新会被提交。
- 当网络分区恢复后，被提交的更新会同步到其他的节点上，其他节点未提交的日志会被回滚并匹配新leader的日志，保证全局的数据是一致的。


# 2. 为什么使用Etcd（why）

## 2.1. Etcd的优势

1. 简单。使用Go语言编写部署简单；使用HTTP作为接口使用简单；使用Raft算法保证强一致性让用户易于理解。
2. 数据持久化。etcd默认数据一更新就进行持久化。
3. 安全。etcd支持SSL客户端安全认证。

# 3. 如何实现Etcd架构（how）

## 3.1. Etcd的相关名词解释

- Raft：etcd所采用的保证分布式系统强一致性的算法。
- Node：一个Raft状态机实例。
- Member： 一个etcd实例。它管理着一个Node，并且可以为客户端请求提供服务。
- Cluster：由多个Member构成可以协同工作的etcd集群。
- Peer：对同一个etcd集群中另外一个Member的称呼。
- Client： 向etcd集群发送HTTP请求的客户端。
- WAL：预写式日志，etcd用于持久化存储的日志格式。
- snapshot：etcd防止WAL文件过多而设置的快照，存储etcd数据状态。
- Proxy：etcd的一种模式，为etcd集群提供反向代理服务。
- Leader：Raft算法中通过竞选而产生的处理所有数据提交的节点。
- Follower：竞选失败的节点作为Raft中的从属节点，为算法提供强一致性保证。
- Candidate：当Follower超过一定时间接收不到Leader的心跳时转变为Candidate开始竞选。【候选人】
- Term：某个节点成为Leader到下一次竞选时间，称为一个Term。【任期】
- Index：数据项编号。Raft中通过Term和Index来定位数据。

## 3.2. Etcd的架构图

![etcd的架构图](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578532/article/etcd/etcd-architecture.jpg)

一个用户的请求发送过来，会经由HTTP Server转发给Store进行具体的事务处理，如果涉及到节点的修改，则交给Raft模块进行状态的变更、日志的记录，然后再同步给别的etcd节点以确认数据提交，最后进行数据的提交，再次同步。

## 1、HTTP Server:

用于处理用户发送的API请求以及其它etcd节点的同步与心跳信息请求。

## 2、Raft:

Raft强一致性算法的具体实现，是etcd的核心。

## 3、WAL:

Write Ahead Log（预写式日志），是etcd的数据存储方式，用于系统提供原子性和持久性的一系列技术。除了在内存中存有所有数据的状态以及节点的索引以外，etcd就通过WAL进行持久化存储。WAL中，所有的数据提交前都会事先记录日志。

1. Entry[日志内容]:

   负责存储具体日志的内容。

2. Snapshot[快照内容]:

   Snapshot是为了防止数据过多而进行的状态快照，日志内容发生变化时保存Raft的状态。

## 4、Store:

用于处理etcd支持的各类功能的事务，包括数据索引、节点状态变更、监控与反馈、事件处理与执行等等，是etcd对用户提供的大多数API功能的具体实现。


参考：

- http://thesecretlivesofdata.com/raft/
