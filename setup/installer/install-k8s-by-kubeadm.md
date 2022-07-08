> 本文为基于`kubeadm`搭建`生产环境`级别`高可用`的k8s集群。

# 1. 环境准备

## 1.0. master硬件配置

参考：

- [Master节点规格](https://help.aliyun.com/document_detail/98886.html)

- [高可靠推荐配置 - 容器服务 ACK - 阿里云](https://help.aliyun.com/document_detail/94292.html)

Kubernetes集群Master节点上运行着etcd、kube-apiserver、kube-controller等核心组件，对于Kubernetes集群的稳定性有着至关重要的影响，对于生产环境的集群，必须慎重选择Master规格。Master规格跟集群规模有关，集群规模越大，所需要的Master规格也越高。

**说明** ：可从多个角度衡量集群规模，例如节点数量、Pod数量、部署频率、访问量。这里简单的认为集群规模就是集群里的节点数量。

对于常见的集群规模，可以参见如下的方式选择Master节点的规格（对于测试环境，规格可以小一些。下面的选择能尽量保证Master负载维持在一个较低的水平上）。

| 节点规模           | Master规格          | 磁盘         |
| -------------- | ----------------- | ---------- |
| 1~5个节点         | 4核8 GB（不建议2核4 GB） |            |
| 6~20个节点        | 4核16 GB           |            |
| 21~100个节点      | 8核32 GB           |            |
| **100~200个节点** | **16核64 GB**      |            |
| **1000个节点**    | **32核128GB**      | **1T SSD** |

**注意事项：**

- **由于Etcd的性能瓶颈，Etcd的数据存储盘尽量选择SSD磁盘。**

- **为了实现多机房容灾，可将三台master分布在一个可用区下三个不同机房。**（机房之间的网络延迟在10毫秒及以下级别）

- **申请LB来做master节点的负载均衡实现高可用，LB作为apiserver的访问地址。**

## 1.1. 设置防火墙端口策略

生产环境设置k8s节点的iptables端口访问规则。

### 1.1.1. master节点端口配置

| 协议  | 方向  | 端口范围      | 目的                      | 使用者                  |
| --- | --- | --------- | ----------------------- | -------------------- |
| TCP | 入站  | 6443      | Kubernetes API server   | 所有                   |
| TCP | 入站  | 2379-2380 | etcd server client API  | kube-apiserver, etcd |
| TCP | 入站  | 10250     | Kubelet API             | 自身, 控制面              |
| TCP | 入站  | 10259     | kube-scheduler          | 自身                   |
| TCP | 入站  | 10257     | kube-controller-manager | 自身                   |

### 1.1.2. worker节点端口配置

| 协议  | 方向  | 端口范围        | 目的                | 使用者     |
| --- | --- | ----------- | ----------------- | ------- |
| TCP | 入站  | 10250       | Kubelet API       | 自身, 控制面 |
| TCP | 入站  | 30000-32767 | NodePort Services | 所有      |

添加防火墙iptables规则

master节点开放6443、2379、2380端口。

```bash
iptables -A INPUT -p tcp -m multiport --dports 6443,2379,2380,10250 -j ACCEPT
```

## 1.2. 关闭​​swap​​分区

```bash
[root@master ~]#swapoff -a
[root@master ~]#
[root@master ~]# free -m
              total        used        free      shared  buff/cache   available
Mem:            976         366         135           6         474         393
Swap:             0           0           0

# swap 一栏为0，表示已经关闭了swap
```

## 1.3.  开启br_netfilter和bridge-nf-call-iptables

参考：https://imroc.cc/post/202105/why-enable-bridge-nf-call-iptables/

```bash
# 设置加载br_netfilter模块
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 开启bridge-nf-call-iptables ，设置所需的 sysctl 参数，参数在重新启动后保持不变
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 应用 sysctl 参数而不重新启动
sudo sysctl --system
```

# 2. 安装容器运行时

在所有主机上安装容器运行时，`推荐使用containerd为runtime`。以下分别是containerd与docker的安装命令。

## 2.1. Containerd

1、参考：[安装containerd](../runtime/containerd/install-containerd.md)

```bash
# for ubuntu
apt install -y containerd.io
```

2、生成默认配置

```bash
containerd config default > /etc/containerd/config.toml
```

3、修改CgroupDriver为systemd

k8s官方推荐使用systemd类型的CgroupDriver。

```bash
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```

4、重启containerd

```bash
systemctl restart containerd
```

## 2.2. Docker

```bash
# for ubuntu
apt install -y docker.io
```

官方建议配置cgroupdriver为systemd。

```bash
# 修改docker进程管理器
vi /etc/docker/daemon.json
{
"exec-opts": ["native.cgroupdriver=systemd"]
}
systemctl daemon-reload && systemctl restart docker
docker info | grep -i cgroup
```

## 2.3. Container Socket

| 运行时                            | Unix 域套接字                                    |
| ------------------------------ | -------------------------------------------- |
| Containerd                     | `unix:///var/run/containerd/containerd.sock` |
| CRI-O                          | `unix:///var/run/crio/crio.sock`             |
| Docker Engine (使用 cri-dockerd) | `unix:///var/run/cri-dockerd.sock`           |

# 3. 安装kubeadm,kubelet,kubectl

在所有主机上安装kubeadm，kubelet，kubectl。最好版本与需要安装的k8s的版本一致。

```bash
# 以Ubuntu系统为例

# 安装仓库依赖
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

# use google registry
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# or use aliyun registry
curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
tee /etc/apt/sources.list.d/kubernetes.list <<EOF 
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF

# 安装指定版本的kubeadm, kubelet, kubectl
apt-get update
apt-get install -y kubelet=1.24.2-00 kubeadm=1.24.2-00 kubectl=1.24.2-00

# 查询有哪些版本
apt-cache madison kubeadm
```

# 4. 配置kubeadm config

参考：

- [kubeadm Configuration (v1beta3) | Kubernetes](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/)
- [kubeadm Configuration (v1beta2) | Kubernetes](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta2/)

## 4.1. 配置项说明

### 4.1.1. 配置类型

kubeadm config支持以下几类配置。

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration

apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration

apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration

apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration

apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
```

可以使用以下命令打印init和join的默认配置。

```bash
kubeadm config print init-defaults
kubeadm config print join-defaults
```

### 4.1.2. Init配置

kubeadm init配置中只有`InitConfiguration` 和 `ClusterConfiguration` 是必须的。

**InitConfiguration:**

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
  ...
nodeRegistration:
  ...
```

- bootstrapTokens
- nodeRegistration
  - criSocket：runtime的socket
  - name：节点名称
- localAPIEndpoint
  - advertiseAddress：apiserver的广播IP
  - bindPort：k8s控制面安全端口

**ClusterConfiguration:**

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  ...
etcd:
  ...
apiServer:
  extraArgs:
    ...
  extraVolumes:
    ...
...
```

- networking:
  
  - podSubnet：Pod CIDR范围
  - serviceSubnet： service CIDR范围
  - dnsDomain

- etcd:
  
  - dataDir：Etcd的数据存储目录

- apiserver
  
  - certSANs：设置额外的apiserver的域名签名证书

- imageRepository：镜像仓库

- controlPlaneEndpoint：控制面LB的域名

- kubernetesVersion：k8s版本

## 4.2. Init配置示例

在master节点生成默认配置，并修改配置参数。

```bash
kubeadm config print init-defaults > kubeadm-config.yaml
```

修改配置内容

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 1.2.3.4 # 修改为apiserver的IP 或者去掉localAPIEndpoint则会读取默认IP。
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  name: node
  taints: null
---
apiServer:
  certSANs:
  - lb.k8s.domain  # 添加额外的apiserver的域名
  - <vip/lb_ip>
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}   # 默认为coredns
etcd:
  local:
    dataDir: /data/etcd   # 修改etcd的存储盘目录
imageRepository: k8s.gcr.io  # 修改镜像仓库地址
controlPlaneEndpoint: lb.k8s.domain  # 修改控制面域名
kind: ClusterConfiguration
kubernetesVersion: 1.24.0  # k8s 版本
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
  podSubnet: 10.244.0.0/16  # 设置pod的IP范围
scheduler: {}
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd   # 设置为systemd
```

安装完成后可以查看kubeadm config

```bash
kubectl get cm -n kube-system kubeadm-config -oyaml
```

# 5. 安装Master控制面

提前拉取镜像：

```bash
kubeadm config images pull
```

## 5.1. 安装master

```bash
sudo kubeadm init --config kubeadm-config.yaml --upload-certs  --node-name <nodename>
```

部署参数说明：

- --control-plane-endpoint：指定控制面(kube-apiserver)的IP或DNS域名地址。

- --apiserver-advertise-address：kube-apiserver的IP地址。

- --pod-network-cidr：pod network范围，控制面会自动给每个节点分配CIDR。

- --service-cidr：service的IP范围，default "10.96.0.0/12"。

- --kubernetes-version：指定k8s的版本。

- --image-repository：指定k8s镜像仓库地址。

- --upload-certs ：标志用来将在所有控制平面实例之间的共享证书上传到集群。

- --node-name：hostname-override，作为节点名称。

执行完毕会输出添加master和添加worker的命令如下：

```bash
...
You can now join any number of control-plane node by running the following command on each as a root:
    kubeadm join 192.168.0.200:6443 --token 9vr73a.a8uxyaju799qwdjv --discovery-token-ca-cert-hash sha256:7c2e69131a36ae2a042a339b33381c6d0d43887e2de83720eff5359e26aec866 --control-plane --certificate-key f8902e114ef118304e561c3ecd4d0b543adc226b7a07f675f56564185ffe0c07

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use kubeadm init phase upload-certs to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:
    kubeadm join 192.168.0.200:6443 --token 9vr73a.a8uxyaju799qwdjv --discovery-token-ca-cert-hash sha256:7c2e69131a36ae2a042a339b33381c6d0d43887e2de83720eff5359e26aec866
```

## 5.2. 添加其他master

添加`master`和添加`worker`的差别在于添加`master`多了`--control-plane` 参数来表示添加类型为`master`。

```bash
kubeadm join <control-plane-endpoint>:6443 --token <token> \
--discovery-token-ca-cert-hash sha256:<hash> \
--control-plane --certificate-key <certificate-key> \
--node-name <nodename>
```

# 6. 添加Node节点

```bash
kubeadm join <control-plane-endpoint>:6443 --token <token> \
--discovery-token-ca-cert-hash sha256:<hash> \
--cri-socket /run/containerd/containerd.sock \
--node-name <nodename>
```

# 7. 安装网络插件

```bash
## 如果安装之后node的状态都改为ready，即为成功
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f ./kube-flannel.yml
kubectl get nodes
```

如果Pod CIDR的网段不是`10.244.0.0/16`，则需要加flannel配置中的网段更改为与Pod CIDR的网段一致。

## 7.1. 问题

```bash
  Warning  FailedCreatePodSandBox  4m6s                kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "300d9b570cc1e23b6335c407b8e7d0ef2c74dc2fe5d7a110678c2dc919c62edf": plugin type="flannel" failed (add): failed to delegate add: failed to set bridge addr: "cni0" already has an IP address different from 10.244.3.1/24
```

**原因：**

宿主机节点有`cni0`网卡，且网卡的IP段与flannel的CIDR网段不同，因此需要删除该网卡，让其重建。

**解决：**

```bash
ifconfig cni0 down    
ip link delete cni0
```

# 8. 重置部署

```bash
# kubeadm重置
kubeadm reset

# 清空数据目录
rm -fr /data/etcd
rm -fr /etc/kubernetes
rm -fr ~/.kube/
```

删除flannel

```bash
ifconfig cni0 down
ip link delete cni0
ifconfig flannel.1 down
ip link delete flannel.1
rm -rf /var/lib/cni/
rm -f /etc/cni/net.d/*
```

# 9. 问题排查

## 9.1. kubeadm token过期

问题描述:

添加节点时报以下错误：

```bash
[discovery] The cluster-info ConfigMap does not yet contain a JWS signature for token ID "abcdef", will try again
```

原因：token过期，初始化token后会在24小时候会被master删除。

解决办法：

```bash
# 重新生成token
kubeadm token create --print-join-command
kubeadm token list

# kubeadm token create
oumnnc.aqlxuvdbntlvzoiv

# 重新生成hash
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
```

基于新生成的token重新添加节点。

## 9.2. 修改kubeadm join的master IP或端口

`kubeadm join`命令会去`kube-public`命名空间获取名为`cluster-info`的`ConfigMap`。如果需要修改kubeadm join使用的master的IP或端口，则需要修改cluster-info的configmap。

```bash
# 查看cluster-info
kubectl -n kube-public get configmaps cluster-info -o yaml

# 修改cluster-info
kubectl -n kube-public edit configmaps cluster-info
```

修改配置文件中的`server`字段

```yaml
clusters:
- cluster:
    certificate-authority-data: xxx
    server: https://lb.k8s.domain:36443
  name: ""
```

执行kubeadm join的命令时指定新修改的master地址。

参考：

- [利用 kubeadm 创建高可用集群 | Kubernetes](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [使用 kubeadm 创建集群 | Kubernetes](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [高可用拓扑选项 | Kubernetes](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/ha-topology/)
- [kubeadm init | Kubernetes](https://kubernetes.io/zh-cn/docs/reference/setup-tools/kubeadm/kubeadm-init/#custom-images)
- [v1.24.2|kubeadm|v1beta3](https://pkg.go.dev/k8s.io/kubernetes@v1.24.2/cmd/kubeadm/app/apis/kubeadm/v1beta3)
- [Installing kubeadm | Kubernetes](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Ports and Protocols | Kubernetes](https://kubernetes.io/docs/reference/ports-and-protocols/)
- [容器运行时 | Kubernetes](https://kubernetes.io/zh-cn/docs/setup/production-environment/container-runtimes/)
- https://github.com/Mirantis/cri-dockerd
- [配置 cgroup 驱动|Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/configure-cgroup-driver/)
- [GitHub: flannel is a network fabric for containers](https://github.com/flannel-io/flannel)
