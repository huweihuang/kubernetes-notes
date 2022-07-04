# PersistentVolumeClaim

## 1. PVC概述

`PersistentVolumeClaim`（简称PVC）是用户存储的请求，PVC消耗PV的资源，可以请求特定的大小和访问模式，需要指定归属于某个Namespace，在同一个Namespace的Pod才可以指定对应的PVC。

当需要不同性质的PV来满足存储需求时，可以使用`StorageClass`来实现。

每个 PVC 中都包含一个 spec 规格字段和一个 status 声明状态字段。

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: myclaim
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 8Gi
  storageClassName: slow
  selector:
    matchLabels:
      release: "stable"
    matchExpressions:
      - {key: environment, operator: In, values: [dev]}
```

## 2. PVC的属性

### 2.1. accessModes

对应存储的访问模式，例如：`ReadWriteOnce`。

### 2.2. volumeMode

对应存储的数据卷模式，例如：`Filesystem`。

### 2.3. resources

声明可以请求特定数量的资源。相同的[资源模型](https://git.k8s.io/community/contributors/design-proposals/scheduling/resources.md)适用于Volume和PVC。

### 2.4. selector

声明`label selector`，只有标签与选择器匹配的卷可以绑定到声明。

- matchLabels：volume 必须有具有该值的标签
- matchExpressions：条件列表，通过条件表达式筛选匹配的卷。有效的运算符包括 In、NotIn、Exists 和 DoesNotExist。

### 2.5. storageClassName

通过`storageClassName`参数来指定使用对应名字的`StorageClass`，只有所请求的类与 PVC 具有相同 `storageClassName` 的 PV 才能绑定到 PVC。

PVC可以不指定storageClassName，或者将该值设置为空，如果打开了准入控制插件，并且指定一个默认的 `StorageClass`，则PVC会使用默认的`StorageClass`，否则就绑定到没有`StorageClass`的 PV上。

> 之前使用注解 `volume.beta.kubernetes.io/storage-class` 而不是 `storageClassName` 属性。这个注解仍然有效，但是在未来的 Kubernetes 版本中不会支持。

## 3. 将PVC作为Volume

将PVC作为Pod的Volume，PVC与Pod需要在同一个命名空间下，其实Pod的声明如下：

```yaml
kind: Pod
apiVersion: v1
metadata:
  name: mypod
spec:
  containers:
    - name: myfrontend
      image: dockerfile/nginx
      volumeMounts:
      - mountPath: "/var/www/html"
        name: mypd
  volumes:
    - name: mypd
      persistentVolumeClaim:    # 使用PVC
        claimName: myclaim
```

`PersistentVolumes` 绑定是唯一的，并且由于 `PersistentVolumeClaims` 是命名空间对象，因此只能在一个命名空间内挂载具有“多个”模式（`ROX`、`RWX`）的PVC。

参考文章：

- https://kubernetes.io/docs/concepts/storage/persistent-volumes/
