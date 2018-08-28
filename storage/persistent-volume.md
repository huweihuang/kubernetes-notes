# PersistentVolume

## 1. PV概述

`PersistentVolume`（简称PV） 是 Volume 之类的卷插件，也是集群中的资源，但独立于Pod的生命周期（即不会因Pod删除而被删除），不归属于某个Namespace。

## 2. PV和PVC的生命周期

### 2.1. 配置（Provision）

有两种方式来配置 PV：静态或动态。

**1、静态**

手动创建PV，可供k8s集群中的对象消费。

**2、动态**

可以通过`StorageClass`和具体的`Provisioner`（例如`nfs-client-provisioner`）来动态地创建和删除PV。

### 2.2. 绑定

在动态配置的情况下，用户创建了特定的PVC，k8s会监听新的PVC，并寻找匹配的PV绑定。一旦绑定后，这种绑定是排他性的，PVC和PV的绑定是一对一的映射。

### 2.3. 使用

Pod 使用PVC作为卷。集群检查PVC以查找绑定的卷并为集群挂载该卷。用户通过在 Pod 的 volume 配置中包含 `persistentVolumeClaim` 来调度 Pod 并访问用户声明的 PV。

### 2.4. 回收

PV的回收策略可以设定PVC在释放后如何处理对应的Volume，目前有 `Retained`， `Recycled `和` Deleted`三种策略。

**1、保留**（Retain）

保留策略允许手动回收资源，当删除PVC的时候，PV仍然存在，可以通过以下步骤回收卷：

1. 删除PV
2. 手动清理外部存储的数据资源
3. 手动删除或重新使用关联的存储资产

**2、回收**（Resycle）

> 该策略已废弃，推荐使用dynamic provisioning

回收策略会在 volume上执行基本擦除（`rm -rf / thevolume / *`），可被再次声明使用。

**3、删除**（Delete）

删除策略，当发生删除操作的时候，会从k8s集群中删除PV对象，并执行外部存储资源的删除操作（根据不同的provisioner定义的删除逻辑不同，有的是重命名）。

动态配置的卷继承其`StorageClass`的回收策略，默认为Delete，即当用户删除PVC的时候，会自动执行PV的删除策略。

如果要修改PV的回收策略，可执行以下命令：

```bash
# Get pv 
kubectl get pv
# Change policy to Retaion
kubectl patch pv <pv_name> -p ‘{“spec”:{“persistentVolumeReclaimPolicy”:“Retain”}}’
```

## 3. PV的类型

`PersistentVolume` 类型以插件形式实现。以下仅列部分常用类型：

- GCEPersistentDisk
- AWSElasticBlockStore

- NFS
- RBD (Ceph Block Device)
- CephFS
- Glusterfs

## 4. PV的属性

每个` PV` 配置中都包含一个 `sepc `规格字段和一个 `status` 卷状态字段。

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  annotations:
    pv.kubernetes.io/provisioned-by: fuseim.pri/ifs
  creationTimestamp: 2018-07-12T06:46:48Z
  name: default-test-web-0-pvc-58cf5ec1-859f-11e8-bb61-005056b83985
  resourceVersion: "100163256"
  selfLink: /api/v1/persistentvolumes/default-test-web-0-pvc-58cf5ec1-859f-11e8-bb61-005056b83985
  uid: 59796ba3-859f-11e8-9c50-c81f66bcff65
spec:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 2Gi
  volumeMode: Filesystem  
  claimRef:
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: test-web-0
    namespace: default
    resourceVersion: "100163248"
    uid: 58cf5ec1-859f-11e8-bb61-005056b83985
  nfs:
    path: /data/nfs-storage/default-test-web-0-pvc-58cf5ec1-859f-11e8-bb61-005056b83985
    server: 172.16.201.54
  persistentVolumeReclaimPolicy: Delete
  storageClassName: managed-nfs-storage
  mountOptions:
    - hard
    - nfsvers=4.1
status:
  phase: Bound
```

### 4.1. Capacity

给PV设置特定的`存储容量`，更多 `capacity` 可参考Kubernetes [资源模型](https://git.k8s.io/community/contributors/design-proposals/scheduling/resources.md) 。

### 4.2. Volume Mode

` volumeMode` 的有效值可以是`Filesystem`或`Block`。如果未指定，volumeMode 将默认为`Filesystem`。

### 4.3. Access Modes

访问模式包括：

- `ReadWriteOnce`——该卷可以被单个节点以读/写模式挂载
- `ReadOnlyMany`——该卷可以被多个节点以只读模式挂载
- `ReadWriteMany`——该卷可以被多个节点以读/写模式挂载

在命令行中，访问模式缩写为：

- RWO - ReadWriteOnce
- ROX - ReadOnlyMany
- RWX - ReadWriteMany

> 一个卷一次只能使用一种访问模式挂载，即使它支持很多访问模式。

以下只列举部分常用插件：

| Volume 插件          | ReadWriteOnce | ReadOnlyMany | ReadWriteMany |
| -------------------- | ------------- | ------------ | ------------- |
| AWSElasticBlockStore | ✓             | -            | -             |
| CephFS               | ✓             | ✓            | ✓             |
| GCEPersistentDisk    | ✓             | ✓            | -             |
| Glusterfs            | ✓             | ✓            | ✓             |
| HostPath             | ✓             | -            | -             |
| NFS                  | ✓             | ✓            | ✓             |
| RBD                  | ✓             | ✓            | -             |
| ...                  |               |              |  -            |

### 4.4. Class

`PV`可以指定一个`StorageClass`来动态绑定PV和PVC，其中通过 `storageClassName` 属性来指定具体的`StorageClass`，如果没有指定该属性的PV，它只能绑定到不需要特定类的 PVC。

### 4.5. Reclaim Policy

回收策略包括：

- `Retain`（保留）——手动回收
- `Recycle`（回收）——基本擦除（`rm -rf /thevolume/*`）
- `Delete`（删除）——关联的存储资产（例如 AWS EBS、GCE PD、Azure Disk 和 OpenStack Cinder 卷）将被删除

当前，只有 NFS 和 HostPath 支持回收策略。AWS EBS、GCE PD、Azure Disk 和 Cinder 卷支持删除策略。

### 4.6. Mount Options

Kubernetes 管理员可以指定在节点上为挂载持久卷指定挂载选项。

> **注意**：不是所有的持久化卷类型都支持挂载选项。

支持挂载选项常用的类型有：

- GCEPersistentDisk
- AWSElasticBlockStore
- AzureFile
- AzureDisk
- NFS
- RBD （Ceph Block Device）
- CephFS
- Cinder （OpenStack 卷存储）
- Glusterfs

### 4.7. Phase

PV可以处于以下的某种状态：

- `Available`（可用）——一块空闲资源还没有被任何声明绑定
- `Bound`（已绑定）——卷已经被声明绑定
- `Released`（已释放）——声明被删除，但是资源还未被集群重新声明
- `Failed`（失败）——该卷的自动回收失败

命令行会显示绑定到 PV 的 PVC 的名称。

参考文章：

- https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/
