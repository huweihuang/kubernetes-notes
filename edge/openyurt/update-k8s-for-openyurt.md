---
title: "OpenYurt 安装相关Kubernetes配置调整"
weight: 2
catalog: true
date: 2022-12-26 10:50:57
subtitle:
header-img: 
tags:
- OpenYurt
catagories:
- OpenYurt
---

安装openyurt，为了适配边缘场景，需要对k8s组件进行调整。其中包括：

- kube-apiserver

- kube-controller-manager

- kube-proxy

- CoreDNS

# 1. kube-apiserver

为了实现云边通信，即用户可以正常使用kubectl exec/logs的功能来登录或查看边缘容器的信息。需要将kube-apiserver访问kubelet的地址调整为hostname优先。

```yaml
$ vi /etc/kubernetes/manifests/kube-apiserver.yaml
apiVersion: v1
kind: Pod
...
spec:
  dnsPolicy: "None" # 1. dnsPolicy修改为None
  dnsConfig:        # 2. 增加dnsConfig配置
    nameservers:
      - 1.2.3.4 # 使用yurt-tunnel-dns service的clusterIP替换
    searches:
      - kube-system.svc.cluster.local
      - svc.cluster.local
      - cluster.local
    options:
      - name: ndots
        value: "5"
  containers:
  - command:
    - kube-apiserver
  ...
    - --kubelet-preferred-address-types=Hostname,InternalIP,ExternalIP # 3. 把Hostname放在第一位
  ...
```

# 2. kube-controller-manager

禁用默认的 `nodelifecycle` 控制器，当节点断连时不驱逐pod。

`nodelifecycle`控制器主要用来根据node的status及lease的更新时间来决定是否要`驱逐节点上的pod`。为了让 `yurt-controller-mamanger` 能够正常工作，因此需要禁用controller的驱逐功能。

```bash
vim /etc/kubernetes/manifests/kube-controller-manager.yaml
# 在--controllers=*,bootstrapsigner,tokencleaner后面添加,-nodelifecycle 
# 即参数为： --controllers=*,bootstrapsigner,tokencleaner,-nodelifecycle

# 如果kube-controller-manager是以static pod部署，修改yaml文件后会自动重启。
```

# 3. CoreDNS

将coredns从deployment部署改为daemonset部署。

将deployment的coredns副本数调整为0。

```bash
kubectl scale --replicas=0 deployment/coredns -n kube-system
```

创建daemonset的coredns。

```bash
wget https://raw.githubusercontent.com/huweihuang/kubeadm-scripts/main/openyurt/yurt-tunnel/coredns.ds.yaml

kubectl apply -f 
```

支持流量拓扑：

```bash
# 利用openyurt实现endpoint过滤
kubectl annotate svc kube-dns -n kube-system openyurt.io/topologyKeys='openyurt.io/nodepool'
```

# 4. kube-proxy

云边端场景下，边缘节点间很有可能无法互通，因此需要endpoints基于nodepool进行拓扑。直接将kube-proxy的kubeconfig配置删除，将apiserver请求经过yurthub即可解决服务拓扑问题。

```bash
kubectl edit cm -n kube-system kube-proxy
```

示例：

```yaml
apiVersion: v1
data:
  config.conf: |-
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    bindAddress: 0.0.0.0
    bindAddressHardFail: false
    clientConnection:
      acceptContentTypes: ""
      burst: 0
      contentType: ""
      #kubeconfig: /var/lib/kube-proxy/kubeconfig.conf <-- 删除这个配置
      qps: 0
    clusterCIDR: 100.64.0.0/10
    configSyncPeriod: 0s
// 省略
```

参考：

- https://openyurt.io/zh/docs/installation/openyurt-prepare/
