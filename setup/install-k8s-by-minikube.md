---
title: "[Kubernetes] 使用minikube安装k8s集群"
catalog: true
date: 2018-6-23 20:26:24
type: "tags"
subtitle:
header-img: "http://ozilwgpje.bkt.clouddn.com/scenery/building.jpg?imageslim"
tags:
- Kubernetes
catagories:
- Kubernetes
---

> 以下内容基于Linux系统，特别为Ubuntu系统

## 1. 安装kubectl

```shell
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

下载指定版本，例如下载v1.9.0版本

```shell
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

## 2. 安装minikube

`minikube`的源码地址：https://github.com/kubernetes/minikube

### 2.1 安装minikube

以下命令为安装`latest`版本的`minikube`。

```shell
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/
```

安装指定版本可到https://github.com/kubernetes/minikube/releases下载对应版本。

例如：以下为安装`v0.28.2`版本

```shell
curl -Lo minikube https://storage.googleapis.com/minikube/releases/v0.28.2/minikube-linux-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/
```

### 2.2 minikube命令帮助

```shell
Minikube is a CLI tool that provisions and manages single-node Kubernetes clusters optimized for development workflows.

Usage:
  minikube [command]

Available Commands:
  addons           Modify minikube's kubernetes addons
  cache            Add or delete an image from the local cache.
  completion       Outputs minikube shell completion for the given shell (bash or zsh)
  config           Modify minikube config
  dashboard        Opens/displays the kubernetes dashboard URL for your local cluster
  delete           Deletes a local kubernetes cluster
  docker-env       Sets up docker env variables; similar to '$(docker-machine env)'
  get-k8s-versions Gets the list of Kubernetes versions available for minikube when using the localkube bootstrapper
  ip               Retrieves the IP address of the running cluster
  logs             Gets the logs of the running localkube instance, used for debugging minikube, not user code
  mount            Mounts the specified directory into minikube
  profile          Profile sets the current minikube profile
  service          Gets the kubernetes URL(s) for the specified service in your local cluster
  ssh              Log into or run a command on a machine with SSH; similar to 'docker-machine ssh'
  ssh-key          Retrieve the ssh identity key path of the specified cluster
  start            Starts a local kubernetes cluster
  status           Gets the status of a local kubernetes cluster
  stop             Stops a running local kubernetes cluster
  update-check     Print current and latest version number
  update-context   Verify the IP address of the running cluster in kubeconfig.
  version          Print the version of minikube

Flags:
      --alsologtostderr                  log to standard error as well as files
  -b, --bootstrapper string              The name of the cluster bootstrapper that will set up the kubernetes cluster. (default "localkube")
      --log_backtrace_at traceLocation   when logging hits line file:N, emit a stack trace (default :0)
      --log_dir string                   If non-empty, write log files in this directory
      --loglevel int                     Log level (0 = DEBUG, 5 = FATAL) (default 1)
      --logtostderr                      log to standard error instead of files
  -p, --profile string                   The name of the minikube VM being used.
	This can be modified to allow for multiple minikube instances to be run independently (default "minikube")
      --stderrthreshold severity         logs at or above this threshold go to stderr (default 2)
  -v, --v Level                          log level for V logs
      --vmodule moduleSpec               comma-separated list of pattern=N settings for file-filtered logging

Use "minikube [command] --help" for more information about a command.
```

## 3. 使用minikube安装k8s集群

### 3.1. minikube start

可以以`Docker`的方式运行k8s的组件，但需要先安装Docker(可参考[Docker安装]())，启动参数使用`--vm-driver=none`。

```shell
minikube start --vm-driver=none
```

例如：

```shell
root@ubuntu:~# minikube start --vm-driver=none
Starting local Kubernetes v1.10.0 cluster...
Starting VM...
Getting VM IP address...
Moving files into cluster...
Downloading kubeadm v1.10.0
Downloading kubelet v1.10.0
^[[DFinished Downloading kubelet v1.10.0
Finished Downloading kubeadm v1.10.0
Setting up certs...
Connecting to cluster...
Setting up kubeconfig...
Starting cluster components...
Kubectl is now configured to use the cluster.
===================
WARNING: IT IS RECOMMENDED NOT TO RUN THE NONE DRIVER ON PERSONAL WORKSTATIONS
	The 'none' driver will run an insecure kubernetes apiserver as root that may leave the host vulnerable to CSRF attacks

When using the none driver, the kubectl config and credentials generated will be root owned and will appear in the root home directory.
You will need to move the files to the appropriate location and then set the correct permissions.  An example of this is below:

	sudo mv /root/.kube $HOME/.kube # this will write over any previous configuration
	sudo chown -R $USER $HOME/.kube
	sudo chgrp -R $USER $HOME/.kube

	sudo mv /root/.minikube $HOME/.minikube # this will write over any previous configuration
	sudo chown -R $USER $HOME/.minikube
	sudo chgrp -R $USER $HOME/.minikube

This can also be done automatically by setting the env var CHANGE_MINIKUBE_NONE_USER=true
Loading cached images from config file.
```

