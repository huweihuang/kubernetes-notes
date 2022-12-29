---
title: "Runc和Containerd概述"
weight: 1
catalog: true
date: 2021-09-17 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Kubernetes
- Runtime
catagories:
- Kubernetes
---

> 本文主要分析OCI，CRI，runc，containerd，cri-containerd，dockershim等组件说明及调用关系。

# 1. 概述

各个组件调用关系图如下：

![关系图](https://res.cloudinary.com/dqxtn0ick/image/upload/v1631845163/article/kubernetes/containerd/runtime.webp)

> 图片来源：https://www.jianshu.com/p/62e71584d1cb

# 2. [OCI（Open Container Initiative）](https://opencontainers.org/about/overview/)

OCI（Open Container Initiative）即开放的容器运行时`规范`，目的在于定义一个容器运行时及镜像的相关标准和规范，其中包括

- runtime-spec：容器的生命周期管理，具体参考[runtime-spec](https://github.com/opencontainers/runtime-spec/blob/master/runtime.md)。
- image-spec：镜像的生命周期管理，具体参考[image-spec](https://github.com/opencontainers/image-spec/blob/main/spec.md)。

实现OCI标准的容器运行时有`runc`，`kata`等。

# 3. [RunC](https://github.com/opencontainers/runc)

`runc(run container)`是一个基于OCI标准实现的一个轻量级容器运行工具，用来创建和运行容器。而Containerd是用来维持通过runc创建的容器的运行状态。即runc用来创建和运行容器，containerd作为常驻进程用来管理容器。

runc包含libcontainer，包括对namespace和cgroup的调用操作。

命令参数：

```bash
To start a new instance of a container:

    # runc run [ -b bundle ] <container-id>
    
USAGE:
   runc [global options] command [command options] [arguments...]

COMMANDS:
   checkpoint  checkpoint a running container
   create      create a container
   delete      delete any resources held by the container often used with detached container
   events      display container events such as OOM notifications, cpu, memory, and IO usage statistics
   exec        execute new process inside the container
   init        initialize the namespaces and launch the process (do not call it outside of runc)
   kill        kill sends the specified signal (default: SIGTERM) to the container's init process
   list        lists containers started by runc with the given root
   pause       pause suspends all processes inside the container
   ps          ps displays the processes running inside a container
   restore     restore a container from a previous checkpoint
   resume      resumes all processes that have been previously paused
   run         create and run a container
   spec        create a new specification file
   start       executes the user defined process in a created container
   state       output the state of a container
   update      update container resource constraints
   help, h     Shows a list of commands or help for one command    
```

# 4. [Containerd](https://github.com/containerd/containerd)

`containerd（container daemon）`是一个daemon进程用来管理和运行容器，可以用来拉取/推送镜像和管理容器的存储和网络。其中可以调用runc来创建和运行容器。

## 4.1. containerd的架构图

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1630634542/article/kubernetes/containerd/containerd-arch.png)

## 4.2. docker与containerd、runc的关系图

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1631847625/article/kubernetes/containerd/container-ecosystem-docker.drawio.png)

更具体的调用逻辑：

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1631854201/article/kubernetes/containerd/containerd-shim.png)

# 5. CRI（[Container Runtime Interface](https://github.com/kubernetes/kubernetes/blob/242a97307b34076d5d8f5bbeb154fa4d97c9ef1d/docs/devel/container-runtime-interface.md) ）

**CRI即容器运行时接口，主要用来定义k8s与容器运行时的API调用**，kubelet通过CRI来调用容器运行时，只要实现了CRI接口的容器运行时就可以对接到k8s的kubelet组件。

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1631849764/article/kubernetes/containerd/kubelet-cri.png)

## 5.1. docker与k8s调用containerd的关系图

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1631847625/article/kubernetes/containerd/container-ecosystem.drawio.png)

## 5.2. [cri-api](https://github.com/kubernetes/cri-api/blob/master/pkg/apis/runtime/v1/api.proto)

### 5.2.1. runtime service

