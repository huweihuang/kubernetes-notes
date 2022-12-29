---
title: "使用kind安装kubernetes"
weight: 4
catalog: true
date: 2019-6-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. 安装kind

On mac or linux

```bash
curl -Lo ./kind "https://github.com/kubernetes-sigs/kind/releases/download/v0.7.0/kind-$(uname)-amd64"
chmod +x ./kind
mv ./kind /some-dir-in-your-PATH/kind
```

# 2. 创建k8s集群

```bash
$ kind create cluster
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.17.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Not sure what to do next? 😅 Check out https://kind.sigs.k8s.io/docs/user/quick-start/
```

查看集群信息

```bash
$ kubectl cluster-info --context kind-kind
Kubernetes master is running at https://127.0.0.1:32768
KubeDNS is running at https://127.0.0.1:32768/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

查看node

```bash
$ kubectl get node -o wide
NAME                 STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE       KERNEL-VERSION                      CONTAINER-RUNTIME
kind-control-plane   Ready    master   35h   v1.17.0   172.17.0.2    <none>        Ubuntu 19.10   3.10.107-1-tlinux2_kvm_guest-0049   containerd://1.3.2
```

查看pod

```bash
$ kubectl get po --all-namespaces -o wide
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE   IP           NODE                 NOMINATED NODE   READINESS GATES
kube-system          coredns-6955765f44-lqk9v                     1/1     Running   0          35h   10.244.0.4   kind-control-plane   <none>           <none>
kube-system          coredns-6955765f44-zpsmc                     1/1     Running   0          35h   10.244.0.3   kind-control-plane   <none>           <none>
kube-system          etcd-kind-control-plane                      1/1     Running   0          35h   172.17.0.2   kind-control-plane   <none>           <none>
kube-system          kindnet-8mt7d                                1/1     Running   0          35h   172.17.0.2   kind-control-plane   <none>           <none>
kube-system          kube-apiserver-kind-control-plane            1/1     Running   0          35h   172.17.0.2   kind-control-plane   <none>           <none>
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   0          35h   172.17.0.2   kind-control-plane   <none>           <none>
kube-system          kube-proxy-5w25s                             1/1     Running   0          35h   172.17.0.2   kind-control-plane   <none>           <none>
kube-system          kube-scheduler-kind-control-plane            1/1     Running   0          35h   172.17.0.2   kind-control-plane   <none>           <none>
local-path-storage   local-path-provisioner-7745554f7f-dckzr      1/1     Running   0          35h   10.244.0.2   kind-control-plane   <none>           <none>
```

docker ps

```bash
$ docker ps
CONTAINER ID        IMAGE                  COMMAND                  CREATED             STATUS              PORTS                       NAMES
93b291f99dd4        kindest/node:v1.17.0   "/usr/local/bin/entr…"   2 minutes ago       Up 2 minutes        127.0.0.1:32768->6443/tcp   kind-control-plane
```

# 3. kindest/node容器内进程

```bash
$ docker exec -it 93b291f99dd4 bash
root@kind-control-plane:/# ps auxw
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.1  0.0  19512  7480 ?        Ss   03:18   0:00 /sbin/init
root       105  0.0  0.0  26396  7344 ?        S<s  03:18   0:00 /lib/systemd/systemd-journald
root       141  2.3  0.3 2374736 51564 ?       Ssl  03:18   0:06 /usr/local/bin/containerd
root       325  0.0  0.0 112540  5036 ?        Sl   03:18   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id 3f415d609e15ef12b9f53557891c311c156b912d5a326544a25c8b29cfa9d366 -address /run/containerd/containerd.sock
root       346  0.0  0.0   1012     4 ?        Ss   03:18   0:00 /pause
root       370  0.0  0.0 112540  5108 ?        Sl   03:18   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id 1e1f3eed09f701fb621325e7b9e96d1c3de60ebd3bd64e0aec376e9490cf0e57 -address /run/containerd/containerd.sock
root       397  0.0  0.0 112540  4684 ?        Sl   03:18   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id c5e451089a1a5b3dfb2cc68ee27ac7d414285be55ecfdc5bd59180fbfbc7df2e -address /run/containerd/containerd.sock
root       424  0.0  0.0 112540  4924 ?        Sl   03:18   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id 81e35f29ac8c2dda344125a10e3791be7ccf788a88f1efbc3397fa319f02881f -address /run/containerd/containerd.sock
root       443  0.0  0.0   1012     4 ?        Ss   03:18   0:00 /pause
root       458  0.0  0.0   1012     4 ?        Ss   03:18   0:00 /pause
root       465  0.0  0.0   1012     4 ?        Ss   03:18   0:00 /pause
root       548  0.7  0.1 145500 27724 ?        Ssl  03:18   0:02 kube-scheduler --authentication-kubeconfig=/etc/kubernetes/scheduler.conf --authorization-kubeconfig=/etc/kubernetes/scheduler.conf --bind-address=127.0.0.1 --kubeconfig=/etc/kubernetes/scheduler.conf --leader-elect=true
root       589  1.0  0.3 159536 54384 ?        Ssl  03:18   0:02 kube-controller-manager --allocate-node-cidrs=true --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf --bind-address=127.0.0.1 --client-ca-file=/etc/kubernetes/pki/ca.cr
root       613  3.8  1.6 445780 273484 ?       Ssl  03:18   0:10 kube-apiserver --advertise-address=172.17.0.2 --allow-privileged=true --authorization-mode=Node,RBAC --client-ca-file=/etc/kubernetes/pki/ca.crt --enable-admission-plugins=NodeRestriction --enable-bootstrap-token-auth=true --etcd-cafile=/etc/kubernetes/
root       660  1.4  0.2 10613604 37448 ?      Ssl  03:18   0:04 etcd --advertise-client-urls=https://172.17.0.2:2379 --cert-file=/etc/kubernetes/pki/etcd/server.crt --client-cert-auth=true --data-dir=/var/lib/etcd --initial-advertise-peer-urls=https://172.17.0.2:2380 --initial-cluster=kind-control-plane=https://172.
root       718  1.3  0.3 2084848 52772 ?       Ssl  03:18   0:03 /usr/bin/kubelet --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml --container-runtime=remote --container-runtime-endpoint=/run/containerd/containerd.sock --fail
root       876  0.0  0.0 112540  5084 ?        Sl   03:18   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id adfbea8fec5ac6986407291f5bfc5aecead176954e5dabbe1517b98dd77bf78b -address /run/containerd/containerd.sock
root       893  0.0  0.0 112540  4796 ?        Sl   03:18   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id 53bdce023626b60ffaa0548b5888e457dc9c3bc45c7808a385dd0f63dcc90327 -address /run/containerd/containerd.sock
root       924  0.0  0.0   1012     4 ?        Ss   03:18   0:00 /pause
root       931  0.0  0.0   1012     4 ?        Ss   03:18   0:00 /pause
root      1000  0.0  0.0 127616 11100 ?        Ssl  03:18   0:00 /bin/kindnetd
root      1017  0.0  0.1 141060 19420 ?        Ssl  03:18   0:00 /usr/local/bin/kube-proxy --config=/var/lib/kube-proxy/config.conf --hostname-override=kind-control-plane
root      1066  0.0  0.0      0     0 ?        Z    03:18   0:00 [iptables-nft-sa] <defunct>
root      1080  0.0  0.0      0     0 ?        Z    03:18   0:00 [iptables-nft-sa] <defunct>
root      1241  0.0  0.0 112540  5156 ?        Sl   03:19   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id 5cbd7bbe186cf5847786c7a03aa4c6f82e6c805d0a189f0f3e8fb1750594260d -address /run/containerd/containerd.sock
root      1262  0.0  0.0   1012     4 ?        Ss   03:19   0:00 /pause
root      1303  0.1  0.0 134372 14088 ?        Ssl  03:19   0:00 local-path-provisioner --debug start --helper-image k8s.gcr.io/debian-base:v2.0.0 --config /etc/config/config.json
root      1411  0.0  0.0 112540  4876 ?        Sl   03:19   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id 196b440345cb5ef47a6c31222323d35bbfef85d1d79c149ec0e3a6e22022a5f0 -address /run/containerd/containerd.sock
root      1437  0.0  0.0   1012     4 ?        Ss   03:19   0:00 /pause
root      1450  0.0  0.0 112540  4380 ?        Sl   03:19   0:00 /usr/local/bin/containerd-shim-runc-v2 -namespace k8s.io -id de7bdf052083978c78708383f842567d4fb38adff22a56792437a4de82425afe -address /run/containerd/containerd.sock
root      1480  0.0  0.0   1012     4 ?        Ss   03:19   0:00 /pause
root      1530  0.1  0.1 144324 19056 ?        Ssl  03:19   0:00 /coredns -conf /etc/coredns/Corefile
root      1531  0.1  0.1 144580 19204 ?        Ssl  03:19   0:00 /coredns -conf /etc/coredns/Corefile
```





参考：

- https://github.com/kubernetes-sigs/kind
- https://kind.sigs.k8s.io/docs/user/quick-start/