---
title: "k8s管理GPU容器"
weight: 1
catalog: true
date: 2025-6-23 16:22:24
subtitle:
header-img:
tags:
- GPU
catagories:
- GPU
---

本文主要描述如何在k8s中管理GPU的节点和容器。

Kubernetes（K8s）对 GPU 的支持，适合用于机器学习、深度学习、图像处理等高性能计算场景。

# 1. 实现思路

K8s 本身不直接管理 GPU，而是通过 **NVIDIA 的 GPU 设备插件（NVIDIA Device Plugin）** 将 GPU 资源暴露给容器。整个流程如下：

```bash
物理 GPU → 安装驱动 + 宿主机工具 → 容器 runtime（如 containerd）→ Kubernetes 通过 device plugin 管理 → Pod 使用 GPU
```

# 2. 实现步骤

## 2.1. 节点准备（仅 GPU 节点需要）

运行 NVIDIA 设备插件的先决条件如下：

- NVIDIA 驱动程序 ~= 384.81
- nvidia-docker >= 2.0 || nvidia-container-toolkit >= 1.7.0（>= 1.11.0 在基于 Tegra 的系统上使用集成 GPU）
- nvidia-container-runtime 配置为默认低级运行时
- Kubernetes 版本 >= 1.10

安装 **NVIDIA 官方驱动**。

```bash
# 示例安装命令（Ubuntu）
sudo apt install nvidia-driver-525
nvidia-smi  # 验证 GPU 可用
```

## 2.2. 安装容器运行时插件（containerd 支持）

安装 NVIDIA Container Toolkit，参考[Installing the NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update

export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.8-1
  sudo apt-get install -y \
      nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}
```

配置containerd

nvidia-ctk会修改containerd的配置使得containerd可以使用NVIDIA Container Runtime。

```bash
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart containerd
```

## 2.3. 安装 NVIDIA Device Plugin（K8s 插件）

NVIDIA device plugin 通过k8s daemonset的方式部署到每个k8s的node节点上，实现了[Kubernetes device plugin](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/resource-management/device-plugin.md)的接口。

提供以下功能：

- 暴露每个节点的GPU数量给集群
- 跟踪GPU的健康情况
- 使在k8s的节点可以运行GPU容器

```bash
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml
```

- 它会在每个 GPU 节点启动一个 `nvidia-device-plugin` DaemonSet。

- 它会向节点注册一个 `nvidia.com/gpu` 资源。

## 2.4. 编写使用 GPU 的 Pod/Deployment

部署守护进程后，容器现在可以使用以下`nvidia.com/gpu`资源类型请求 NVIDIA GPU：

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  restartPolicy: Never
  containers:
    - name: cuda-container
      image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0
      resources:
        limits:
          nvidia.com/gpu: 1 # requesting 1 GPU
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
EOF
```

# 3. nvidia-device-plugin内容

nvidia-device-plugin的daemonset yaml文件如下，具体参考：[nvidia-device-plugin.yml](https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml)

```yaml
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
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      # Mark this pod as a critical add-on; when enabled, the critical add-on
      # scheduler reserves resources for critical add-on pods so that they can
      # be rescheduled after a failure.
      # See https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/
      priorityClassName: "system-node-critical"
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.17.1
        name: nvidia-device-plugin-ctr
        env:
          - name: FAIL_ON_INIT_ERROR
            value: "false"
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

- [调度 GPU | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/manage-gpus/scheduling-gpus/)

- [configuring-containerd-for-kubernetes](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#configuring-containerd-for-kubernetes)

- [Installing the NVIDIA Container Toolkit ](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

- [k8s-device-plugin](https://github.com/kubernetes/design-proposals-archive/blob/main/resource-management/device-plugin.md)

- [gpu-support](https://github.com/kubernetes/design-proposals-archive/blob/main/resource-management/gpu-support.md)
