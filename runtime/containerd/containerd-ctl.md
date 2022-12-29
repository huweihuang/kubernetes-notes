---
title: "Containerd命令工具"
weight: 2
catalog: true
date: 2022-6-23 16:22:24
subtitle:
header-img:
tags:
- Containerd
catagories:
- Containerd
---

# crictl

```bash
#!/bin/bash
CrictlVersion=$1
CrictlVersion=${CrictlVersion:-1.24.2}

echo "--------------install crictl--------------"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CrictlVersion}/crictl-v${CrictlVersion}-linux-amd64.tar.gz
tar Cxzvf /usr/local/bin nerdctl-${NerdctlVersion}-linux-amd64.tar.gz
```

设置配置文件

```bash
cat > /etc/crictl.yaml << \EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF
```





参考：

- [使用 crictl 对 Kubernetes 节点进行调试 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/crictl/)

- https://github.com/kubernetes-sigs/cri-tools/blob/master/docs/crictl.mdCrictlVersion=${CrictlVersion:-1.24.2}
