---
title: "Volume介绍"
linkTitle: "Volume"
weight: 1
catalog: true
date: 2019-6-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. volume概述

- 容器上的文件生命周期同容器的生命周期一致，即容器挂掉之后，容器将会以最初镜像中的文件系统内容启动，之前容器运行时产生的文件将会丢失。
- Pod的volume的生命周期同Pod的生命周期一致，当Pod被删除的时候，对应的volume才会被删除。即Pod中的容器重启时，之前的文件仍可以保存。

容器中的进程看到的是由其 `Docker 镜像和卷`组成的文件系统视图。

**Pod volume的使用方式**

Pod 中的每个容器都必须独立指定每个卷的挂载位置，需要给Pod配置volume相关参数。

Pod的volume关键字段如下：

- spec.volumes：提供怎样的数据卷
- spec.containers.volumeMounts：挂载到容器的什么路径

# 2. volume类型

## 2.1. emptyDir

**1、特点**

- 会创建`emptyDir`对应的目录，默认为空（如果该目录原来有文件也会被重置为空）
- Pod中的不同容器可以在目录中读写相同文件（即Pod中的不同容器可以通过该方式来共享文件）
- 当Pod被删除，`emptyDir` 中的数据将被永久删除，如果只是Pod挂掉该数据还会保留

**2、使用场景**

- 不同容器之间共享文件（例如日志采集等）

- 暂存空间，例如用于基于磁盘的合并排序

- 用作长时间计算崩溃恢复时的检查点
  
  **3、示例**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: k8s.gcr.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir: {}
```

## 2.2. hostPath

**1、特点**

- 会将宿主机的目录或文件挂载到Pod中

**2、使用场景**

- 运行需要访问 Docker 内部的容器；使用 `/var/lib/docker` 的 `hostPath`

- 在容器中运行 cAdvisor；使用 `/dev/cgroups` 的 `hostPath`

- 其他使用到宿主机文件的场景

**`hostPath`的`type`字段**

| 值                   | 行为                                                                   |
| ------------------- | -------------------------------------------------------------------- |
|                     | 空字符串（默认）用于向后兼容，这意味着在挂载 hostPath 卷之前不会执行任何检查。                         |
| `DirectoryOrCreate` | 如果在给定的路径上没有任何东西存在，那么将根据需要在那里创建一个空目录，权限设置为 0755，与 Kubelet 具有相同的组和所有权。 |
| `Directory`         | 给定的路径下必须存在目录                                                         |
| `FileOrCreate`      | 如果在给定的路径上没有任何东西存在，那么会根据需要创建一个空文件，权限设置为 0644，与 Kubelet 具有相同的组和所有权。    |
| `File`              | 给定的路径下必须存在文件                                                         |
| `Socket`            | 给定的路径下必须存在 UNIX 套接字                                                  |
| `CharDevice`        | 给定的路径下必须存在字符设备                                                       |
| `BlockDevice`       | 给定的路径下必须存在块设备                                                        |

**注意事项**

- 由于每个节点上的文件都不同，具有相同配置的 pod 在不同节点上的行为可能会有所不同
- 当 Kubernetes 按照计划添加资源感知调度时，将无法考虑 `hostPath` 使用的资源
- 在底层主机上创建的文件或目录只能由 root 写入。您需要在[特权容器](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)中以 root 身份运行进程，或修改主机上的文件权限以便写入 `hostPath` 卷

**3、示例**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: k8s.gcr.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /test-pd
      name: test-volume
  volumes:
  - name: test-volume
    hostPath:
      # directory location on host
      path: /data
      # this field is optional
      type: Directory
```

### 2.2.1. 同步文件变化到容器内

`hostPath`的挂载方式可以挂载目录和文件两种格式，如果使用文件挂载的方式，通过简单的`vi`等命令修改宿主机的文件，并不会实时同步到容器内的映射文件。而需要对容器进行重启的操作才可以把文件的修改内容同步到文件中，但生产的容器一般不建议执行重启的操作。因此我们可以通过以下的方式来避免这个问题的发生。

以上文件不同步的本质原因是容器在初次挂载的时候使用了宿主机的文件的inode number进行标识，而**vi等操作会导致文件的inode number发生变化**，所以当宿主机文件的inode number发生变化，容器内并不会发生变化，**为了保持文件内容一致，则需要保持修改文件的同时文件的inode number不变**。那么我们**可以使用 cat 或echo 命令覆盖文件的内容则inode number不会发生变化。**

示例：

```yaml
      containers:
        volumeMounts:
        - mountPath: /etc/hosts
          name: hosts
          readOnly: true
      volumes:
      - hostPath:
          path: /etc/hosts
          type: FileOrCreate
        name: hosts
```

例如，以上的案例是通过挂载宿主机的/etc/hosts文件来映射到容器，如果想修改宿主机的hosts文件来同步容器内的hosts文件，可以通过以下的方式:

```bash
# 查看文件的inode
ls -i /etc/hosts
39324780 /etc/hosts

# 追加记录
echo "1.1.1.1 xxx.com" >> /etc/hosts

# 替换内容
sed 's/1.1.1.1/2.2.2.2/g' /etc/hosts > temp.txt
cat temp.txt > /etc/hosts

# 查看宿主机和容器内的inode号都没有发生变化
# crictl exec -it 20891de31a4a6 sh
/var/www/html # ls -i /etc/hosts
39324780 /etc/hosts
```

## 2.3. configMap

`configMap`提供了一种给Pod注入配置文件的方式，配置文件内容存储在configMap对象中，如果Pod使用configMap作为volume的类型，需要先创建configMap的对象。

**示例**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
spec:
  containers:
    - name: test
      image: busybox
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
  volumes:
    - name: config-vol
      configMap:
        name: log-config
        items:
          - key: log_level
            path: log_level
```

## 2.4. cephfs

`cephfs`的方式将Pod的存储挂载到`ceph`集群中，通过外部存储的方式持久化Pod的数据（即当Pod被删除数据仍可以存储在ceph集群中），前提是先部署和维护好一个ceph集群。

**示例**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cephfs
spec:
  containers:
  - name: cephfs-rw
    image: kubernetes/pause
    volumeMounts:
    - mountPath: "/mnt/cephfs"
      name: cephfs
  volumes:
  - name: cephfs
    cephfs:
      monitors:
      - 10.16.154.78:6789
      - 10.16.154.82:6789
      - 10.16.154.83:6789
      # by default the path is /, but you can override and mount a specific path of the filesystem by using the path attribute
      # path: /some/path/in/side/cephfs 
      user: admin
      secretFile: "/etc/ceph/admin.secret"
      readOnly: true
```

更多可参考 [CephFS 示例](https://github.com/kubernetes/examples/tree/master/staging/volumes/cephfs/)。

## 2.5. nfs

`nfs`的方式类似cephfs，即将Pod数据存储到NFS集群中，具体可参考[NFS示例](https://github.com/kubernetes/examples/tree/master/staging/volumes/nfs)。

## 2.6. persistentVolumeClaim

`persistentVolumeClaim` 卷用于将`PersistentVolume`挂载到容器中。PersistentVolumes 是在用户不知道特定云环境的细节的情况下“声明”持久化存储（例如 GCE PersistentDisk 或 iSCSI 卷）的一种方式。 

参考文章：

- https://kubernetes.io/docs/concepts/storage/volumes/