安装指定版本的kubernetes集群

```shell
# 查阅版本
minikube get-k8s-versions
# 选择版本启动
minikube start --kubernetes-version v1.7.3 --vm-driver=none
```

### 3.2. minikube status

```shell
$ minikube status
minikube: Running
cluster: Running
kubectl: Correctly Configured: pointing to minikube-vm at 172.16.94.139
```

### 3.3. minikube stop

`minikube stop` 命令可以用来停止集群。 该命令会关闭 minikube 虚拟机，但将保留所有集群状态和数据。 再次启动集群将恢复到之前的状态。

### 3.4. minikube delete

`minikube delete` 命令可以用来删除集群。 该命令将关闭并删除 minikube 虚拟机。没有数据或状态会被保存下来。

## 4. 查看部署结果

### 4.1. 部署组件

```shell
root@ubuntu:~# kubectl get all --namespace=kube-system
NAME                                        READY     STATUS    RESTARTS   AGE
pod/etcd-minikube                           1/1       Running   0          38m
pod/kube-addon-manager-minikube             1/1       Running   0          38m
pod/kube-apiserver-minikube                 1/1       Running   1          39m
pod/kube-controller-manager-minikube        1/1       Running   0          38m
pod/kube-dns-86f4d74b45-bdfnx               3/3       Running   0          38m
pod/kube-proxy-dqdvg                        1/1       Running   0          38m
pod/kube-scheduler-minikube                 1/1       Running   0          38m
pod/kubernetes-dashboard-5498ccf677-c2gnh   1/1       Running   0          38m
pod/storage-provisioner                     1/1       Running   0          38m

NAME                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)         AGE
service/kube-dns               ClusterIP   10.96.0.10      <none>        53/UDP,53/TCP   38m
service/kubernetes-dashboard   NodePort    10.104.48.227   <none>        80:30000/TCP    38m

NAME                        DESIRED   CURRENT   READY     UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/kube-proxy   1         1         1         1            1           <none>          38m

NAME                                   DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kube-dns               1         1         1            1           38m
deployment.apps/kubernetes-dashboard   1         1         1            1           38m

NAME                                              DESIRED   CURRENT   READY     AGE
replicaset.apps/kube-dns-86f4d74b45               1         1         1         38m
replicaset.apps/kubernetes-dashboard-5498ccf677   1         1         1         38m
```

### 4.2. dashboard

通过访问`ip:port`，例如：http://172.16.94.139:30000/，可以访问k8s的`dashboard`控制台。

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1533695750/article/kubernetes/arch/dashboard.png" width = "100%"/>

## 5. troubleshooting

### 5.1. 没有安装VirtualBox

```shell
[root@minikube ~]# minikube start
Starting local Kubernetes v1.10.0 cluster...
Starting VM...
Downloading Minikube ISO
 160.27 MB / 160.27 MB [============================================] 100.00% 0s
E0727 15:47:08.655647    9407 start.go:174] Error starting host: Error creating host: Error executing step: Running precreate checks.
: VBoxManage not found. Make sure VirtualBox is installed and VBoxManage is in the path.

 Retrying.
E0727 15:47:08.656994    9407 start.go:180] Error starting host:  Error creating host: Error executing step: Running precreate checks.
: VBoxManage not found. Make sure VirtualBox is installed and VBoxManage is in the path
================================================================================
An error has occurred. Would you like to opt in to sending anonymized crash
information to minikube to help prevent future errors?
To opt out of these messages, run the command:
	minikube config set WantReportErrorPrompt false
================================================================================
Please enter your response [Y/n]:
```

解决方法，先安装VirtualBox。

### 5.2. 没有安装Docker

```shell
[root@minikube ~]# minikube start --vm-driver=none
Starting local Kubernetes v1.10.0 cluster...
Starting VM...
E0727 15:56:54.936706    9441 start.go:174] Error starting host: Error creating host: Error executing step: Running precreate checks.
: docker cannot be found on the path for this machine. A docker installation is a requirement for using the none driver: exec: "docker": executable file not found in $PATH.

 Retrying.
E0727 15:56:54.938930    9441 start.go:180] Error starting host:  Error creating host: Error executing step: Running precreate checks.
: docker cannot be found on the path for this machine. A docker installation is a requirement for using the none driver: exec: "docker": executable file not found in $PATH
```

解决方法，先安装Docker。



文章参考：

https://github.com/kubernetes/minikube

https://kubernetes.io/docs/setup/minikube/

https://kubernetes.io/docs/tasks/tools/install-minikube/

https://kubernetes.io/docs/tasks/tools/install-kubectl/

