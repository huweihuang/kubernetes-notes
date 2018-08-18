---
title: "[Kubernetes] Kubernetes集群问题排查"
catalog: true
date: 2017-09-20 10:50:57
type: "categories"
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. 查看系统Event事件

 ```
kubectl describe pod <PodName> --namespace=<NAMESPACE> 
 ```

该命令可以显示Pod创建时的配置定义、状态等信息和最近的Event事件，事件信息可用于排错。例如当Pod状态为Pending，可通过查看Event事件确认原因，一般原因有几种：

- 没有可用的Node可调度
- 开启了资源配额管理并且当前Pod的目标节点上恰好没有可用的资源
- 正在下载镜像（镜像拉取耗时太久）或镜像下载失败。

kubectl describe还可以查看其它k8s对象：NODE,RC,Service,Namespace,Secrets。

### 1.1. Pod

```
kubectl describe pod <PodName> --namespace=<NAMESPACE>
```

以下是容器的启动命令非阻塞式导致容器挂掉，被k8s频繁重启所产生的事件。

```shell
kubectl describe pod <PodName> --namespace=<NAMESPACE>  

Events:
  FirstSeen LastSeen    Count   From            SubobjectPath       Reason      Message
  ───────── ────────    ─────   ────            ─────────────       ──────      ───────
  7m        7m      1   {scheduler }                    Scheduled   Successfully assigned yangsc-1-0-0-index0 to 10.8.216.19
  7m        7m      1   {kubelet 10.8.216.19}   containers{infra}   Pulled      Container image "gcr.io/kube-system/pause:0.8.0" already present on machine
  7m        7m      1   {kubelet 10.8.216.19}   containers{infra}   Created     Created with docker id 84f133c324d0
  7m        7m      1   {kubelet 10.8.216.19}   containers{infra}   Started     Started with docker id 84f133c324d0
  7m        7m      1   {kubelet 10.8.216.19}   containers{yangsc0} Started     Started with docker id 3f9f82abb145
  7m        7m      1   {kubelet 10.8.216.19}   containers{yangsc0} Created     Created with docker id 3f9f82abb145
  7m        7m      1   {kubelet 10.8.216.19}   containers{yangsc0} Created     Created with docker id fb112e4002f4
  7m        7m      1   {kubelet 10.8.216.19}   containers{yangsc0} Started     Started with docker id fb112e4002f4
  6m        6m      1   {kubelet 10.8.216.19}   containers{yangsc0} Created     Created with docker id 613b119d4474
  6m        6m      1   {kubelet 10.8.216.19}   containers{yangsc0} Started     Started with docker id 613b119d4474
  6m        6m      1   {kubelet 10.8.216.19}   containers{yangsc0} Created     Created with docker id 25cb68d1fd3d
  6m        6m      1   {kubelet 10.8.216.19}   containers{yangsc0} Started     Started with docker id 25cb68d1fd3d
  5m        5m      1   {kubelet 10.8.216.19}   containers{yangsc0} Started     Started with docker id 7d9ee8610b28
  5m        5m      1   {kubelet 10.8.216.19}   containers{yangsc0} Created     Created with docker id 7d9ee8610b28
  3m        3m      1   {kubelet 10.8.216.19}   containers{yangsc0} Started     Started with docker id 88b9e8d582dd
  3m        3m      1   {kubelet 10.8.216.19}   containers{yangsc0} Created     Created with docker id 88b9e8d582dd
  7m        1m      7   {kubelet 10.8.216.19}   containers{yangsc0} Pulling     Pulling image "gcr.io/test/tcp-hello:1.0.0"
  1m        1m      1   {kubelet 10.8.216.19}   containers{yangsc0} Started     Started with docker id 089abff050e7
  1m        1m      1   {kubelet 10.8.216.19}   containers{yangsc0} Created     Created with docker id 089abff050e7
  7m        1m      7   {kubelet 10.8.216.19}   containers{yangsc0} Pulled      Successfully pulled image "gcr.io/test/tcp-hello:1.0.0"
  6m        7s      34  {kubelet 10.8.216.19}   containers{yangsc0} Backoff     Back-off restarting failed docker container
```

### 1.2. NODE

```
kubectl describe node 10.8.216.20
```