```go
// Runtime service defines the public APIs for remote container runtimes
service RuntimeService {
    // Version returns the runtime name, runtime version, and runtime API version.
    rpc Version(VersionRequest) returns (VersionResponse) {}

    // RunPodSandbox creates and starts a pod-level sandbox. Runtimes must ensure
    // the sandbox is in the ready state on success.
    rpc RunPodSandbox(RunPodSandboxRequest) returns (RunPodSandboxResponse) {}
    // StopPodSandbox stops any running process that is part of the sandbox and
    // reclaims network resources (e.g., IP addresses) allocated to the sandbox.
    // If there are any running containers in the sandbox, they must be forcibly
    // terminated.
    // This call is idempotent, and must not return an error if all relevant
    // resources have already been reclaimed. kubelet will call StopPodSandbox
    // at least once before calling RemovePodSandbox. It will also attempt to
    // reclaim resources eagerly, as soon as a sandbox is not needed. Hence,
    // multiple StopPodSandbox calls are expected.
    rpc StopPodSandbox(StopPodSandboxRequest) returns (StopPodSandboxResponse) {}
    // RemovePodSandbox removes the sandbox. If there are any running containers
    // in the sandbox, they must be forcibly terminated and removed.
    // This call is idempotent, and must not return an error if the sandbox has
    // already been removed.
    rpc RemovePodSandbox(RemovePodSandboxRequest) returns (RemovePodSandboxResponse) {}
    // PodSandboxStatus returns the status of the PodSandbox. If the PodSandbox is not
    // present, returns an error.
    rpc PodSandboxStatus(PodSandboxStatusRequest) returns (PodSandboxStatusResponse) {}
    // ListPodSandbox returns a list of PodSandboxes.
    rpc ListPodSandbox(ListPodSandboxRequest) returns (ListPodSandboxResponse) {}

    // CreateContainer creates a new container in specified PodSandbox
    rpc CreateContainer(CreateContainerRequest) returns (CreateContainerResponse) {}
    // StartContainer starts the container.
    rpc StartContainer(StartContainerRequest) returns (StartContainerResponse) {}
    // StopContainer stops a running container with a grace period (i.e., timeout).
    // This call is idempotent, and must not return an error if the container has
    // already been stopped.
    // The runtime must forcibly kill the container after the grace period is
    // reached.
    rpc StopContainer(StopContainerRequest) returns (StopContainerResponse) {}
    // RemoveContainer removes the container. If the container is running, the
    // container must be forcibly removed.
    // This call is idempotent, and must not return an error if the container has
    // already been removed.
    rpc RemoveContainer(RemoveContainerRequest) returns (RemoveContainerResponse) {}
    // ListContainers lists all containers by filters.
    rpc ListContainers(ListContainersRequest) returns (ListContainersResponse) {}
    // ContainerStatus returns status of the container. If the container is not
    // present, returns an error.
    rpc ContainerStatus(ContainerStatusRequest) returns (ContainerStatusResponse) {}
    // UpdateContainerResources updates ContainerConfig of the container.
    rpc UpdateContainerResources(UpdateContainerResourcesRequest) returns (UpdateContainerResourcesResponse) {}
    // ReopenContainerLog asks runtime to reopen the stdout/stderr log file
    // for the container. This is often called after the log file has been
    // rotated. If the container is not running, container runtime can choose
    // to either create a new log file and return nil, or return an error.
    // Once it returns error, new container log file MUST NOT be created.
    rpc ReopenContainerLog(ReopenContainerLogRequest) returns (ReopenContainerLogResponse) {}

    // ExecSync runs a command in a container synchronously.
    rpc ExecSync(ExecSyncRequest) returns (ExecSyncResponse) {}
    // Exec prepares a streaming endpoint to execute a command in the container.
    rpc Exec(ExecRequest) returns (ExecResponse) {}
    // Attach prepares a streaming endpoint to attach to a running container.
    rpc Attach(AttachRequest) returns (AttachResponse) {}
    // PortForward prepares a streaming endpoint to forward ports from a PodSandbox.
    rpc PortForward(PortForwardRequest) returns (PortForwardResponse) {}

    // ContainerStats returns stats of the container. If the container does not
    // exist, the call returns an error.
    rpc ContainerStats(ContainerStatsRequest) returns (ContainerStatsResponse) {}
    // ListContainerStats returns stats of all running containers.
    rpc ListContainerStats(ListContainerStatsRequest) returns (ListContainerStatsResponse) {}

    // UpdateRuntimeConfig updates the runtime configuration based on the given request.
    rpc UpdateRuntimeConfig(UpdateRuntimeConfigRequest) returns (UpdateRuntimeConfigResponse) {}

    // Status returns the status of the runtime.
    rpc Status(StatusRequest) returns (StatusResponse) {}
}
```

