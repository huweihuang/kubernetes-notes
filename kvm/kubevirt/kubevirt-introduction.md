> 本文主要由[云原生虚拟化：基于 Kubevirt 构建边缘计算实例](https://mp.weixin.qq.com/s/IwA1QcGaooZAL96YjvTqjA)文章重新整理而成。

# 1. kubevirt简介

kubevirt是基于k8s之上，提供了一种通过k8s来编排和管理虚拟机的方式。

# 2. 架构图

![arch](https://res.cloudinary.com/dqxtn0ick/image/upload/v1650005691/article/kubernetes/kubevirt/architecture.png)

## 2.1. 组件说明

| 分类  | 组件              | 部署方式             | 功能说明                                                         |
| --- | --------------- | ---------------- | ------------------------------------------------------------ |
| 控制面 | virt-api        | deployment       | 自定义API，开机、关机、重启等，作为apiserver的插件，业务通过k8s apiserver请求virt-api。 |
|     | virt-controller | deployment       | 管理和监控VMI对象的状态，控制VMI下的pod。                                    |
| 节点侧 | virt-handler    | daemonset        | 类似kubelet，管理宿主机上的所有虚拟机实例。                                    |
|     | virt-launcher   | virt-handler pod | 调用libvirt和qemu创建虚拟机进程。                                       |

virt-launcher与libvirt逻辑：

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1650271227/article/kubernetes/kubevirt/virt-launcher.jpg)

## 2.2. 自定义CRD对象

| 分类  | CRD对象                       | 功能说明                                |
| --- | --------------------------- | ----------------------------------- |
| 虚机  | VirtualMachineInstance（VMI） | 代表运行的虚拟机实例                          |
|     | VirtualMachine（VM）          | 虚机对象，提供开机、关机、重启，管理VMI实例，与VMI的关系是1：1 |
|     |                             |                                     |

# 3. 创建虚拟机流程

> 待补充



参考：

- https://github.com/kubevirt/kubevirt

- [Architecture - KubeVirt User-Guide](http://kubevirt.io/user-guide/architecture/)

- https://mp.weixin.qq.com/s/IwA1QcGaooZAL96YjvTqjA
