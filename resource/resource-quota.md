> 本文个人博客地址：http://www.huweihuang.com/article/kubernetes/kubernetes-resource/

# 资源配额（ResourceQuota）

`ResourceQuota`对象用来定义某个命名空间下所有资源的使用限额，其实包括：

- 计算资源的配额
- 存储资源的配额
- 对象数量的配额

如果集群的总容量小于命名空间的配额总额，可能会产生资源竞争。这时会按照先到先得来处理。
资源竞争和配额的更新都不会影响已经创建好的资源。

## 1. 启动资源配额

Kubernetes 的众多发行版本默认开启了资源配额的支持。当在apiserver的`--admission-control`配置中添加`ResourceQuota`参数后，便启用了。 当一个命名空间中含有`ResourceQuota`对象时，资源配额将强制执行。

## 2. 计算资源配额

可以在给定的命名空间中限制可以请求的计算资源（[compute resources](https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/)）的总量。

| 资源名称        | 描述                                          |
| --------------- | --------------------------------------------- |
| cpu             | 非终止态的所有pod, cpu请求总量不能超出此值。  |
| limits.cpu      | 非终止态的所有pod， cpu限制总量不能超出此值。 |
| limits.memory   | 非终止态的所有pod, 内存限制总量不能超出此值。 |
| memory          | 非终止态的所有pod, 内存请求总量不能超出此值。 |
| requests.cpu    | 非终止态的所有pod, cpu请求总量不能超出此值。  |
| requests.memory | 非终止态的所有pod, 内存请求总量不能超出此值。 |

## 3. 存储资源配额

可以在给定的命名空间中限制可以请求的存储资源（[storage resources](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)）的总量。

| 资源名称                                            | 描述                                                         |
| --------------------------------------------------- | ------------------------------------------------------------ |
| requests.storage                                    | 所有PVC, 存储请求总量不能超出此值。                          |
| persistentvolumeclaims                              | 命名空间中可以存在的PVC（[persistent volume claims](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims)）总数。 |
| .storageclass.storage.k8s.io/requests.storage       | 和该存储类关联的所有PVC, 存储请求总和不能超出此值。          |
| .storageclass.storage.k8s.io/persistentvolumeclaims | 和该存储类关联的所有PVC，命名空间中可以存在的PVC（[persistent volume claims](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims)）总数。 |

## 4. 对象数量的配额

| 资源名称               | 描述                                                         |
| ---------------------- | ------------------------------------------------------------ |
| congfigmaps            | 命名空间中可以存在的配置映射的总数。                         |
| persistentvolumeclaims | 命名空间中可以存在的PVC总数。                                |
| pods                   | 命名空间中可以存在的非终止态的pod总数。如果一个pod的`status.phase` 是 `Failed, Succeeded`, 则该pod处于终止态。 |
| replicationcontrollers | 命名空间中可以存在的`rc`总数。                               |
| resourcequotas         | 命名空间中可以存在的资源配额（[resource quotas](https://kubernetes.io/docs/admin/admission-controllers/#resourcequota)）总数。 |
| services               | 命名空间中可以存在的服务总数量。                             |
| services.loadbalancers | 命名空间中可以存在的服务的负载均衡的总数量。                 |
| services.nodeports     | 命名空间中可以存在的服务的主机接口的总数量。                 |
| secrets                | 命名空间中可以存在的`secrets`的总数量。                      |

例如：可以定义pod的限额来避免某用户消耗过多的Pod IPs。

## 5. 限额的作用域

| 作用域         | 描述                                           |
| -------------- | ---------------------------------------------- |
| Terminating    | 匹配 `spec.activeDeadlineSeconds >= 0` 的pod   |
| NotTerminating | 匹配 `spec.activeDeadlineSeconds is nil` 的pod |
| BestEffort     | 匹配具有最佳服务质量的pod                      |
| NotBestEffort  | 匹配具有非最佳服务质量的pod                    |

## 6. request和limit

当分配计算资源时，每个容器可以为cpu或者内存指定一个请求值和一个限度值。可以配置限额值来限制它们中的任何一个值。
如果指定了`requests.cpu` 或者 `requests.memory`的限额值，那么就要求传入的每一个容器显式的指定这些资源的请求。如果指定了`limits.cpu`或者`limits.memory`，那么就要求传入的每一个容器显式的指定这些资源的限度。

## 7. 查看和设置配额

```shell
# 创建namespace
$ kubectl create namespace myspace

# 创建resourcequota
$ cat <<EOF > compute-resources.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-resources
spec:
  hard:
    pods: "4"
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
EOF
$ kubectl create -f ./compute-resources.yaml --namespace=myspace

# 查询resourcequota
$ kubectl get quota --namespace=myspace
NAME                    AGE
compute-resources       30s

# 查询resourcequota的详细信息
$ kubectl describe quota compute-resources --namespace=myspace
Name:                  compute-resources
Namespace:             myspace
Resource               Used Hard
--------               ---- ----
limits.cpu             0    2
limits.memory          0    2Gi
pods                   0    4
requests.cpu           0    1
requests.memory        0    1Gi
```

## 8. 配额和集群容量

资源配额对象与集群容量无关，它们以绝对单位表示。即增加节点的资源并不会增加已经配置的namespace的资源。

参考文章：
- https://kubernetes.io/docs/concepts/policy/resource-quotas/
  