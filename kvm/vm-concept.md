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

在虚拟化技术中，Hypervisor（虚拟机监视器）是一种软件、固件或硬件，能够创建和运行虚拟机（VM）。Hypervisor 起到物理硬件与虚拟机之间的中介作用，管理和分配物理资源（如 CPU、内存、存储和网络）给虚拟机，并确保每个虚拟机的隔离性和安全性。

**Hypervisor 的功能**

1. **虚拟化资源管理**：
   - 分配物理硬件资源（CPU、内存、存储、网络）给虚拟机。
   - 管理和调度虚拟机的运行。
2. **虚拟机隔离**：
   - 确保虚拟机之间的隔离性，防止一个虚拟机的故障或安全问题影响其他虚拟机。
3. **硬件抽象**：
   - 抽象底层硬件，使虚拟机可以运行在不同的硬件平台上，而无需修改虚拟机内的操作系统和应用程序。
4. **资源优化**：
   - 动态调整虚拟机资源，提供负载均衡、资源共享和节能功能。
5. **高可用性和容错**：
   - 提供虚拟机快照、备份和恢复功能，确保高可用性和数据安全。
   - 支持虚拟机迁移和克隆，方便运维管理。

**Hypervisor 的优点**

- **硬件利用率**：通过虚拟化，可以更高效地利用物理硬件资源，减少硬件浪费。
- **灵活性**：虚拟机可以轻松创建、删除和迁移，方便开发、测试和部署。
- **隔离性**：虚拟机之间相互隔离，提高系统安全性和稳定性。
- **成本效益**：减少对物理硬件的需求，降低硬件和维护成本。

# 4. kvm

`kvm(Kernel-based Virtual Machine)`是Linux内核的虚拟化模块，可以利用Linux内核的功能来作为hypervisor。

KVM本身不进行模拟，而是暴露一个`/dev/kvm`接口。

使用KVM，可以在Linux的镜像上

<img src="https://upload.wikimedia.org/wikipedia/commons/5/5c/Kernel-based_Virtual_Machine_zh-CN.svg" width="50%">

# 5. qemu

QEMU（Quick Emulator）是一个开源的硬件虚拟化和仿真器软件。它被广泛用于创建和运行虚拟机，支持多种不同的硬件平台和操作系统。以下是对 QEMU 的详细介绍：

**QEMU 的主要特点**

1. **虚拟化和仿真**：
   - **虚拟化**：QEMU 能够利用硬件虚拟化技术（如 Intel VT-x 和 AMD-V）来运行虚拟机。通过硬件辅助虚拟化，QEMU 可以提供接近原生性能的虚拟机运行环境。
   - **仿真**：QEMU 还可以完全在软件中仿真硬件，无需硬件虚拟化支持。这种模式下，QEMU 能够仿真多种不同的 CPU 架构（如 x86、ARM、MIPS、PowerPC 等），适用于跨平台开发和测试。
2. **多种平台支持**：
   - QEMU 支持多种不同的主机平台和目标平台，能够在一个平台上运行不同架构的操作系统。这使得 QEMU 成为跨平台开发和测试的理想工具。
3. **与 KVM 集成**：
   - QEMU 可以与内核虚拟机（KVM）集成使用，以提高虚拟化性能。KVM 提供了基于 Linux 内核的高效虚拟化解决方案，而 QEMU 提供了强大的虚拟机管理和仿真功能。
4. **设备仿真**：
   - QEMU 提供了丰富的设备仿真功能，包括网络接口、磁盘存储、图形显示、USB 设备等。这些设备仿真使得虚拟机能够模拟真实硬件环境，方便开发和测试。
5. **快照和恢复**：
   - QEMU 支持虚拟机快照功能，允许用户在特定时刻保存虚拟机的状态，并在需要时恢复到该状态。这对于调试和测试非常有用。

# 6. libvirt

Libvirt 是一个开源的虚拟化管理框架和工具集，用于管理不同的虚拟化技术，包括 KVM、QEMU、Xen、VMware ESXi、Hyper-V 以及其他一些虚拟化平台。它提供了一个统一的 API，用于创建、管理和监控虚拟机，使得对不同虚拟化技术的操作更加简化和一致。

<img src="https://upload.wikimedia.org/wikipedia/commons/d/d0/Libvirt_support.svg">



## 6.1. 特点

1. **统一接口**

- 提供了一个统一的 API 和命令行工具，使用户和开发者可以通过一致的接口管理不同的虚拟化技术。

2. **多种虚拟化技术支持**：
   - 支持多种虚拟化平台，如 KVM、QEMU、Xen、VMware ESXi、Hyper-V、LXC（Linux 容器）等，提供跨平台的虚拟化管理功能。
3. **管理和监控**：
   - 提供强大的管理和监控功能，包括创建、启动、停止、迁移虚拟机，以及管理存储和网络资源。
4. **XML 配置**：
   - 使用 XML 配置文件来定义虚拟机和资源，提供灵活和可扩展的配置方式，易于保存和版本控制。
5. **安全性**：
   - 支持多种安全机制，如基于 SELinux 的安全策略，确保虚拟机和宿主系统的隔离性和安全性。
6. **网络管理**：
   - 提供网络桥接、NAT、虚拟交换机等网络管理功能，支持复杂的网络拓扑配置。
7. **存储管理**：
   - 支持多种存储后端，如本地磁盘、网络文件系统（NFS）、iSCSI、LVM 等，方便虚拟机的存储资源管理。

## 6.2. 主要组件

1. **libvirtd**：
   - Libvirt 的守护进程，负责处理客户端请求和管理虚拟机。通过这个守护进程，可以与不同的虚拟化后端进行交互。
2. **virsh**：
   - Libvirt 的命令行工具，提供了一系列命令用于管理虚拟机和资源。通过 `virsh`，用户可以执行创建、启动、停止、迁移虚拟机等操作。
3. **libvirt API**：
   - 提供 C 语言的库和 API，同时支持多种编程语言的绑定，如 Python、Perl、Ruby、Java、Go 等，使得开发者可以在不同的编程环境中使用 Libvirt 的功能。

## 6.3. virsh命令

```bash
# 列出所有虚拟机
virsh list --all
# 启动虚拟机
virsh start <vm_name>
# 关闭虚拟机
virsh shutdown <vm_name>
# 定义新的虚拟机
virsh define /path/to/vm.xml
# 创建并启动虚拟机
virsh create /path/to/vm.xml
# 迁移虚拟机
virsh migrate --live <vm_name> qemu+ssh://destination_host/system
```



参考：

- https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/virtualization_getting_started_guide/chap-virtualization_getting_started-what_is_it
- https://en.wikipedia.org/wiki/Hypervisor
- https://www.linux-kvm.org/page/Main_Page
- [http://www.linux-kvm.org/page/Documents](http://www.linux-kvm.org/page/Documents)
- https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine
- https://wiki.qemu.org/Index.html

