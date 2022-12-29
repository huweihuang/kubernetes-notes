---
title: "Lxcfs资源视图隔离"
weight: 4
catalog: true
date: 2021-07-18 13:41:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. 资源视图隔离

容器中的执行`top`、`free`等命令展示出来的CPU，内存等信息是从`/proc`目录中的相关文件里读取出来的。而容器并没有对`/proc`，`/sys`等文件系统做隔离，因此容器中读取出来的CPU和内存的信息是宿主机的信息，与容器实际分配和限制的资源量不同。

```bash
/proc/cpuinfo
/proc/diskstats
/proc/meminfo
/proc/stat
/proc/swaps
/proc/uptime
```

为了实现让容器内部的资源视图更像虚拟机，使得应用程序可以拿到真实的CPU和内存信息，就需要通过文件挂载的方式将cgroup的真实的容器资源信息挂载到容器内`/proc`下的文件，使得容器内执行top、free等命令时可以拿到真实的CPU和内存信息。

# 2. Lxcfs简介

lxcfs是一个FUSE文件系统，使得Linux容器的文件系统更像虚拟机。lxcfs是一个常驻进程运行在宿主机上，从而来自动维护宿主机cgroup中容器的真实资源信息与容器内`/proc`下文件的映射关系。

lxcfs的命令信息如下：

```bash
#/usr/local/bin/lxcfs -h
Usage:

lxcfs [-f|-d] -u -l -n [-p pidfile] mountpoint
  -f running foreground by default; -d enable debug output
  -l use loadavg
  -u no swap
  Default pidfile is /run/lxcfs.pid
lxcfs -h
```

lxcfs的源码：https://github.com/lxc/lxcfs

# 3. Lxcfs原理

lxcfs实现的基本原理是通过文件挂载的方式，把cgroup中容器相关的信息读取出来，存储到lxcfs相关的目录下，并将相关目录映射到容器内的/proc目录下，从而使得容器内执行top,free等命令时拿到的/proc下的数据是真实的cgroup分配给容器的CPU和内存数据。

**原理图**

