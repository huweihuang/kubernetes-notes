---
title: "kubectl安装与配置"
weight: 1
catalog: true
date: 2019-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. kubectl的安装

```bash
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

安装指定版本的kubectl，例如：`v1.9.0`

```bash
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

# 2. 配置k8s集群环境

## 2.1. 命令行方式

### 2.1.1 非安全方式

```bash
kubectl config set-cluster k8s --server=http://<url> 
kubectl config set-context <NAMESPACE> --cluster=k8s --namespace=<NAMESPACE> 

kubectl config use-context <NAMESPACE> 
```

### 2.1.2 安全方式

```bash
kubectl config set-cluster k8s --server=https://<url> --insecure-skip-tls-verify=true
kubectl config set-credentials k8s-user --username=<username> --password=<password>

kubectl config set-context <NAMESPACE> --cluster=k8s --user=k8s-user --namespace=<NAMESPACE> 
kubectl config use-context <NAMESPACE>
```

### 2.1.3 查询当前配置环境

```bash
[root@test ]# kubectl cluster-info
Kubernetes master is running at http://192.168.10.3:8081
```

## 2.2. 添加配置文件的方式

当没有指定` --kubeconfig`参数和`$KUBECONFIG`的环境变量的时候，会默认读取`${HOME}/.kube/config`。

因此创建`${HOME}/.kube/config`文件，并在``${HOME}/.kube/ssl`目录下创建ca.pem、cert.pem、key.pem文件。

内容如下：

```yaml
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    certificate-authority: ./ssl/ca.pem
    server: https://192.168.10.3:6443
users:
- name: kubelet
  user:
    client-certificate: ./ssl/cert.pem
    client-key: ./ssl/key.pem
contexts:
- context:
    cluster: local
    user: kubelet
  name: kubelet-cluster.local
current-context: kubelet-cluster.local
```

# 3. kubectl config

 kubectl config命令说明

```bash
$ kubectl config --help
Modify kubeconfig files using subcommands like "kubectl config set current-context my-context"

The loading order follows these rules:

  1. If the --kubeconfig flag is set, then only that file is loaded.  The flag may only be set once and no merging takes
place.
  2. If $KUBECONFIG environment variable is set, then it is used a list of paths (normal path delimitting rules for your
system).  These paths are merged.  When a value is modified, it is modified in the file that defines the stanza.  When a
value is created, it is created in the first file that exists.  If no files in the chain exist, then it creates the last
file in the list.
  3. Otherwise, ${HOME}/.kube/config is used and no merging takes place.

Available Commands:
  current-context Displays the current-context
  delete-cluster  Delete the specified cluster from the kubeconfig
  delete-context  Delete the specified context from the kubeconfig
  get-clusters    Display clusters defined in the kubeconfig
  get-contexts    Describe one or many contexts
  rename-context  Renames a context from the kubeconfig file.
  set             Sets an individual value in a kubeconfig file
  set-cluster     Sets a cluster entry in kubeconfig
  set-context     Sets a context entry in kubeconfig
  set-credentials Sets a user entry in kubeconfig
  unset           Unsets an individual value in a kubeconfig file
  use-context     Sets the current-context in a kubeconfig file
  view            Display merged kubeconfig settings or a specified kubeconfig file

Usage:
  kubectl config SUBCOMMAND [options]

Use "kubectl <command> --help" for more information about a given command.
Use "kubectl options" for a list of global command-line options (applies to all commands).
```

# 4. shell自动补齐

```bash
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc
```

如果出现以下报错

```bash
# kubectl自动补齐失败
kubectl _get_comp_words_by_ref : command not found
```

解决方法：

```bash
yum install bash-completion -y

source /etc/profile.d/bash_completion.sh 
```



参考文章：

- https://kubernetes.io/docs/tasks/tools/install-kubectl/

