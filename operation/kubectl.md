> 本文个人博客地址：http://www.huweihuang.com/article/kubernetes/kubernetes-commands/

# 1. kubectl介绍

kubectl controls the Kubernetes cluster manager.

Usage:
 kubectl [flags] 
 kubectl [command]

```bash
[root@node5 ~]# kubectl
kubectl controls the Kubernetes cluster manager.

Find more information at https://github.com/kubernetes/kubernetes.

Basic Commands (Beginner):
  create         Create a resource from a file or from stdin.
  expose         Take a replication controller, service, deployment or pod and expose it as a new Kubernetes Service
  run            Run a particular image on the cluster
  set            Set specific features on objects
  run-container  Run a particular image on the cluster. This command is deprecated, use "run" instead

Basic Commands (Intermediate):
  get            Display one or many resources
  explain        Documentation of resources
  edit           Edit a resource on the server
  delete         Delete resources by filenames, stdin, resources and names, or by resources and label selector

Deploy Commands:
  rollout        Manage the rollout of a resource
  rolling-update Perform a rolling update of the given ReplicationController
  scale          Set a new size for a Deployment, ReplicaSet, Replication Controller, or Job
  autoscale      Auto-scale a Deployment, ReplicaSet, or ReplicationController

Cluster Management Commands:
  certificate    Modify certificate resources.
  cluster-info   Display cluster info
  top            Display Resource (CPU/Memory/Storage) usage.
  cordon         Mark node as unschedulable
  uncordon       Mark node as schedulable
  drain          Drain node in preparation for maintenance
  taint          Update the taints on one or more nodes

Troubleshooting and Debugging Commands:
  describe       Show details of a specific resource or group of resources
  logs           Print the logs for a container in a pod
  attach         Attach to a running container
  exec           Execute a command in a container
  port-forward   Forward one or more local ports to a pod
  proxy          Run a proxy to the Kubernetes API server
  cp             Copy files and directories to and from containers.
  auth           Inspect authorization

Advanced Commands:
  apply          Apply a configuration to a resource by filename or stdin
  patch          Update field(s) of a resource using strategic merge patch
  replace        Replace a resource by filename or stdin
  convert        Convert config files between different API versions

Settings Commands:
  label          Update the labels on a resource
  annotate       Update the annotations on a resource
  completion     Output shell completion code for the specified shell (bash or zsh)

Other Commands:
  api-versions   Print the supported API versions on the server, in the form of "group/version"
  config         Modify kubeconfig files
  help           Help about any command
  plugin         Runs a command-line plugin
  version        Print the client and server version information

Use "kubectl <command> --help" for more information about a given command.
Use "kubectl options" for a list of global command-line options (applies to all commands).
```

# 2. 操作的资源对象

1. Node
2. Podes
3. Replication Controllers
4. Services
5. Namespace
6. ComponentStatus

# 3. kubectl命令分类[command]

## 3.1 增

1）create:[Create a resource by filename or stdin]

2）run:[ Run a particular image on the cluster]

3）apply:[Apply a configuration to a resource by filename or stdin]

4）proxy:[Run a proxy to the Kubernetes API server ]

## 3.2 删

1）delete:[Delete resources ]

## 3.3 改

1）scale:[Set a new size for a Replication Controller]

2）exec:[Execute a command in a container]

3）attach:[Attach to a running container]

4）patch:[Update field(s) of a resource by stdin]

5）edit:[Edit a resource on the server]

6） label:[Update the labels on a resource]

7）annotate:[Auto-scale a replication controller]

8）replace:[Replace a resource by filename or stdin]

9）config:[config modifies kubeconfig files]

## 3.4 查

1）get:[Display one or many resources]

2）describe:[Show details of a specific resource or group of resources]

3）log:[Print the logs for a container in a pod]

4）cluster-info:[Display cluster info]

5） version:[Print the client and server version information]

6）api-versions:[Print the supported API versions]

# 4. 配置K8S环境

## 4.1 非安全方式

```bash
kubectl config set-cluster k8s --server=http://<url> 
kubectl config set-context <namespace> --cluster=k8s --namespace=<namespace> 

kubectl config use-context <namespace> 
```

## 4.2 安全方式

```bash
kubectl config set-cluster k8s --server=https://<url> --insecure-skip-tls-verify=true
kubectl config set-credentials k8s-user --username=<username> --password=<password>

kubectl config set-context <namespace> --cluster=k8s --user=k8s-user --namespace=<namespace> 
kubectl config use-context <namespace>
```

## 4.3 查询当前配置环境

```bash
[root@mysql2 ]# kubectl cluster-info
Kubernetes master is running at http://192.168.19.2:8081
```

# 5. Pod相关命令

## 5.1 查询Pod

```bash
kubectl get pod -o wide --namespace=<NAMESPACE>
```

## 5.2 进入Pod

```bash
kubectl exec -it <Pod_NAME> /bin/bash --namespace=<namespace>
```

## 5.3 删除Pod

```bash
kubectl delete pod wsop-proxy-1-0-9-ii97y 
```

## 5.4 日志查看

```bash
$ 查看运行容器日志 
kubectl logs wsop-proxy-1-0-9-ii97y --namespace=<namespace>
$ 查看上一个挂掉的容器日志 
kubectl logs wsop-proxy-1-0-9-ii97y -p --namespace=<namespace> 
```

# 6. Node隔离与恢复

说明：Node设置隔离之后，原先运行在该Node上的Pod不受影响，后续的Pod不会调度到被隔离的Node上。

**1. Node隔离**

```bash
kubectl patch node <NodeName> -p '{"spec":{"unschedulable":true}}'
```
**2. Node恢复**

```bash
kubectl patch node <NodeName> -p '{"spec":{"unschedulable":false}}'
```

# 7. kubectl label

**1. 固定Pod到指定机器**

```bash
kubectl label node <NodeName> namespace/<NAMESPACE>=true
```

**2. 取消Pod固定机器**

```bash
kubectl label node <NodeName> namespace/<NAMESPACE>-
```

# 8. kubectl 自动补全

```bash
# for linux
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc
```