![lxcfs](https://res.cloudinary.com/dqxtn0ick/image/upload/v1626002975/article/kubernetes/resource/lxcfs/lxcfs.webp)

**映射目录**

| 类别 | 容器内目录                     | 宿主机lxcfs目录                                             |
| ---- | ------------------------------ | ----------------------------------------------------------- |
| cpu  | /proc/cpuinfo                  | /var/lib/lxcfs/{container_id}/proc/cpuinfo                  |
| 内存 | /proc/meminfo                  | /var/lib/lxcfs/{container_id}/proc/meminfo                  |
|      | /proc/diskstats                | /var/lib/lxcfs/{container_id}/proc/diskstats                |
|      | /proc/stat                     | /var/lib/lxcfs/{container_id}/proc/stat                     |
|      | /proc/swaps                    | /var/lib/lxcfs/{container_id}/proc/swaps                    |
|      | /proc/uptime                   | /var/lib/lxcfs/{container_id}/proc/uptime                   |
|      | /proc/loadavg                  | /var/lib/lxcfs/{container_id}/proc/loadavg                  |
|      | /sys/devices/system/cpu/online | /var/lib/lxcfs/{container_id}/sys/devices/system/cpu/online |

# 4. 使用方式

## 4.1. 安装lxcfs

环境准备

```bash
yum install -y fuse fuse-lib fuse-devel
```

源码编译安装

```bash
git clone git://github.com/lxc/lxcfs
cd lxcfs
./bootstrap.sh
./configure
make
make install
```

或者通过rpm包安装

```bash
wget https://copr-be.cloud.fedoraproject.org/results/ganto/lxc3/epel-7-x86_64/01041891-lxcfs/lxcfs-3.1.2-0.2.el7.x86_64.rpm;
rpm -ivh lxcfs-3.1.2-0.2.el7.x86_64.rpm --force --nodeps
```

查看是否安装成功

```bash
lxcfs -h
```

## 4.2. 运行lxcfs

运行lxcfs主要执行两条命令。

```bash
sudo mkdir -p /var/lib/lxcfs
sudo lxcfs /var/lib/lxcfs
```

可以通过systemd运行。

lxcfs.service文件：

```bash
cat > /usr/lib/systemd/system/lxcfs.service <<EOF
[Unit]
Description=lxcfs

[Service]
ExecStart=/usr/bin/lxcfs -f /var/lib/lxcfs
Restart=on-failure
#ExecReload=/bin/kill -s SIGHUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
```

运行命令

```bash
systemctl daemon-reload && systemctl enable lxcfs && systemctl start lxcfs && systemctl status lxcfs 
```

## 4.3. 挂载容器内`/proc`下的文件目录

```bash
docker run -it --rm -m 256m  --cpus 2  \
      -v /var/lib/lxcfs/proc/cpuinfo:/proc/cpuinfo:rw \
      -v /var/lib/lxcfs/proc/diskstats:/proc/diskstats:rw \
      -v /var/lib/lxcfs/proc/meminfo:/proc/meminfo:rw \
      -v /var/lib/lxcfs/proc/stat:/proc/stat:rw \
      -v /var/lib/lxcfs/proc/swaps:/proc/swaps:rw \
      -v /var/lib/lxcfs/proc/uptime:/proc/uptime:rw \
      nginx:latest /bin/sh
```

## 4.4. 验证容器内CPU和内存

```bash
# cpu
grep -c processor /proc/cpuinfo
cat /proc/cpuinfo

# memory
free -g
cat /proc/meminfo
```

# 5. 使用k8s集群部署

使用k8s集群部署与systemd部署方式同理，需要解决2个问题：

1. 在每个node节点上部署lxcfs常驻进程，lxcfs需要通过镜像来运行，可以通过daemonset来部署。
2. 实现将lxcfs维护的目录自动挂载到pod内的`/proc`目录。

具体可参考：https://github.com/denverdino/lxcfs-admission-webhook

## 5.1. lxcfs-image

[Dockerfile](https://github.com/denverdino/lxcfs-admission-webhook/blob/master/lxcfs-image/Dockerfile)

```bash
FROM centos:7 as build
RUN yum -y update
RUN yum -y install fuse-devel pam-devel wget install gcc automake autoconf libtool make
ENV LXCFS_VERSION 3.1.2
RUN wget https://linuxcontainers.org/downloads/lxcfs/lxcfs-$LXCFS_VERSION.tar.gz && \
	mkdir /lxcfs && tar xzvf lxcfs-$LXCFS_VERSION.tar.gz -C /lxcfs  --strip-components=1 && \
	cd /lxcfs && ./configure && make

FROM centos:7
STOPSIGNAL SIGINT
COPY --from=build /lxcfs/lxcfs /usr/local/bin/lxcfs
COPY --from=build /lxcfs/.libs/liblxcfs.so /usr/local/lib/lxcfs/liblxcfs.so
COPY --from=build /lxcfs/lxcfs /lxcfs/lxcfs
COPY --from=build /lxcfs/.libs/liblxcfs.so /lxcfs/liblxcfs.so
COPY --from=build /usr/lib64/libfuse.so.2.9.2 /usr/lib64/libfuse.so.2.9.2
COPY --from=build /usr/lib64/libulockmgr.so.1.0.1 /usr/lib64/libulockmgr.so.1.0.1
RUN ln -s /usr/lib64/libfuse.so.2.9.2 /usr/lib64/libfuse.so.2 && \
    ln -s /usr/lib64/libulockmgr.so.1.0.1 /usr/lib64/libulockmgr.so.1
COPY start.sh /
CMD ["/start.sh"]
```

star.sh

```bash
#!/bin/bash

# Cleanup
nsenter -m/proc/1/ns/mnt fusermount -u /var/lib/lxcfs 2> /dev/null || true
nsenter -m/proc/1/ns/mnt [ -L /etc/mtab ] || \
        sed -i "/^lxcfs \/var\/lib\/lxcfs fuse.lxcfs/d" /etc/mtab

# Prepare
mkdir -p /usr/local/lib/lxcfs /var/lib/lxcfs

# Update lxcfs
cp -f /lxcfs/lxcfs /usr/local/bin/lxcfs
cp -f /lxcfs/liblxcfs.so /usr/local/lib/lxcfs/liblxcfs.so


# Mount
exec nsenter -m/proc/1/ns/mnt /usr/local/bin/lxcfs /var/lib/lxcfs/
```

## 5.2. daemonset

[lxcfs-daemonset.yaml](https://github.com/denverdino/lxcfs-admission-webhook/blob/master/deployment/lxcfs-daemonset.yaml)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: lxcfs
  labels:
    app: lxcfs
spec:
  selector:
    matchLabels:
      app: lxcfs
  template:
    metadata:
      labels:
        app: lxcfs
    spec:
      hostPID: true
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: lxcfs
        image: registry.cn-hangzhou.aliyuncs.com/denverdino/lxcfs:3.1.2
        imagePullPolicy: Always
        securityContext:
          privileged: true
        volumeMounts:
        - name: cgroup
          mountPath: /sys/fs/cgroup
        - name: lxcfs
          mountPath: /var/lib/lxcfs
          mountPropagation: Bidirectional
        - name: usr-local
          mountPath: /usr/local
      volumes:
      - name: cgroup
        hostPath:
          path: /sys/fs/cgroup
      - name: usr-local
        hostPath:
          path: /usr/local
      - name: lxcfs
        hostPath:
          path: /var/lib/lxcfs
          type: DirectoryOrCreate
```

## 5.3. [lxcfs-admission-webhook](https://github.com/denverdino/lxcfs-admission-webhook)

`lxcfs-admission-webhook`实现了一个动态的准入webhook，更准确的讲是实现了一个[修改性质的webhook](https://kubernetes.io/zh/docs/reference/access-authn-authz/admission-controllers/#mutatingadmissionwebhook)，即监听pod的创建，然后对pod执行patch的操作，从而将lxcfs与容器内的目录映射关系植入到pod创建的yaml中从而实现自动挂载。

[deployment](https://github.com/denverdino/lxcfs-admission-webhook/blob/master/deployment/deployment.yaml)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lxcfs-admission-webhook-deployment
  labels:
    app: lxcfs-admission-webhook
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lxcfs-admission-webhook
  template:
    metadata:
      labels:
        app: lxcfs-admission-webhook
    spec:
      containers:
        - name: lxcfs-admission-webhook
          image: registry.cn-hangzhou.aliyuncs.com/denverdino/lxcfs-admission-webhook:v1
          imagePullPolicy: IfNotPresent
          args:
            - -tlsCertFile=/etc/webhook/certs/cert.pem
            - -tlsKeyFile=/etc/webhook/certs/key.pem
            - -alsologtostderr
            - -v=4
            - 2>&1
          volumeMounts:
            - name: webhook-certs
              mountPath: /etc/webhook/certs
              readOnly: true
      volumes:
        - name: webhook-certs
          secret:
            secretName: lxcfs-admission-webhook-certs
```

具体部署参考:[install.sh](https://github.com/denverdino/lxcfs-admission-webhook/blob/master/deployment/install.sh)

```bash
#!/bin/bash

./deployment/webhook-create-signed-cert.sh
kubectl get secret lxcfs-admission-webhook-certs

kubectl create -f deployment/deployment.yaml
kubectl create -f deployment/service.yaml
cat ./deployment/mutatingwebhook.yaml | ./deployment/webhook-patch-ca-bundle.sh > ./deployment/mutatingwebhook-ca-bundle.yaml
kubectl create -f deployment/mutatingwebhook-ca-bundle.yaml
```

执行命令

```bash
/deployment/install.sh
```





参考：

- https://github.com/lxc/lxcfs
- https://linuxcontainers.org/lxcfs/
- https://github.com/denverdino/lxcfs-admission-webhook
- https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/





