---
title: "etcdctl-V2"
weight: 2
catalog: true
date: 2017-07-10 10:50:57
subtitle:
header-img: 
tags:
- Etcd
catagories:
- Etcd
---

# 1. etcdctl介绍

etcdctl是一个命令行的客户端，它提供了一下简洁的命令，可理解为命令工具集，可以方便我们在对服务进行测试或者手动修改数据库内容。etcdctl与其他xxxctl的命令原理及操作类似（例如kubectl，systemctl）。

用法：etcdctl [global options] command [command options][args...]

# 2. Etcd常用命令

## 2.1. 数据库操作命令

etcd 在键的组织上采用了层次化的空间结构（类似于文件系统中目录的概念），数据库操作围绕对键值和目录的 CRUD [增删改查]（符合 REST 风格的一套操作：Create, Read, Update, Delete）完整生命周期的管理。

具体的命令选项参数可以通过 etcdctl command --help来获取相关帮助。

## 2.1.1. 对象为键值

1. ### set[增:无论是否存在]:etcdctl set key value

2. ### mk[增:必须不存在]:etcdctl mk key value

3. ### rm[删]:etcdctl rm key

4. ### update[改]:etcdctl update key value

5. ### get[查]:etcdctl get key

## 2.1.2. 对象为目录

1. ### setdir[增:无论是否存在]:etcdctl setdir dir

2. ### mkdir[增:必须不存在]: etcdctl mkdir dir

3. ### rmdir[删]:etcdctl rmdir dir

4. ### updatedir[改]:etcdctl updatedir dir

5. ### ls[查]:etcdclt ls

## 2.2. 非数据库操作命令

1. ### backup[备份 etcd 的数据]

   etcdctl backup

2. ### watch[监测一个键值的变化，一旦键值发生更新，就会输出最新的值并退出]

   etcdctl watch key

3. ### exec-watch[监测一个键值的变化，一旦键值发生更新，就执行给定命令]

   etcdctl exec-watch key --sh -c "ls"

4. ### member[通过 list、add、remove、update 命令列出、添加、删除 、更新etcd 实例到 etcd 集群中]

   etcdctl member list；etcdctl member add 实例；etcdctl member remove 实例；etcdctl member update 实例。

5. ### etcdctl cluster-health[检查集群健康状态]

## 2.3. 常用配置参数

设置配置文件，默认为/etc/etcd/etcd.conf。

| 配置参数                         | 参数说明                                     |
| ---------------------------- | ---------------------------------------- |
| 配置参数                         | 参数说明                                     |
| -name                        | 节点名称                                     |
| -data-dir                    | 保存日志和快照的目录，默认为当前工作目录，指定节点的数据存储目录         |
| -addr                        | 公布的ip地址和端口。 默认为127.0.0.1:2379            |
| -bind-addr                   | 用于客户端连接的监听地址，默认为-addr配置                  |
| -peers                       | 集群成员逗号分隔的列表，例如 127.0.0.1:2380,127.0.0.1:2381 |
| -peer-addr                   | 集群服务通讯的公布的IP地址，默认为 127.0.0.1:2380.       |
| -peer-bind-addr              | 集群服务通讯的监听地址，默认为-peer-addr配置              |
| -wal-dir                     | 指定节点的was文件的存储目录，若指定了该参数，wal文件会和其他数据文件分开存储 |
| -listen-client-urls          |                                          |
| -listen-peer-urls            | 监听URL，用于与其他节点通讯                          |
| -initial-advertise-peer-urls | 告知集群其他节点url.                             |
| -advertise-client-urls       | 告知客户端url, 也就是服务的url                      |
| -initial-cluster-token       | 集群的ID                                    |
| -initial-cluster             | 集群中所有节点                                  |
| -initial-cluster-state       | -initial-cluster-state=new 表示从无到有搭建etcd集群 |
| -discovery-srv               | 用于DNS动态服务发现，指定DNS SRV域名                  |
| -discovery                   | 用于etcd动态发现，指定etcd发现服务的URL [https://discovery.etcd.io/],用环境变量表示 |

 