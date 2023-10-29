---
title: "Heapster介绍"
weight: 4
catalog: true
date: 2017-08-13 10:50:57
subtitle:
header-img: 
tags:
- Monitor
catagories:
- Monitor
---

# 1. heapster简介

Heapster是容器集群监控和性能分析工具，天然的支持Kubernetes和CoreOS。
Kubernetes有个出名的监控agent—cAdvisor。在每个kubernetes Node上都会运行cAdvisor，它会收集本机以及容器的监控数据(cpu,memory,filesystem,network,uptime)。

# 2. heapster部署与配置

## 2.1. 注意事项

需同步部署机器和被采集机器的时间：ntpdate time.windows.com

加入定时任务，定期同步时间

crontab –e

30 5 * * *          /usr/sbin/ntpdate time.windows.com          //每天早晨5点半执行

## 2.2. 容器式部署

```bash
#拉取镜像
docker pull heapster:latest
#运行容器
docker run -d -p 8082:8082 --net=host heapster:latest --source=kubernetes:http://<k8s-server-ip>:8080?inClusterConfig=false\&useServiceAccount=false --sink=influxdb:http://<influxdb-ip>:8086?db=<k8s_env_zone>
```

## 2.3. 配置说明

可以参考[官方文档](https://github.com/kubernetes/heapster/tree/master/docs)

## 2.3.1. –source

–source: 指定数据获取源。这里指定kube-apiserver即可。
后缀参数：
inClusterConfig:
kubeletPort: 指定kubelet的使用端口，默认10255
kubeletHttps: 是否使用https去连接kubelets(默认：false)
apiVersion: 指定K8S的apiversion
insecure: 是否使用安全证书(默认：false)
auth: 安全认证
useServiceAccount: 是否使用K8S的安全令牌

## 2.3.2. –sink

–sink: 指定后端数据存储。这里指定influxdb数据库。
后缀参数：
user: InfluxDB用户
pw: InfluxDB密码
db: 数据库名
secure: 安全连接到InfluxDB(默认：false)
withfields： 使用InfluxDB fields(默认：false)。

# 3. Metrics

| 分类         | Metric Name                   | Description                                                                                         | 备注            |
| ---------- | ----------------------------- | --------------------------------------------------------------------------------------------------- | ------------- |
| cpu        | cpu/limit                     | CPU hard limit in millicores.                                                                       | CPU上限         |
|            | cpu/node_capacity             | Cpu capacity of a node.                                                                             | Node节点的CPU容量  |
|            | cpu/node_allocatable          | Cpu allocatable of a node.                                                                          | Node节点可分配的CPU |
|            | cpu/node_reservation          | Share of cpu that is reserved on the node allocatable.                                              |               |
|            | cpu/node_utilization          | CPU utilization as a share of node allocatable.                                                     |               |
|            | cpu/request                   | CPU request (the guaranteed amount of resources) in millicores.                                     |               |
|            | cpu/usage                     | Cumulative CPU usage on all cores.                                                                  | CPU总使用量       |
|            | cpu/usage_rate                | CPU usage on all cores in millicores.                                                               |               |
| filesystem | filesystem/usage              | Total number of bytes consumed on a filesystem.                                                     | 文件系统的使用量      |
|            | filesystem/limit              | The total size of filesystem in bytes.                                                              | 文件系统的使用上限     |
|            | filesystem/available          | The number of available bytes remaining in a the filesystem                                         | 可用的文件系统容量     |
|            | filesystem/inodes             | The number of available inodes in a the filesystem                                                  |               |
|            | filesystem/inodes_free        | The number of free inodes remaining in a the filesystem                                             |               |
| memory     | memory/limit                  | Memory hard limit in bytes.                                                                         | 内存上限          |
|            | memory/major_page_faults      | Number of major page faults.                                                                        |               |
|            | memory/major_page_faults_rate | Number of major page faults per second.                                                             |               |
|            | memory/node_capacity          | Memory capacity of a node.                                                                          |               |
|            | memory/node_allocatable       | Memory allocatable of a node.                                                                       |               |
|            | memory/node_reservation       | Share of memory that is reserved on the node allocatable.                                           |               |
|            | memory/node_utilization       | Memory utilization as a share of memory allocatable.                                                |               |
|            | memory/page_faults            | Number of page faults.                                                                              |               |
|            | memory/page_faults_rate       | Number of page faults per second.                                                                   |               |
|            | memory/request                | Memory request (the guaranteed amount of resources) in bytes.                                       |               |
|            | memory/usage                  | Total memory usage.                                                                                 |               |
|            | memory/cache                  | Cache memory usage.                                                                                 |               |
|            | memory/rss                    | RSS memory usage.                                                                                   |               |
|            | memory/working_set            | Total working set usage. Working set is the memory being used and not easily dropped by the kernel. |               |
| network    | network/rx                    | Cumulative number of bytes received over the network.                                               |               |
|            | network/rx_errors             | Cumulative number of errors while receiving over the network.                                       |               |
|            | network/rx_errors_rate        | Number of errors while receiving over the network per second.                                       |               |
|            | network/rx_rate               | Number of bytes received over the network per second.                                               |               |
|            | network/tx                    | Cumulative number of bytes sent over the network                                                    |               |
|            | network/tx_errors             | Cumulative number of errors while sending over the network                                          |               |
|            | network/tx_errors_rate        | Number of errors while sending over the network                                                     |               |
|            | network/tx_rate               | Number of bytes sent over the network per second.                                                   |               |
|            | uptime                        | Number of milliseconds since the container was started.                                             | -             |

# 4. Labels

| Label Name           | Description                                                                                                            |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| pod_id               | Unique ID of a Pod                                                                                                     |
| pod_name             | User-provided name of a Pod                                                                                            |
| pod_namespace        | The namespace of a Pod                                                                                                 |
| container_base_image | Base image for the container                                                                                           |
| container_name       | User-provided name of the container or full cgroup name for system containers                                          |
| host_id              | Cloud-provider specified or user specified Identifier of a node                                                        |
| hostname             | Hostname where the container ran                                                                                       |
| labels               | Comma-separated(Default) list of user-provided labels. Format is 'key:value'                                           |
| namespace_id         | UID of the namespace of a Pod                                                                                          |
| resource_id          | A unique identifier used to differentiate multiple metrics of the same type. e.x. Fs partitions under filesystem/usage |

# 5. heapster API

见官方文档：[https://github.com/kubernetes/heapster/blob/master/docs/model.md](https://github.com/kubernetes/heapster/blob/master/docs/model.md)