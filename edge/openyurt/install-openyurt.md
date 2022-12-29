---
title: "OpenYurt部署"
weight: 1
catalog: true
date: 2022-08-13 10:50:57
subtitle:
header-img: 
tags:
- OpenYurt
catagories:
- OpenYurt
---

> 本文主要介绍部署openyurt组件到k8s集群中。

## 1. 给云端节点和边缘节点打标签

openyurt将k8s节点分为云端节点和边缘节点，云端节点主要运行一些云端的业务，边缘节点运行边缘业务。当与 `apiserver` 断开连接时，只有运行在边缘自治的节点上的Pod才不会被驱逐。通过打 `openyurt.io/is-edge-worker` 的标签的方式来区分，`false`表示云端节点，`true`表示边缘节点。

云端组件：

- yurt-controller-manager

- yurt-tunnel-server

边缘组件：

- yurt-hub

- yurt-tunnel-agent

### 1.1. openyurt.io/is-edge-worker节点标签

```bash
# 云端节点，值为false
kubectl label node us-west-1.192.168.0.87 openyurt.io/is-edge-worker=false

# 边缘节点，值为true
kubectl label node us-west-1.192.168.0.88 openyurt.io/is-edge-worker=true
```

### 1.2. 给边缘节点开启自治模式

```bash
kubectl annotate node us-west-1.192.168.0.88 node.beta.openyurt.io/autonomy=true
```

## 2. 安装准备

### 2.1. 调整k8s组件的配置

