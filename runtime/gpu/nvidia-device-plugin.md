---
title: "nvidia-device-plugin介绍"
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

# 1. 简介

NVIDIA device plugin 通过k8s daemonset的方式部署到每个k8s的node节点上，实现了[Kubernetes device plugin](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/resource-management/device-plugin.md)的接口。

提供以下功能：

- 暴露每个节点的GPU数量给集群
- 跟踪GPU的健康情况
- 使在k8s的节点可以运行GPU容器

# 2. 要求

- NVIDIA drivers ~= 384.81
- nvidia-docker version > 2.0 (see how to [install](https://github.com/NVIDIA/nvidia-docker) and it's [prerequisites](https://github.com/nvidia/nvidia-docker/wiki/Installation-(version-2.0)#prerequisites))
- docker configured with nvidia as the [default runtime](https://github.com/NVIDIA/nvidia-docker/wiki/Advanced-topics#default-runtime).
- Kubernetes version >= 1.10

# 3. 使用

## 3.1. 安装NVIDIA drivers和nvidia-docker

提供GPU节点的机器，准备工作如下

1. 安装NVIDIA drivers ~= 384.81
2. 安装nvidia-docker version > 2.0

## 3.2. 配置docker runtime

配置nvidia runtime作为GPU节点的默认runtime。

修改文件/etc/docker/daemon.json，增加以下runtime内容。

```json
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
```

## 3.3. 部署nvidia-device-plugin

```bash
$ kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/1.0.0-beta4/nvidia-device-plugin.yml
```

nvidia-device-plugin的daemonset yaml文件如下：

```yaml
# Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      # This annotation is deprecated. Kept here for backward compatibility
      # See https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      # This toleration is deprecated. Kept here for backward compatibility
      # See https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/
      - key: CriticalAddonsOnly
        operator: Exists
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      # Mark this pod as a critical add-on; when enabled, the critical add-on
      # scheduler reserves resources for critical add-on pods so that they can
      # be rescheduled after a failure.
      # See https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/
      priorityClassName: "system-node-critical"
      containers:
      - image: nvidia/k8s-device-plugin:1.0.0-beta4
        name: nvidia-device-plugin-ctr
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
          - name: device-plugin
            mountPath: /var/lib/kubelet/device-plugins
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
```

## 3.4. 运行GPU任务

创建一个GPU的pod，pod的资源类型指定为`nvidia.com/gpu`。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  containers:
    - name: cuda-container
      image: nvidia/cuda:9.0-devel
      resources:
        limits:
          nvidia.com/gpu: 2 # requesting 2 GPUs
    - name: digits-container
      image: nvidia/digits:6.0
      resources:
        limits:
          nvidia.com/gpu: 2 # requesting 2 GPUs
```

# 4. 构建和运行nvidia-device-plugin

## 4.1. docker方式

### 4.1.1. 编译

- 直接拉取dockerhub的镜像

```bash
$ docker pull nvidia/k8s-device-plugin:1.0.0-beta4
```

- 拉取代码构建镜像

```bash
$ docker build -t nvidia/k8s-device-plugin:1.0.0-beta4 https://github.com/NVIDIA/k8s-device-plugin.git#1.0.0-beta4
```

- 修改nvidia-device-plugin后构建镜像

```bash
$ git clone https://github.com/NVIDIA/k8s-device-plugin.git && cd k8s-device-plugin
$ git checkout 1.0.0-beta4
$ docker build -t nvidia/k8s-device-plugin:1.0.0-beta4 .
```

### 4.1.2. 运行

- docker本地运行

```bash
$ docker run --security-opt=no-new-privileges --cap-drop=ALL --network=none -it -v /var/lib/kubelet/device-plugins:/var/lib/kubelet/device-plugins nvidia/k8s-device-plugin:1.0.0-beta4
```

- daemonset运行

```bash
$ kubectl create -f nvidia-device-plugin.yml
```

## 4.2. 非docker方式

### 4.2.1. 编译

```bash
$ C_INCLUDE_PATH=/usr/local/cuda/include LIBRARY_PATH=/usr/local/cuda/lib64 go build
```

### 4.2.2. 本地运行

```bash
$ ./k8s-device-plugin
```





参考：

- https://github.com/NVIDIA/k8s-device-plugin
- [k8s-device-plugin](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/resource-management/device-plugin.md)
- [gpu-support](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/resource-management/gpu-support.md)