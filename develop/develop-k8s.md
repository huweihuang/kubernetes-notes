---
title: "k8s社区开发指南"
weight: 4
catalog: true
date: 2023-03-02 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. 社区说明

## 1.1. Community membership

| Role             | Responsibilities                              | Requirements                                                                     | Defined by                                                                                                                                                                                           |
| ---------------- | --------------------------------------------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Member           | Active contributor in the community           | Sponsored by 2 reviewers and multiple contributions to the project               | Kubernetes GitHub org member                                                                                                                                                                         |
| Reviewer         | Review contributions from other members       | History of review and authorship in a subproject                                 | [OWNERS](https://github.com/kubernetes/community/blob/master/contributors/guide/owners.md) file reviewer entry                                                                                       |
| Approver         | Contributions acceptance approval             | Highly experienced active reviewer and contributor to a subproject               | [OWNERS](https://github.com/kubernetes/community/blob/master/contributors/guide/owners.md) file approver entry                                                                                       |
| Subproject owner | Set direction and priorities for a subproject | Demonstrated responsibility and excellent technical judgement for the subproject | [sigs.yaml](https://github.com/kubernetes/community/blob/master/sigs.yaml) subproject [OWNERS](https://github.com/kubernetes/community/blob/master/contributors/guide/owners.md) file *owners* entry |

## 1.2. 社区活动日历

[Community Calendar | Kubernetes Contributors](https://www.kubernetes.dev/resources/calendar/)

## 1.3. 加入k8s slack

点击 https://communityinviter.com/apps/kubernetes/community

## 1.4. 特别兴趣小组（SIG）

列表： https://github.com/kubernetes/community/blob/master/sig-list.md

# 2. 编译k8s仓库

参考：

- [Building Kubernetes](https://github.com/kubernetes/kubernetes/blob/2c6c4566eff972d6c1320b5f8ad795f88c822d09/build/README.md)
- https://github.com/kubernetes/community/blob/master/contributors/devel/development.md#building-kubernetes

## 2.1. 编译二进制

### 2.1.1. 基于docker构建容器编译。

> 该方式为官方镜像及二进制文件的构建方式。

构建镜像(大小：5.97GB)为： kube-build:build-8faa8d3cb7-5-v1.27.0-go1.20.6-bullseye.0

```bash
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes
build/run.sh make # 构建全部

#指定模块构建
build/run.sh make kubeadm
```

输出如下：

```bash
# build/run.sh make
+++ [0804 18:39:11] Verifying Prerequisites....
+++ [0804 18:39:16] Building Docker image kube-build:build-8faa8d3cb7-5-v1.27.0-go1.20.6-bullseye.0
+++ [0804 18:40:49] Creating data container kube-build-data-8faa8d3cb7-5-v1.27.0-go1.20.6-bullseye.0
+++ [0804 18:40:50] Syncing sources to container
+++ [0804 18:40:58] Output from this container will be rsynced out upon completion. Set KUBE_RUN_COPY_OUTPUT=n to disable.
+++ [0804 18:40:58] Running build command...
go: downloading go.uber.org/automaxprocs v1.5.2
+++ [0804 18:41:04] Setting GOMAXPROCS: 8
Go version: go version go1.20.6 linux/amd64
+++ [0804 18:41:04] Building go targets for linux/amd64
    k8s.io/kubernetes/cmd/kube-proxy (static)
    k8s.io/kubernetes/cmd/kube-apiserver (static)
    k8s.io/kubernetes/cmd/kube-controller-manager (static)
    k8s.io/kubernetes/cmd/kubelet (non-static)
    k8s.io/kubernetes/cmd/kubeadm (static)
    k8s.io/kubernetes/cmd/kube-scheduler (static)
    k8s.io/component-base/logs/kube-log-runner (static)
    k8s.io/kube-aggregator (static)
    k8s.io/apiextensions-apiserver (static)
    k8s.io/kubernetes/cluster/gce/gci/mounter (non-static)
    k8s.io/kubernetes/cmd/kubectl (static)
    k8s.io/kubernetes/cmd/kubectl-convert (static)
    github.com/onsi/ginkgo/v2/ginkgo (non-static)
    k8s.io/kubernetes/test/e2e/e2e.test (test)
    k8s.io/kubernetes/test/conformance/image/go-runner (non-static)
    k8s.io/kubernetes/cmd/kubemark (static)
    github.com/onsi/ginkgo/v2/ginkgo (non-static)
    k8s.io/kubernetes/test/e2e_node/e2e_node.test (test)
Env for linux/amd64: GOOS=linux GOARCH=amd64 GOROOT=/usr/local/go CGO_ENABLED= CC=
Coverage is disabled.
Coverage is disabled.
+++ [0804 18:48:17] Placing binaries
+++ [0804 18:48:25] Syncing out of container
```

产物文件在`_output`目录上。

```bash
kubernetes/_output# tree
.
|-- dockerized
|   |-- bin
|   |   `-- linux
|   |       `-- amd64
|   |           |-- apiextensions-apiserver
|   |           |-- e2e_node.test
|   |           |-- e2e.test
|   |           |-- ginkgo
|   |           |-- go-runner
|   |           |-- kubeadm
|   |           |-- kube-aggregator
|   |           |-- kube-apiserver
|   |           |-- kube-controller-manager
|   |           |-- kubectl
|   |           |-- kubectl-convert
|   |           |-- kubelet
|   |           |-- kube-log-runner
|   |           |-- kubemark
|   |           |-- kube-proxy
|   |           |-- kube-scheduler
|   |           |-- mounter
|   |           `-- ncpu
|   `-- go
`-- images
    `-- kube-build:build-8faa8d3cb7-5-v1.27.0-go1.20.6-bullseye.0
        |-- Dockerfile
        |-- localtime
        |-- rsyncd.password
        `-- rsyncd.sh
```

### 2.1.2. 基于构建机环境编译

```bash
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes
# 构建全部二进制
make

# 构建指定二进制
make WHAT=cmd/kubeadm
```

输出如下：

```bash
# make WHAT=cmd/kubeadm
go version go1.20.6 linux/amd64
+++ [0804 19:30:55] Setting GOMAXPROCS: 8
+++ [0804 19:30:56] Building go targets for linux/amd64
    k8s.io/kubernetes/cmd/kubeadm (static)
```

## 2.2. 编译镜像

```bash
git clone https://github.com/kubernetes/kubernetes
cd kubernetes
make quick-release
```

# 3. 如何给k8s提交PR

参考：

- https://github.com/kubernetes/community/blob/master/contributors/guide/pull-requests.md

- https://github.com/kubernetes/community/blob/master/contributors/guide/first-contribution.md

- [Here is the bot commands documentation](https://go.k8s.io/bot-commands).

-  [testing guide](https://git.k8s.io/community/contributors/devel/sig-testing/testing.md)

参考：

- https://github.com/kubernetes/community/

- https://github.com/kubernetes/community/tree/master/contributors/guide

- https://github.com/kubernetes/community/blob/master/contributors/guide/first-contribution.md

-  [issues labeled as a good first issue](https://go.k8s.io/good-first-issue)