```shell
[root@FC-43745A-10 ~]# kubectl describe node 10.8.216.20  
Name:           10.8.216.20  
Labels:         kubernetes.io/hostname=10.8.216.20,namespace/bcs-cc=true,namespace/myview=true  
CreationTimestamp:  Mon, 17 Apr 2017 11:32:52 +0800  
Phase:            
Conditions:  
  Type      Status  LastHeartbeatTime           LastTransitionTime          Reason              Message  
  ────      ──────  ─────────────────           ──────────────────          ──────              ───────  
  Ready     True    Fri, 18 Aug 2017 09:38:33 +0800     Tue, 02 May 2017 17:40:58 +0800     KubeletReady            kubelet is posting ready status  
  OutOfDisk     False   Fri, 18 Aug 2017 09:38:33 +0800     Mon, 17 Apr 2017 11:31:27 +0800     KubeletHasSufficientDisk    kubelet has sufficient disk space available  
Addresses:  10.8.216.20,10.8.216.20  
Capacity:  
 cpu:       32  
 memory:    67323039744  
 pods:      40  
System Info:  
 Machine ID:            723bafc7f6764022972b3eae1ce6b198  
 System UUID:           4C4C4544-0042-4210-8044-C3C04F595631  
 Boot ID:           da01f2e3-987a-425a-9ca7-1caaec35d1e5  
 Kernel Version:        3.10.0-327.28.3.el7.x86_64  
 OS Image:          CentOS Linux 7 (Core)  
 Container Runtime Version: docker://1.13.1  
 Kubelet Version:       v1.1.1-xxx2-13.1+79c90c68bfb72f-dirty  
 Kube-Proxy Version:        v1.1.1-xxx2-13.1+79c90c68bfb72f-dirty  
ExternalID:         10.8.216.20  
Non-terminated Pods:        (6 in total)  
  Namespace         Name                    CPU Requests    CPU Limits  Memory Requests Memory Limits  
  ─────────         ────                    ────────────    ──────────  ─────────────── ─────────────  
  bcs-cc            bcs-cc-api-0-0-1364-index0      1 (3%)      1 (3%)      4294967296 (6%) 4294967296 (6%)  
  bcs-cc            bcs-cc-api-0-0-1444-index0      1 (3%)      1 (3%)      4294967296 (6%) 4294967296 (6%)  
  fw                fw-demo2-0-0-1519-index0        1 (3%)      1 (3%)      4294967296 (6%) 4294967296 (6%)  
  myview            myview-api-0-0-1362-index0      1 (3%)      1 (3%)      4294967296 (6%) 4294967296 (6%)  
  myview            myview-api-0-0-1442-index0      1 (3%)      1 (3%)      4294967296 (6%) 4294967296 (6%)  
  qa-ts-dna         ts-dna-console3-0-0-1434-index0     1 (3%)      1 (3%)      4294967296 (6%) 4294967296 (6%)  
Allocated resources:  
  (Total limits may be over 100%, i.e., overcommitted. More info: http://releases.k8s.io/HEAD/docs/user-guide/compute-resources.md)  
  CPU Requests  CPU Limits  Memory Requests     Memory Limits  
  ────────────  ──────────  ───────────────     ─────────────  
  6 (18%)   6 (18%)     25769803776 (38%)   25769803776 (38%)  
No events.  
```

### 1.3. RC

```
kubectl describe rc mytest-1-0-0 --namespace=test
```

```shell
[root@FC-43745A-10 ~]# kubectl describe rc mytest-1-0-0 --namespace=test  
Name:       mytest-1-0-0  
Namespace:  test  
Image(s):   gcr.io/test/mywebcalculator:1.0.1  
Selector:   app=mytest,appVersion=1.0.0  
Labels:     app=mytest,appVersion=1.0.0,env=ts,zone=inner  
Replicas:   1 current / 1 desired  
Pods Status:    1 Running / 0 Waiting / 0 Succeeded / 0 Failed  
No volumes.  
Events:  
  FirstSeen LastSeen    Count   From                SubobjectPath   Reason          Message  
  ───────── ────────    ─────   ────                ─────────────   ──────          ───────  
  20h       19h     9   {replication-controller }           FailedCreate        Error creating: Pod "mytest-1-0-0-index0" is forbidden: limited to 10 pods  
  20h       17h     7   {replication-controller }           FailedCreate        Error creating: pods "mytest-1-0-0-index0" already exists  
  20h       17h     4   {replication-controller }           SuccessfulCreate    Created pod: mytest-1-0-0-index0  
```

### 1.4. NAMESPACE

```
kubectl describe namespace test
```

```shell
[root@FC-43745A-10 ~]# kubectl describe namespace test  
Name:   test  
Labels: <none>  
Status: Active  
  
Resource Quotas  
 Resource       Used        Hard  
 ---            ---     ---  
 cpu            5       20  
 memory         1342177280  53687091200  
 persistentvolumeclaims 0       10  
 pods           4       10  
 replicationcontrollers 8       20  
 resourcequotas     1       1  
 secrets        3       10  
 services       8       20  
  
No resource limits.  
```

