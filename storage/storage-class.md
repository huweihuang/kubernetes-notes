# StorageClass

## 1. StorageClass概述

`StorageClass`提供了一种描述`存储类`（class）的方法，不同的class可能会映射到不同的服务质量等级和备份策略或其他策略等。

`StorageClass` 对象中包含 `provisioner`、`parameters` 和 `reclaimPolicy` 字段，当需要动态分配 `PersistentVolume` 时会使用到。当创建 `StorageClass` 对象时，设置名称和其他参数，一旦创建了对象就不能再对其更新。也可以为没有申请绑定到特定 class 的 PVC 指定一个默认的 `StorageClass` 。

**StorageClass对象文件**

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v3
metadata:
  name: standard
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
reclaimPolicy: Retain
mountOptions:
  - debug
```

## 2. StorageClass的属性

### 2.1.  Provisioner（存储分配器）

Storage class 有一个`分配器（provisioner）`，用来决定使用哪个卷插件分配 PV，该字段必须指定。可以指定内部分配器，也可以指定外部分配器。外部分配器的代码地址为： [kubernetes-incubator/external-storage](https://github.com/kubernetes-incubator/external-storage)，其中包括`NFS`和`Ceph`等。

### 2.2. Reclaim Policy（回收策略）

可以通过`reclaimPolicy`字段指定创建的`Persistent Volume`的回收策略，回收策略包括：`Delete` 或者 `Retain`，没有指定默认为`Delete`。

### 2.3. Mount Options（挂载选项）

由 storage class 动态创建的 Persistent Volume 将使用 class 中 `mountOptions` 字段指定的挂载选项。

### 2.4. 参数

Storage class 具有描述属于 storage class 卷的参数。取决于`分配器`，可以接受不同的参数。 当参数被省略时，会使用默认值。

例如以下使用`Ceph RBD`

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v3
metadata:
  name: fast
provisioner: kubernetes.io/rbd
parameters:
  monitors: 30.36.353.305:6789
  adminId: kube
  adminSecretName: ceph-secret
  adminSecretNamespace: kube-system
  pool: kube
  userId: kube
  userSecretName: ceph-secret-user
  fsType: ext4
  imageFormat: "2"
  imageFeatures: "layering"
```

 **对应的参数说明**

- `monitors`：Ceph monitor，逗号分隔。该参数是必需的。

- `adminId`：Ceph 客户端 ID，用于在池（ceph pool）中创建映像。 默认是 “admin”。

- `adminSecretNamespace`：adminSecret 的 namespace。默认是 “default”。

- `adminSecret`：adminId 的 Secret 名称。该参数是必需的。 提供的 secret 必须有值为 “kubernetes.io/rbd” 的 type 参数。

- `pool`: Ceph RBD 池. 默认是 “rbd”。

- `userId`：Ceph 客户端 ID，用于映射 RBD 镜像（RBD image）。默认与 adminId 相同。

- `userSecretName`：用于映射 RBD 镜像的 userId 的 Ceph Secret 的名字。 它必须与 PVC 存在于相同的 namespace 中。该参数是必需的。 提供的 secret 必须具有值为 “kubernetes.io/rbd” 的 type 参数，例如以这样的方式创建：

  ```bash
  kubectl create secret generic ceph-secret --type="kubernetes.io/rbd" \
    --from-literal=key='QVFEQ1pMdFhPUnQrSmhBQUFYaERWNHJsZ3BsMmNjcDR6RFZST0E9PQ==' \
    --namespace=kube-system
  ```

- `fsType`：Kubernetes 支持的 fsType。默认："ext4"。

- `imageFormat`：Ceph RBD 镜像格式，”1” 或者 “2”。默认值是 “1”。

- `imageFeatures`：这个参数是可选的，只能在你将 imageFormat 设置为 “2” 才使用。 目前支持的功能只是 `layering`。 默认是 ““，没有功能打开。


参考文章：

- https://kubernetes.io/docs/concepts/storage/storage-classes/
