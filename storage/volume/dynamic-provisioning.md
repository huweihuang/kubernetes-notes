---
title: "Dynamic Volume Provisioning 介绍"
linkTitle: "Dynamic Volume Provisioning"
weight: 5
catalog: true
date: 2019-6-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

## Dynamic Volume Provisioning

Dynamic volume provisioning允许用户按需自动创建存储卷，这种方式可以让用户不需要关心存储的复杂性和差别，又可以选择不同的存储类型。

## 1. 开启Dynamic Provisioning

需要先提前创建`StorageClass`对象，`StorageClass`中定义了使用哪个`provisioner`，并且在`provisioner`被调用时传入哪些参数，具体可参考`StorageClass`介绍。

例如：

- 磁盘类存储

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: slow
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-standard
```

- SSD类存储

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
```

## 2. 使用Dynamic Provisioning

创建一个PVC对象，并且在其中`storageClassName`字段指明需要用到的`StorageClass`的名称，例如：

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: claim1
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast
  resources:
    requests:
      storage: 30Gi
```

当使用到PVC的时候会自动创建对应的外部存储，当PVC被删除的时候，会自动销毁（或备份）外部存储。

## 3. 默认的StorageClass

当没有对应的`StorageClass`配置时，可以设定默认的`StorageClass`，需要执行以下操作：

- 在API Server开启[`DefaultStorageClass` admission controller](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#defaultstorageclass) 。
- 设置默认的`StorageClass`对象。

可以通过添加`storageclass.kubernetes.io/is-default-class`注解的方式设置某个`StorageClass`为默认的`StorageClass`。当用户创建了一个`PersistentVolumeClaim`，但没有指定`storageClassName`的时候，会自动将该PVC的`storageClassName`指向默认的`StorageClass`。



参考文章：

- https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/
