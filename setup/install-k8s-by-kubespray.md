---
title: "[Kubernetes] 使用kubespray安装k8s集群"
catalog: true
date: 2018-6-23 21:26:24
type: "tags"
subtitle:
header-img: "http://ozilwgpje.bkt.clouddn.com/scenery/building.jpg?imageslim"
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. 环境准备

### 1.1. 部署机器

> 以下机器为虚拟机

| 机器IP        | 主机名        | 角色       | 系统版本       | 备注     |
| ------------- | ------------- | ---------- | -------------- | -------- |
| 172.16.94.140 | kube-master-0 | k8s master | Centos 4.17.14 | 内存：3G |
| 172.16.94.141 | kube-node-41  | k8s node   | Centos 4.17.14 | 内存：3G |
| 172.16.94.142 | kube-node-42  | k8s node   | Centos 4.17.14 | 内存：3G |
| 172.16.94.135 |               | 部署管理机 |                |          |

### 1.2. 配置管理机

管理机主要用来部署k8s集群，需要安装以下版本的软件，具体可参考：

- https://github.com/kubernetes-incubator/kubespray#requirements

- https://github.com/kubernetes-incubator/kubespray/blob/master/requirements.txt

```shell
ansible>=2.4.0
jinja2>=2.9.6
netaddr
pbr>=1.6
ansible-modules-hashivault>=3.9.4
hvac
```

**1、安装及配置ansible**