参考[调整k8s组件的配置](https://blog.huweihuang.com/kubernetes-notes/edge/openyurt/update-k8s-for-openyurt/)

### 2.2. 部署tunnel-dns

```bash
wget https://raw.githubusercontent.com/openyurtio/openyurt/master/config/setup/yurt-tunnel-dns.yaml
kubectl apply -f yurt-tunnel-dns.yaml
```

获取clusterIP，作为kube-apiserver的专用nameserver地址。

```bash
kubectl -n kube-system get svc yurt-tunnel-dns -o=jsonpath='{.spec.clusterIP}'
```

## 3. 部署openyurt控制面

通过helm来部署控制面，所有helm charts都可以在[openyurt-helm 仓库](https://github.com/openyurtio/openyurt-helm)中找到。

快捷安装可参考脚本：[helm-install-openyurt.sh](https://github.com/huweihuang/kubeadm-scripts/blob/main/openyurt/cloud/helm-install-openyurt.sh)

```bash
helm repo add openyurt https://openyurtio.github.io/openyurt-helm
```

### 3.1. yurt-app-manager

```bash
helm upgrade --install yurt-app-manager -n kube-system openyurt/yurt-app-manager
```

### 3.2. openyurt

在`openyurt/openyurt`中的组件包括：

- [yurt-controller-manager](https://openyurt.io/zh/docs/core-concepts/yurt-controller-manager): 防止apiserver在断开连接时驱逐运行在边缘节点上的pod
- [yurt-tunnel-server](https://openyurt.io/zh/docs/core-concepts/yurttunnel): 在云端构建云边隧道
- [yurt-tunnel-agent](https://openyurt.io/zh/docs/core-concepts/yurttunnel): 在边缘侧构建云边隧道

由于yurt-tunnel-server默认使用host模式，因此可能存在边缘端的agent无法访问云端的tunnel-server，需要为tunnel-server配置一个可访问的地址。

```bash
# 下载并解压
helm pull openyurt/openyurt --untar

# 修改tunnel相关配置
cd openyurt 
vi values.yaml

# 示例：
yurtTunnelServer:
  replicaCount: 1
  tolerations: []
  parameters:
    certDnsNames: "<tunnel server的域名>"
    tunnelAgentConnectPort: <tunnel server端口，默认为10262>
    certIps: ""


yurtTunnelAgent:
  replicaCount: 1
  tolerations: []
  parameters:
    tunnelserverAddr: "<tunnel server的地址，包括端口>"


# install
helm install openyurt ./openyurt
```

## 4. 部署 Yurthub(edge)

在 `yurt-controller-manager` 启动并正常运行后，以静态 pod 的方式部署 `Yurthub`。

1. 为 yurthub 创建全局配置(即RBAC, configmap)

```bash
wget https://raw.githubusercontent.com/openyurtio/openyurt/master/config/setup/yurthub-cfg.yaml
kubectl apply -f yurthub-cfg.yaml
```

2. 在边缘节点以static pod方式创建yurthub

```bash
mkdir -p /etc/kubernetes/manifests/
cd /etc/kubernetes/manifests/
wget https://raw.githubusercontent.com/openyurtio/openyurt/master/config/setup/yurthub.yaml 

# 获取bootstrap token
kubeadm token create

# 假设 apiserver 的地址是 1.2.3.4:6443，bootstrap token 是 07401b.f395accd246ae52d
sed -i 's|__kubernetes_master_address__|1.2.3.4:6443|;
s|__bootstrap_token__|07401b.f395accd246ae52d|' /etc/kubernetes/manifests/yurthub.yaml
```

## 5. 重置 Kubelet

重置 kubelet 服务，让它通过 yurthub 访问apiserver。为 kubelet 服务创建一个新的 kubeconfig 文件来访问apiserver。

```bash
mkdir -p /var/lib/openyurt
cat << EOF > /var/lib/openyurt/kubelet.conf
apiVersion: v1
clusters:
- cluster:
    server: http://127.0.0.1:10261
  name: default-cluster
contexts:
- context:
    cluster: default-cluster
    namespace: default
    user: default-auth
  name: default-context
current-context: default-context
kind: Config
preferences: {}
EOF
```

修改`/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`

```bash
sed -i "s|KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=\/etc\/kubernetes\/bootstrap-kubelet.conf\ --kubeconfig=\/etc\/kubernetes\/kubelet.conf|KUBELET_KUBECONFIG_ARGS=--kubeconfig=\/var\/lib\/openyurt\/kubelet.conf|g" \
    /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

重启kubelet服务

```bash
systemctl daemon-reload && systemctl restart kubelet
```

## 6. yurthub部署脚本

根据以上部署步骤，整理部署脚本。需要修改脚本内容的`master-addr`和`token`字段。

```bash
#!/bin/bash
set -e
set -x

### install yurthub ###
mkdir -p /etc/kubernetes/manifests/
cd /etc/kubernetes/manifests/
wget https://raw.githubusercontent.com/openyurtio/openyurt/master/config/setup/yurthub.yaml 


### 修改master和token字段
sed -i 's|__kubernetes_master_address__|<master-addr>:6443|;
s|__bootstrap_token__|<token>|' /etc/kubernetes/manifests/yurthub.yaml

mkdir -p /var/lib/openyurt
cat << EOF > /var/lib/openyurt/kubelet.conf
apiVersion: v1
clusters:
- cluster:
    server: http://127.0.0.1:10261
  name: default-cluster
contexts:
- context:
    cluster: default-cluster
    namespace: default
    user: default-auth
  name: default-context
current-context: default-context
kind: Config
preferences: {}
EOF

cp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.bak
sed -i "s|KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=\/etc\/kubernetes\/bootstrap-kubelet.conf\ --kubeconfig=\/etc\/kubernetes\/kubelet.conf|KUBELET_KUBECONFIG_ARGS=--kubeconfig=\/var\/lib\/openyurt\/kubelet.conf|g" \
    /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl daemon-reload && systemctl restart kubelet
```

参考：

- https://openyurt.io/zh/docs/installation/manually-setup
- https://openyurt.io/zh/docs/installation/openyurt-prepare
- [在存量的K8s节点上安装OpenYurt Node组件](https://openyurt.io/zh/docs/installation/yurtadm-join/#2-%E5%9C%A8%E5%AD%98%E9%87%8F%E7%9A%84k8s%E8%8A%82%E7%82%B9%E4%B8%8A%E5%AE%89%E8%A3%85openyurt-node%E7%BB%84%E4%BB%B6)
