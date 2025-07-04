---
title: "qemu创建虚拟机"
weight: 3
catalog: true
date: 2024-07-10 10:50:57
subtitle:
header-img: 
tags:
- KubeVirt
catagories:
- KubeVirt
---

# 1. 部署qemu-system-x86_64

```bash
# 更新包
sudo apt-get update

# 安装QEMU和KVM相关的包。KVM（Kernel-based Virtual Machine）可以显著提高QEMU的性能。
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

# 安装qemu-system-x86
sudo apt-get install -y qemu qemu-system-x86

# 为了在非root用户下使用QEMU/KVM，需要将当前用户添加到 libvirt 和 kvm 组。
sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)

# 查看版本
qemu-system-x86_64 --version

# 验证命令
virsh list --all
```