- 参考[ansible的使用](https://blog.csdn.net/huwh_/article/details/81215579)。
- 给部署机器配置SSH的免密登录权限，具体参考[ssh免密登录](https://blog.csdn.net/huwh_/article/details/78006127)。

**2、安装python-netaddr**

```shell
# 安装pip
yum -y install epel-release
yum -y install python-pip
# 安装python-netaddr
pip install netaddr
```

**3、升级Jinja**

```shell
# Jinja 2.9 (or newer)
pip install --upgrade jinja2
```

### 1.3. 配置部署机器

部署机器即用来运行k8s集群的机器，包括`Master`和`Node`。

**1、确认系统版本**

本文采用`centos7`的系统，建议将系统内核升级到`4.x.x`以上。

**2、关闭防火墙**

```shell
systemctl stop firewalld
systemctl disable firewalld
iptables -F
```

**3、关闭swap**

Kubespary `v2.5.0`的版本需要关闭swap，具体参考

- https://github.com/kubernetes-incubator/kubespray/blob/02cd5418c22d51e40261775908d55bc562206023/roles/kubernetes/preinstall/tasks/verify-settings.yml#L75

```yaml
- name: Stop if swap enabled
  assert:
    that: ansible_swaptotal_mb == 0
  when: kubelet_fail_swap_on|default(true)
  ignore_errors: "{{ ignore_assert_errors }}"
```

>`V2.6.0` 版本去除了swap的检查，具体参考：
>
>- https://github.com/kubernetes-incubator/kubespray/commit/b902602d161f8c147f3d155d2ac5360244577127#diff-b92ae64dd18d34a96fbeb7f7e48a6a9b

执行关闭swap命令`swapoff -a`。

```shell
[root@master ~]#swapoff -a
[root@master ~]#
[root@master ~]# free -m
              total        used        free      shared  buff/cache   available
Mem:            976         366         135           6         474         393
Swap:             0           0           0

# swap 一栏为0，表示已经关闭了swap
```

**4、确认部署机器内存**

由于本文采用虚拟机部署，内存可能存在不足的问题，因此将虚拟机内存调整为3G或以上；如果是物理机一般不会有内存不足的问题。具体参考：

- https://github.com/kubernetes-incubator/kubespray/blob/95f1e4634a1c50fa77312d058a2b713353f4307e/roles/kubernetes/preinstall/tasks/verify-settings.yml#L52

```yaml
- name: Stop if memory is too small for masters
  assert:
    that: ansible_memtotal_mb >= 1500
  ignore_errors: "{{ ignore_assert_errors }}"
  when: inventory_hostname in groups['kube-master']

- name: Stop if memory is too small for nodes
  assert:
    that: ansible_memtotal_mb >= 1024
  ignore_errors: "{{ ignore_assert_errors }}"
  when: inventory_hostname in groups['kube-node']
```

### 1.4. 涉及镜像

`Docker`版本为`17.03.2-ce`。

**1、Master节点**

| 镜像                                 | 版本    | 大小    | 镜像ID       | 备注   |
| ------------------------------------ | ------- | ------- | ------------ | ------ |
| gcr.io/google-containers/hyperkube   | v1.9.5  | 620 MB  | a7e7fdbc5fee | k8s    |
| quay.io/coreos/etcd                  | v3.2.4  | 35.7 MB | 498ffffcfd05 |        |
| gcr.io/google_containers/pause-amd64 | 3.0     | 747 kB  | 99e59f495ffa |        |
| quay.io/calico/node                  | v2.6.8  | 282 MB  | e96a297310fd | calico |
| quay.io/calico/cni                   | v1.11.4 | 70.8 MB | 4c4cb67d7a88 | calico |
| quay.io/calico/ctl                   | v1.6.3  | 44.4 MB | 46d3aace8bc6 | calico |

**2、Node节点**

| 镜像                                                         | 版本    | 大小    | 镜像ID       | 备注      |
| ------------------------------------------------------------ | ------- | ------- | ------------ | --------- |
| gcr.io/google-containers/hyperkube                           | v1.9.5  | 620 MB  | a7e7fdbc5fee | k8s       |
| gcr.io/google_containers/pause-amd64                         | 3.0     | 747 kB  | 99e59f495ffa |           |
| quay.io/calico/node                                          | v2.6.8  | 282 MB  | e96a297310fd | calico    |
| quay.io/calico/cni                                           | v1.11.4 | 70.8 MB | 4c4cb67d7a88 | calico    |
| quay.io/calico/ctl                                           | v1.6.3  | 44.4 MB | 46d3aace8bc6 | calico    |
| gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64         | 1.14.8  | 40.9 MB | c2ce1ffb51ed | dns       |
| gcr.io/google_containers/k8s-dns-sidecar-amd64               | 1.14.8  | 42.2 MB | 6f7f2dc7fab5 | dns       |
| gcr.io/google_containers/k8s-dns-kube-dns-amd64              | 1.14.8  | 50.5 MB | 80cc5ea4b547 | dns       |
| gcr.io/google_containers/cluster-proportional-autoscaler-amd64 | 1.1.2   | 50.5 MB | 78cf3f492e6b |           |
| gcr.io/google_containers/kubernetes-dashboard-amd64          | v1.8.3  | 102 MB  | 0c60bcf89900 | dashboard |
| nginx                                                        | 1.13    | 109 MB  | ae513a47849c |           |

**3、说明**

- 镜像被墙并且全部镜像下载需要较多时间，建议提前下载到部署机器上。
- hyperkube镜像主要用来运行k8s核心组件（例如kube-apiserver等）。
- 此处使用的网络组件为calico。

## 2. 部署集群

### 2.1. 下载kubespary的源码

```shell
git clone https://github.com/kubernetes-incubator/kubespray.git
```

### 2.2. 编辑配置文件

#### 2.2.1. hosts.ini

`hosts.ini`主要为部署节点机器信息的文件，路径为：`kubespray/inventory/sample/hosts.ini`。

```shell
cd kubespray
# 复制一份配置进行修改
cp -rfp inventory/sample inventory/k8s
vi inventory/k8s/hosts.ini
```

例如：

> hosts.ini文件可以填写部署机器的登录密码，也可以不填密码而设置ssh的免密登录。

```shell
## Configure 'ip' variable to bind kubernetes services on a
## different ip than the default iface
## 主机名             ssh登陆IP                        ssh用户名               ssh登陆密码                 机器IP          子网掩码
kube-master-0     ansible_ssh_host=172.16.94.140   ansible_ssh_user=root   ansible_ssh_pass=123  ip=172.16.94.140   mask=/24
kube-node-41      ansible_ssh_host=172.16.94.141   ansible_ssh_user=root   ansible_ssh_pass=123  ip=172.16.94.141   mask=/24
kube-node-42      ansible_ssh_host=172.16.94.142   ansible_ssh_user=root   ansible_ssh_pass=123  ip=172.16.94.142   mask=/24

## configure a bastion host if your nodes are not directly reachable
# bastion ansible_ssh_host=x.x.x.x

[kube-master]
kube-master-0

[etcd]
kube-master-0

[kube-node]
kube-node-41
kube-node-42

[k8s-cluster:children]
kube-node
kube-master

[calico-rr]
```

#### 2.2.2. k8s-cluster.yml

`k8s-cluster.yml`主要为k8s集群的配置文件，路径为：`kubespray/inventory/k8s/group_vars/k8s-cluster.yml`。该文件可以修改安装的k8s集群的版本，参数为：kube_version: v1.9.5。具体可参考：

- https://github.com/kubernetes-incubator/kubespray/blob/master/inventory/sample/group_vars/k8s-cluster.yml#L22

### 2.3. 执行部署操作

```shell
# 进入主目录
cd kubespray
# 执行部署命令
ansible-playbook -i inventory/k8s/hosts.ini cluster.yml -b -vvv
```

> -vvv 参数表示输出运行日志

如果需要`重置`可以执行以下命令：

```shell
ansible-playbook -i inventory/k8s/hosts.ini reset.yml -b -vvv
```

## 3. 确认部署结果

### 3.1. ansible的部署结果

ansible命令执行完，出现以下日志，则说明部署成功，否则根据报错内容进行修改。

```shell
PLAY RECAP *****************************************************************************
kube-master-0              : ok=309  changed=30   unreachable=0    failed=0
kube-node-41               : ok=203  changed=8    unreachable=0    failed=0
kube-node-42               : ok=203  changed=8    unreachable=0    failed=0
localhost                  : ok=2    changed=0    unreachable=0    failed=0
```

以下为部分部署执行日志：

```shell
kubernetes/preinstall : Update package management cache (YUM) --------------------23.96s
/root/gopath/src/kubespray/roles/kubernetes/preinstall/tasks/main.yml:121 
kubernetes/master : Master | wait for the apiserver to be running ----------------23.44s
/root/gopath/src/kubespray/roles/kubernetes/master/handlers/main.yml:79 
kubernetes/preinstall : Install packages requirements ----------------------------20.20s
/root/gopath/src/kubespray/roles/kubernetes/preinstall/tasks/main.yml:203 
kubernetes/secrets : Check certs | check if a cert already exists on node --------13.94s
/root/gopath/src/kubespray/roles/kubernetes/secrets/tasks/check-certs.yml:17 
gather facts from all instances --------------------------------------------------9.98s
/root/gopath/src/kubespray/cluster.yml:25 
kubernetes/node : install | Compare host kubelet with hyperkube container --------9.66s
/root/gopath/src/kubespray/roles/kubernetes/node/tasks/install_host.yml:2 
kubernetes-apps/ansible : Kubernetes Apps | Start Resources -----------------------9.27s
/root/gopath/src/kubespray/roles/kubernetes-apps/ansible/tasks/main.yml:37 
kubernetes-apps/ansible : Kubernetes Apps | Lay Down KubeDNS Template ------------8.47s
/root/gopath/src/kubespray/roles/kubernetes-apps/ansible/tasks/kubedns.yml:3
download : Sync container ---------------------------------------------------------8.23s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:15 
kubernetes-apps/network_plugin/calico : Start Calico resources --------------------7.82s
/root/gopath/src/kubespray/roles/kubernetes-apps/network_plugin/calico/tasks/main.yml:2 
download : Download items ---------------------------------------------------------7.67s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:6 
download : Download items ---------------------------------------------------------7.48s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:6 
download : Sync container ---------------------------------------------------------7.35s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:15 
download : Download items ---------------------------------------------------------7.16s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:6 
network_plugin/calico : Calico | Copy cni plugins from calico/cni container -------7.10s
/root/gopath/src/kubespray/roles/network_plugin/calico/tasks/main.yml:62 
download : Download items ---------------------------------------------------------7.04s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:6
download : Download items ---------------------------------------------------------7.01s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:6 
download : Sync container ---------------------------------------------------------7.00s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:15 
download : Download items ---------------------------------------------------------6.98s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:6 
download : Download items ---------------------------------------------------------6.79s
/root/gopath/src/kubespray/roles/download/tasks/main.yml:6 
```

### 3.2. k8s集群运行结果

**1、k8s组件信息**

```shell
# kubectl get all --namespace=kube-system
NAME             DESIRED   CURRENT   READY     UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
ds/calico-node   3         3         3         3            3           <none>          2h

NAME                          DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/kube-dns               2         2         2            2           2h
deploy/kubedns-autoscaler     1         1         1            1           2h
deploy/kubernetes-dashboard   1         1         1            1           2h

NAME                                 DESIRED   CURRENT   READY     AGE
rs/kube-dns-79d99cdcd5               2         2         2         2h
rs/kubedns-autoscaler-5564b5585f     1         1         1         2h
rs/kubernetes-dashboard-69cb58d748   1         1         1         2h

NAME             DESIRED   CURRENT   READY     UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
ds/calico-node   3         3         3         3            3           <none>          2h

NAME                          DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/kube-dns               2         2         2            2           2h
deploy/kubedns-autoscaler     1         1         1            1           2h
deploy/kubernetes-dashboard   1         1         1            1           2h

NAME                                 DESIRED   CURRENT   READY     AGE
rs/kube-dns-79d99cdcd5               2         2         2         2h
rs/kubedns-autoscaler-5564b5585f     1         1         1         2h
rs/kubernetes-dashboard-69cb58d748   1         1         1         2h

NAME                                       READY     STATUS    RESTARTS   AGE
po/calico-node-22vsg                       1/1       Running   0          2h
po/calico-node-t7zgw                       1/1       Running   0          2h
po/calico-node-zqnx8                       1/1       Running   0          2h
po/kube-apiserver-kube-master-0            1/1       Running   0          22h
po/kube-controller-manager-kube-master-0   1/1       Running   0          2h
po/kube-dns-79d99cdcd5-f2t6t               3/3       Running   0          2h
po/kube-dns-79d99cdcd5-gw944               3/3       Running   0          2h
po/kube-proxy-kube-master-0                1/1       Running   2          22h
po/kube-proxy-kube-node-41                 1/1       Running   3          22h
po/kube-proxy-kube-node-42                 1/1       Running   3          22h
po/kube-scheduler-kube-master-0            1/1       Running   0          2h
po/kubedns-autoscaler-5564b5585f-lt9bb     1/1       Running   0          2h
po/kubernetes-dashboard-69cb58d748-wmb9x   1/1       Running   0          2h
po/nginx-proxy-kube-node-41                1/1       Running   3          22h
po/nginx-proxy-kube-node-42                1/1       Running   3          22h

NAME                       TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)         AGE
svc/kube-dns               ClusterIP   10.233.0.3     <none>        53/UDP,53/TCP   2h
svc/kubernetes-dashboard   ClusterIP   10.233.27.24   <none>        443/TCP         2h
```

**2、k8s节点信息**

```shell
# kubectl get nodes
NAME            STATUS    ROLES     AGE       VERSION
kube-master-0   Ready     master    22h       v1.9.5
kube-node-41    Ready     node      22h       v1.9.5
kube-node-42    Ready     node      22h       v1.9.5
```

**3、组件健康信息**

```shell
# kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health": "true"}
```

## 4. troubles shooting

在使用kubespary部署k8s集群时，主要遇到以下报错。

### 4.1. python-netaddr未安装

- 报错内容：

```shell
fatal: [node1]: FAILED! => {"failed": true, "msg": "The ipaddr filter requires python-netaddr be installed on the ansible controller"}
```

- 解决方法：

需要安装 python-netaddr，具体参考上述[环境准备]内容。

### 4.2. swap未关闭

- 报错内容：

```shell
fatal: [kube-master-0]: FAILED! => {
    "assertion": "ansible_swaptotal_mb == 0",
    "changed": false,
    "evaluated_to": false
}
fatal: [kube-node-41]: FAILED! => {
    "assertion": "ansible_swaptotal_mb == 0",
    "changed": false,
    "evaluated_to": false
}
fatal: [kube-node-42]: FAILED! => {
    "assertion": "ansible_swaptotal_mb == 0",
    "changed": false,
    "evaluated_to": false
}
```

- 解决方法：

所有部署机器执行`swapoff -a`关闭swap，具体参考上述[环境准备]内容。

### 4.3. 部署机器内存过小

- 报错内容：

```shell
TASK [kubernetes/preinstall : Stop if memory is too small for masters] *********************************************************************************************************************************************************************************************************
task path: /root/gopath/src/kubespray/roles/kubernetes/preinstall/tasks/verify-settings.yml:52
Friday 10 August 2018  21:50:26 +0800 (0:00:00.940)       0:01:14.088 *********
fatal: [kube-master-0]: FAILED! => {
    "assertion": "ansible_memtotal_mb >= 1500",
    "changed": false,
    "evaluated_to": false
}

TASK [kubernetes/preinstall : Stop if memory is too small for nodes] ***********************************************************************************************************************************************************************************************************
task path: /root/gopath/src/kubespray/roles/kubernetes/preinstall/tasks/verify-settings.yml:58
Friday 10 August 2018  21:50:27 +0800 (0:00:00.570)       0:01:14.659 *********
fatal: [kube-node-41]: FAILED! => {
    "assertion": "ansible_memtotal_mb >= 1024",
    "changed": false,
    "evaluated_to": false
}
fatal: [kube-node-42]: FAILED! => {
    "assertion": "ansible_memtotal_mb >= 1024",
    "changed": false,
    "evaluated_to": false
}
	to retry, use: --limit @/root/gopath/src/kubespray/cluster.retry
```

- 解决方法：

调大所有部署机器的内存，本示例中调整为3G或以上。

### 4.4. kube-scheduler组件运行失败

kube-scheduler组件运行失败，导致http://localhost:10251/healthz调用失败。

- 报错内容：

```shell
FAILED - RETRYING: Master | wait for kube-scheduler (1 retries left).
FAILED - RETRYING: Master | wait for kube-scheduler (1 retries left).
fatal: [node1]: FAILED! => {"attempts": 60, "changed": false, "content": "", "failed": true, "msg": "Status code was not [200]: Request failed: <urlopen error [Errno 111] Connection refused>", "redirected": false, "status": -1, "url": "http://localhost:10251/healthz"}
```

- 解决方法：

可能是内存不足导致，本示例中调大了部署机器的内存。

### 4.5. docker安装包冲突

- 报错内容：

```shell
failed: [k8s-node-1] (item={u'name': u'docker-engine-1.13.1-1.el7.centos'}) => {
    "attempts": 4,
    "changed": false,
    ...
    "item": {
        "name": "docker-engine-1.13.1-1.el7.centos"
    },
    "msg": "Error: docker-ce-selinux conflicts with 2:container-selinux-2.66-1.el7.noarch\n",
    "rc": 1,
    "results": [
        "Loaded plugins: fastestmirror\nLoading mirror speeds from cached hostfile\n * elrepo: mirrors.tuna.tsinghua.edu.cn\n * epel: mirrors.tongji.edu.cn\nPackage docker-engine is obsoleted by docker-ce, trying to install docker-ce-17.03.2.ce-1.el7.centos.x86_64 instead\nResolving Dependencies\n--> Running transaction check\n---> Package docker-ce.x86_64 0:17.03.2.ce-1.el7.centos will be installed\n--> Processing Dependency: docker-ce-selinux >= 17.03.2.ce-1.el7.centos for package: docker-ce-17.03.2.ce-1.el7.centos.x86_64\n--> Processing Dependency: libltdl.so.7()(64bit) for package: docker-ce-17.03.2.ce-1.el7.centos.x86_64\n--> Running transaction check\n---> Package docker-ce-selinux.noarch 0:17.03.2.ce-1.el7.centos will be installed\n---> Package libtool-ltdl.x86_64 0:2.4.2-22.el7_3 will be installed\n--> Processing Conflict: docker-ce-selinux-17.03.2.ce-1.el7.centos.noarch conflicts docker-selinux\n--> Restarting Dependency Resolution with new changes.\n--> Running transaction check\n---> Package container-selinux.noarch 2:2.55-1.el7 will be updated\n---> Package container-selinux.noarch 2:2.66-1.el7 will be an update\n--> Processing Conflict: docker-ce-selinux-17.03.2.ce-1.el7.centos.noarch conflicts docker-selinux\n--> Finished Dependency Resolution\n You could try using --skip-broken to work around the problem\n You could try running: rpm -Va --nofiles --nodigest\n"
    ]
}
```

- 解决方法：

卸载旧的docker版本，由kubespary自动安装。

```shell
sudo yum remove -y docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-selinux \
                  docker-engine-selinux \
                  docker-engine
```



参考文章：

- https://github.com/kubernetes-incubator/kubespray