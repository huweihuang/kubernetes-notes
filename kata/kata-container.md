# Kata-container简介

kata-container通过轻量型虚拟机技术构建一个安全的容器运行时，表现像容器一样，但通硬件虚拟化技术提供强隔离，作为第二层的安全防护。

**特点：**

- 安全：独立的内核，提供网络、I/O、内存的隔离。
- 兼容性：支持OCI容器标准，k8s的CRI接口。
- 性能：兼容虚拟机的安全和容器的轻量特点。
- 简单：使用标准的接口。

# 1. kata-container架构

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1563362030/article/kata-container/arch_diagram.jpg">

**kata-container与传统container的比较**

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1563362032/article/kata-container/traditionalvskata.jpg">

# 2. [kata-runtime](https://github.com/kata-containers/runtime)

[Kata Containers runtime (`kata-runtime`)](https://github.com/kata-containers/runtime)通过`QEMU*/KVM`技术创建了一种轻量型的虚拟机，兼容 [OCI](https://github.com/opencontainers) [runtime specification](https://github.com/opencontainers/runtime-spec) 标准，支持[Kubernetes* Container Runtime Interface (CRI)](https://github.com/kubernetes/community/blob/master/contributors/devel/container-runtime-interface.md)接口，可替换[CRI shim runtime (runc)](https://github.com/opencontainers/runc) 通过k8s来创建pod或容器。

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1563362029/article/kata-container/docker-kata.png">

# 3. shim

`shim`类似Docker的 `containerd-shim` 或CRI-O的 `conmon`，主要用来监控和回收容器的进程，`kata-shim`需要处理所有的容器的IO流(`stdout`, `stdin` and `stderr`)和转发相关信号。

[containerd-shim-kata-v2](https://github.com/kata-containers/runtime/tree/master/containerd-shim-v2)实现了[Containerd Runtime V2 (Shim API)](https://github.com/containerd/containerd/tree/master/runtime/v2)，k8s可以通过`containerd-shim-kata-v2`（替代`2N+1`个`shims`[由一个`containerd-shim`和`kata-shim`组成]）来创建pod。

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1563362030/article/kata-container/shimv2.svg">

# 4. [kata-agent](https://github.com/kata-containers/agent)

在虚拟机内`kata-agent`作为一个daemon进程运行，并拉起容器的进程。kata-agent使用VIRTIO或VSOCK接口（QEMU在主机上暴露的socket文件）在guest虚拟机中运行gRPC服务器。kata-runtime通过grpc协议与kata-agent通信，向kata-agent发送管理容器的命令。该协议还用于容器和管理引擎（例如Docker Engine）之间传送I / O流（stdout，stderr，stdin）。

容器内所有的执行命令和相关的IO流都需要通过QEMU在宿主机暴露的`virtio-serial`或`vsock`接口，当使用VIRTIO的情况下，每个虚拟机会创建一个[Kata Containers proxy (`kata-proxy`)](https://github.com/kata-containers/proxy) 来处理命令和IO流。

`kata-agent`使用[`libcontainer`](https://github.com/opencontainers/runc/tree/master/libcontainer) 来管理容器的生命周期，复用了[`runc`](https://github.com/opencontainers/runc)的部分代码。

# 5. kata-proxy

`kata-proxy`提供了 `kata-shim` 和 `kata-runtime` 与VM中的`kata-agent`通信的方式，其中通信方式是使用`virtio-serial`或`vsock`，默认是使用`virtio-serial`。



# 6. Hypervisor

kata-container通过[QEMU](http://www.qemu-project.org/)/[KVM](http://www.linux-kvm.org/page/Main_Page)来创建虚拟机给容器运行，可以支持多种hypervisors。

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1563362028/article/kata-container/qemu.png">

# 7. QEMU/KVM

> 待补充


参考文档：

- https://katacontainers.io/

- https://github.com/kata-containers/documentation/blob/master/design/architecture.md