### 5.2.2. image service

```go
// ImageService defines the public APIs for managing images.
service ImageService {
    // ListImages lists existing images.
    rpc ListImages(ListImagesRequest) returns (ListImagesResponse) {}
    // ImageStatus returns the status of the image. If the image is not
    // present, returns a response with ImageStatusResponse.Image set to
    // nil.
    rpc ImageStatus(ImageStatusRequest) returns (ImageStatusResponse) {}
    // PullImage pulls an image with authentication config.
    rpc PullImage(PullImageRequest) returns (PullImageResponse) {}
    // RemoveImage removes the image.
    // This call is idempotent, and must not return an error if the image has
    // already been removed.
    rpc RemoveImage(RemoveImageRequest) returns (RemoveImageResponse) {}
    // ImageFSInfo returns information of the filesystem that is used to store images.
    rpc ImageFsInfo(ImageFsInfoRequest) returns (ImageFsInfoResponse) {}
}
```

## 5.3. cri-containerd

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1631849203/article/kubernetes/containerd/cri-plugin-architecture.png)

### 5.3.1. CRI Plugin调用流程

1. kubelet调用CRI插件，通过CRI Runtime Service接口创建pod
2. cri通过CNI接口创建和配置pod的network namespace
3. cri调用containerd创建sandbox container（[pause container](https://www.ianlewis.org/en/almighty-pause-container) ）并将容器放入pod的cgroup和namespace中
4. kubelet调用CRI插件，通过image service接口拉取镜像，接着通过containerd来拉取镜像
5. kubelet调用CRI插件，通过runtime service接口运行拉取下来的镜像服务，最后通过containerd来运行业务容器，并将容器放入pod的cgroup和namespace中。

> 具体参考：https://github.com/containerd/cri/blob/release/1.4/docs/architecture.md

### 5.3.2. k8s对runtime调用的演进

由原来通过dockershim调用docker再调用containerd，直接变成通过cri-containerd调用containerd，从而减少了一层docker调用逻辑。

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1631854007/article/kubernetes/containerd/cri-performance.png)

> 具体参考：https://github.com/containerd/cri/blob/release/1.4/docs/proposal.md

## 5.4. [Dockershim](https://github.com/kubernetes/kubernetes/tree/master/pkg/kubelet/dockershim)

在旧版本的k8s中，由于docker没有实现CRI接口，因此增加一个Dockershim来实现k8s对docker的调用。（shim：垫片，一般用来表示对第三方组件API调用的适配插件，例如k8s使用Dockershim来实现对docker接口的适配调用）

## 5.5. CRI-O

cri-o与containerd类似，用来实现容器的管理，可替换containerd的使用。





参考：

- https://opencontainers.org/about/overview/
- https://github.com/opencontainers/runtime-spec
- https://github.com/kubernetes/kubernetes/blob/242a97307b34076d5d8f5bbeb154fa4d97c9ef1d/docs/devel/container-runtime-interface.md
- https://github.com/containerd/containerd/blob/main/docs/cri/architecture.md
- https://www.tutorialworks.com/difference-docker-containerd-runc-crio-oci/
- https://kubernetes.io/zh/docs/setup/production-environment/container-runtimes/

