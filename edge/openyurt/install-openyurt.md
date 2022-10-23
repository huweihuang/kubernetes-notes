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

## 2. 部署 Yurt-controller-manager(cloud)

`yurt-controller-manager`用来避免节点与apiserver失联时，自治边缘节点pod被驱逐。

```bash
wget https://raw.githubusercontent.com/openyurtio/openyurt/master/config/setup/yurt-controller-manager.yaml
kubectl apply -f yurt-controller-manager.yaml
```

> yaml文件位于https://github.com/openyurtio/openyurt/tree/master/config/setup

### 禁用默认的 `nodelifecycle` 控制器

`nodelifecycle`控制器主要用来根据node的status及lease的更新时间来决定是否要`驱逐节点上的pod`。为了让 `yurt-controller-mamanger` 能够正常工作，因此需要禁用controller的驱逐功能。

```bash
vim /etc/kubernetes/manifests/kube-controller-manager.yaml
# 在--controllers=*,bootstrapsigner,tokencleaner后面添加,-nodelifecycle 
# 即参数为： --controllers=*,bootstrapsigner,tokencleaner,-nodelifecycle

# 如果kube-controller-manager是以static pod部署，修改yaml文件后会自动重启。
```

## 3. 部署 Yurthub(edge)

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

## 4. 重置 Kubelet

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

## 5. 部署 Yurt-tunnel (可选)

### 5.1.  部署云端的 yurt-tunnel-server

```bash
wget https://raw.githubusercontent.com/openyurtio/openyurt/master/config/setup/yurt-tunnel-server.yaml
kubectl apply -f yurt-tunnel-server.yaml
```

### 5.2. 部署边缘的yurt-tunnel-agent

```bash
wget https://raw.githubusercontent.com/openyurtio/openyurt/master/config/setup/yurt-tunnel-agent.yaml
kubectl apply -f yurt-tunnel-agent.yaml
```

> 由于yurt-tunnel-server默认使用host模式，因此可能存在边缘端的agent无法访问云端的tunnel-server，需要为tunnel-server配置一个可访问的地址。





参考：

- https://openyurt.io/zh/docs/installation/manually-setup
- https://openyurt.io/zh/docs/installation/openyurt-prepare
