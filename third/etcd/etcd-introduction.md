# 1. Etcd是什么（what）

## 1.1. 概述

etcd is a distributed, consistent key-value store for shared configuration and service discovery, with a focus on being:

- Secure: automatic TLS with optional client cert authentication[可选的SSL客户端证书认证：支持https访问 ]
- Fast: benchmarked 10,000 writes/sec[单实例每秒 1000 次写操作]
- Reliable: properly distributed using Raft[使用Raft保证一致性]

etcd是一个分布式、一致性的键值存储系统，主要用于配置共享和服务发现。[以上内容来自etcd官网]

## 1.2. Raft协议[分布式一致性算法]

![raft](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578532/article/etcd/raft.png)

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