### 1.5. Service

```
kubectl describe service xxx-containers-1-1-0 --namespace=test
```

```shell
[root@FC-43745A-10 ~]# kubectl describe service xxx-containers-1-1-0 --namespace=test  
Name:           xxx-containers-1-1-0  
Namespace:      test  
Labels:         app=xxx-containers,appVersion=1.1.0,env=ts,zone=inner  
Selector:       app=xxx-containers,appVersion=1.1.0  
Type:           ClusterIP  
IP:         10.254.46.42  
Port:           port-dna-tcp-35913  35913/TCP  
Endpoints:      10.0.92.17:35913  
Port:           port-l7-tcp-8080    8080/TCP  
Endpoints:      10.0.92.17:8080  
Session Affinity:   None  
No events.  
```

## 2. 查看容器日志

1、查看指定pod的日志

```shell
kubectl logs <pod_name>

kubectl logs -f <pod_name> #类似tail -f的方式查看
```

2、查看上一个pod的日志

```
kubectl logs -p <pod_name>
```

3、查看指定pod中指定容器的日志

```
kubectl logs <pod_name> -c <container_name>
```

4、kubectl logs --help

```shell
[root@node5 ~]# kubectl logs --help  
Print the logs for a container in a pod. If the pod has only one container, the container name is optional.  
Usage:  
  kubectl logs [-f] [-p] POD [-c CONTAINER] [flags]  
Aliases:  
  logs, log  
   
Examples:  
# Return snapshot logs from pod nginx with only one container  
$ kubectl logs nginx  
# Return snapshot of previous terminated ruby container logs from pod web-1  
$ kubectl logs -p -c ruby web-1  
# Begin streaming the logs of the ruby container in pod web-1  
$ kubectl logs -f -c ruby web-1  
# Display only the most recent 20 lines of output in pod nginx  
$ kubectl logs --tail=20 nginx  
# Show all logs from pod nginx written in the last hour  
$ kubectl logs --since=1h nginx  
```

## 3. 查看k8s服务日志

### 3.1. journalctl

在Linux系统上systemd系统来管理kubernetes服务，并且journal系统会接管服务程序的输出日志，可以通过**systemctl status <xxx>或journalctl -u <xxx> -f**来查看kubernetes服务的日志。

其中kubernetes组件包括：

| k8s组件                   | 涉及日志内容           | 备注   |
| ----------------------- | ---------------- | ---- |
| kube-apiserver          |                  |      |
| kube-controller-manager | Pod扩容相关或RC相关     |      |
| kube-scheduler          | Pod扩容相关或RC相关     |      |
| kubelet                 | Pod生命周期相关：创建、停止等 |      |
| etcd                    |                  |      |

### 3.2. 日志文件

也可以通过指定日志存放目录来保存和查看日志

- --logtostderr=false：不输出到stderr
- --log-dir=/var/log/kubernetes:日志的存放目录
- --alsologtostderr=false:设置为true表示日志输出到文件也输出到stderr
- --v=0:glog的日志级别
- --vmodule=gfs*=2,test*=4：glog基于模块的详细日志级别

## 4. 常见问题

### 4.1. Pod状态一直为Pending

```
kubectl describe <pod_name> --namespace=<NAMESPACE>
```

查看该POD的事件。

- 正在下载镜像但拉取不下来（镜像拉取耗时太久）[一般都是该原因]
- 没有可用的Node可调度
- 开启了资源配额管理并且当前Pod的目标节点上恰好没有可用的资源

解决方法：

1. 查看该POD所在宿主机与镜像仓库之间的网络是否有问题，可以手动拉取镜像
2. 删除POD实例，让POD调度到别的宿主机上

### 4.2. Pod创建后不断重启

kubectl get pods中Pod状态一会running，一会不是，且RESTARTS次数不断增加。

一般原因为容器启动命令不是阻塞式命令，导致容器运行后马上退出。

非阻塞式命令：

- 本身CMD指定的命令就是非阻塞式命令
- 将服务启动方式设置为后台运行

解决方法：

1、将命令改为阻塞式命令（前台运行），例如：**zkServer.sh start-foreground**

2、java运行程序的启动脚本将 nohup xxx &的nobup和&去掉，例如：

```shell
nohup JAVA_HOME/bin/java JAVA_OPTS -cp $CLASSPATH com.cnc.open.processor.Main &
```

改为：

```shell
JAVA_HOME/bin/java JAVA_OPTS -cp $CLASSPATH com.cnc.open.processor.Main
```

 

文章参考《Kubernetes权威指南》
