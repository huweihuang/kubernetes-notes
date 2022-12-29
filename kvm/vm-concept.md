---
title: "虚拟化相关概念"
weight: 1
catalog: true
date: 2019-07-10 10:50:57
subtitle:
header-img: 
tags:
- KubeVirt
catagories:
- KubeVirt
---

# 1. 虚拟化

借助虚拟化技术，用户能以单个物理硬件系统为基础，创建多个模拟环境或专用资源，并使用一款名为“Hypervisor”（虚拟机监控程序）的软件直接连接到硬件，从而将一个系统划分为不同、单独而安全的环境，即虚拟机 (VM)。

虚拟化技术可以重新划分IT资源，提高资源的利用率。

# 2. 虚拟化的类型

**全虚拟化（Full virtualization）**

全虚拟化使用未修改的guest操作系统版本，guest直接与CPU通信，是最快的虚拟化方法。

**半虚拟化（Paravirtualization）**

半虚拟化使用修改过的guest操作系统，guest与hypervisor通信，hypervisor将guest的调用传递给CPU和其他接口。因为通信经过hypervisor，因此比全虚拟化慢。

# 3. hypervisor

`hypervisor`又称为 **virtual machine monitor** (**VMM**)，是一个创建和运行虚拟机的程序。被 hypervisor 用来运行一个或多个虚拟机的计算机称为宿主机（`host machine`），这些虚拟机则称为客户机（`guest machine`）。

# 4. kvm

`kvm(Kernel-based Virtual Machine)`是Linux内核的虚拟化模块，可以利用Linux内核的功能来作为hypervisor。

KVM本身不进行模拟，而是暴露一个`/dev/kvm`接口。

使用KVM，可以在Linux的镜像上

<img src="https://upload.wikimedia.org/wikipedia/commons/5/5c/Kernel-based_Virtual_Machine_zh-CN.svg">

# 5. qemu

**QEMU**（quick emulator）

> 待补充



# 6. libvirt

libvirt是一个硬件虚拟化的管理工具API，可用于KVM、QEMU等虚拟化技术，

<img src="https://upload.wikimedia.org/wikipedia/commons/d/d0/Libvirt_support.svg">



参考：

- https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/virtualization_getting_started_guide/chap-virtualization_getting_started-what_is_it
- https://en.wikipedia.org/wiki/Hypervisor
- https://www.linux-kvm.org/page/Main_Page
- [http://www.linux-kvm.org/page/Documents](http://www.linux-kvm.org/page/Documents)
- https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine
- https://wiki.qemu.org/Index.html


