# 问题描述

节点Pod被驱逐


# 原因

## 1. 查看节点和该节点pod状态

查看节点状态为Ready，查看该节点的所有pod，发现存在被驱逐的pod和nvidia-device-plugin为pending

```bash
root@host:~$ kgpoallowide |grep 192.168.1.1
department-56   173e397c-ea35-4aac-85d8-07106e55d7b7   0/1       Evicted             0          52d       <none>            192.168.1.1   <none>
kube-system     nvidia-device-plugin-daemonset-d58d2   0/1       Pending             0          1s        <none>            192.168.1.1   <none>
```

## 2. 查看对应节点kubelet的日志

```bash
0905 15:42:13.182280   23506 eviction_manager.go:142] Failed to admit pod rdma-device-plugin-daemonset-8nwb8_kube-system(acc28a85-cfb0-11e9-9729-6c92bf5e2432) - node has conditions: [DiskPressure]
I0905 15:42:14.827343   23506 kubelet.go:1836] SyncLoop (ADD, "api"): "nvidia-device-plugin-daemonset-88sm6_kube-system(adbd9227-cfb0-11e9-9729-6c92bf5e2432)"
W0905 15:42:14.827372   23506 eviction_manager.go:142] Failed to admit pod nvidia-device-plugin-daemonset-88sm6_kube-system(adbd9227-cfb0-11e9-9729-6c92bf5e2432) - node has conditions: [DiskPressure]
I0905 15:42:15.722378   23506 kubelet_node_status.go:607] Update capacity for nvidia.com/gpu-share to 0
I0905 15:42:16.692488   23506 kubelet.go:1852] SyncLoop (DELETE, "api"): "rdma-device-plugin-daemonset-8nwb8_kube-system(acc28a85-cfb0-11e9-9729-6c92bf5e2432)"
W0905 15:42:16.698445   23506 status_manager.go:489] Failed to delete status for pod "rdma-device-plugin-daemonset-8nwb8_kube-system(acc28a85-cfb0-11e9-9729-6c92bf5e2432)": pod "rdma-device-plugin-daemonset-8nwb8" not found
I0905 15:42:16.698490   23506 kubelet.go:1846] SyncLoop (REMOVE, "api"): "rdma-device-plugin-daemonset-8nwb8_kube-system(acc28a85-cfb0-11e9-9729-6c92bf5e2432)"
I0905 15:42:16.699267   23506 kubelet.go:2040] Failed to delete pod "rdma-device-plugin-daemonset-8nwb8_kube-system(acc28a85-cfb0-11e9-9729-6c92bf5e2432)", err: pod not found
W0905 15:42:16.777355   23506 eviction_manager.go:332] eviction manager: attempting to reclaim nodefs
I0905 15:42:16.777384   23506 eviction_manager.go:346] eviction manager: must evict pod(s) to reclaim nodefs
E0905 15:42:16.777390   23506 eviction_manager.go:357] eviction manager: eviction thresholds have been met, but no pods are active to evict
```

存在关于pod驱逐相关的日志，驱逐的原因为`node has conditions: [DiskPressure]`。

## 3. 查看磁盘相关信息

```bash 
[root@host /]# df -h
Filesystem      Size  Used Avail Use% Mounted on
devtmpfs        126G     0  126G   0% /dev
tmpfs           126G     0  126G   0% /dev/shm
tmpfs           126G   27M  126G   1% /run
tmpfs           126G     0  126G   0% /sys/fs/cgroup
/dev/sda1        20G   19G     0 100% /   # 根目录磁盘满
/dev/nvme1n1    3.0T  191G  2.8T   7% /data2
/dev/nvme0n1    3.0T  1.3T  1.7T  44% /data1
/dev/sda4       182G   95G   87G  53% /data
/dev/sda3        20G  3.8G   15G  20% /usr/local
tmpfs            26G     0   26G   0% /run/user/0
```

发现根目录的磁盘盘，接着查看哪些文件占用磁盘。

```bash 
[root@host ~/kata]# du -sh ./*
1.0M	./log
944K	./netlink
6.6G	./kernel3
```

/var/log/下存在7G 的日志。清理相关日志和无用文件后，根目录恢复空间。

```bash 
[root@host /data]# df -h
Filesystem      Size  Used Avail Use% Mounted on
devtmpfs        126G     0  126G   0% /dev
tmpfs           126G     0  126G   0% /dev/shm
tmpfs           126G   27M  126G   1% /run
tmpfs           126G     0  126G   0% /sys/fs/cgroup
/dev/sda1        20G  5.8G   13G  32% /   # 根目录正常
/dev/nvme1n1    3.0T  191G  2.8T   7% /data2
```

查看节点pod状态，相关plugin的pod恢复正常。

```bash 
root@host:~$ kgpoallowide |grep 192.168.1.1
kube-system     nvidia-device-plugin-daemonset-h4pjc   1/1       Running             0          16m       192.168.1.1   192.168.1.1   <none>
kube-system     rdma-device-plugin-daemonset-xlkbv     1/1       Running             0          16m       192.168.1.1   192.168.1.1   <none>
```

## 4. 查看kubelet配置

查看kubelet关于pod驱逐相关的参数配置，可见节点kubelet开启了驱逐机制，正常情况下该配置应该是关闭的。

```bash
ExecStart=/usr/local/bin/kubelet \
	...
  --eviction-hard=nodefs.available<1% \
```

# 解决方案

总结以上原因为，kubelet开启了pod驱逐的机制，根目录的磁盘达到100%，pod被驱逐，且无法再正常创建在该节点。

解决方案如下：

1、关闭kubelet的驱逐机制。

2、清除根目录的文件，恢复根目录空间，并后续增加根目录的磁盘监控。


