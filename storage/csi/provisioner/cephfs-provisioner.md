---
title: "部署cephfs-provisioner"
weight: 3
catalog: true
date: 2019-6-23 16:22:24
subtitle:
header-img:
tags:
- CSI
catagories:
- CSI
---

# 1. 安装cephfs客户端

所有node节点安装cephfs客户端，主要用来和ceph集群挂载使用。

```bash
yum install -y ceph-common
```


# 2. 部署RBAC


## 2.1. ClusterRole


```yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: cephfs-provisioner
  namespace: cephfs
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services"]
    resourceNames: ["kube-dns","coredns"]
    verbs: ["list", "get"]
```


## 2.2. ClusterRoleBinding


```yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: cephfs-provisioner
subjects:
  - kind: ServiceAccount
    name: cephfs-provisioner
    namespace: cephfs
roleRef:
  kind: ClusterRole
  name: cephfs-provisioner
  apiGroup: rbac.authorization.k8s.io
```

## 2.3. Role


```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cephfs-provisioner
  namespace: cephfs
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["create", "get", "delete"]
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
```


## 2.4. RoleBinding


```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cephfs-provisioner
  namespace: cephfs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cephfs-provisioner
subjects:
- kind: ServiceAccount
  name: cephfs-provisioner
```


## 2.5. ServiceAccount


```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cephfs-provisioner
  namespace: cephfs
```

# 3. 部署 cephfs-provisioner


```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: cephfs-provisioner
  namespace: cephfs
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: cephfs-provisioner
    spec:
      containers:
      - name: cephfs-provisioner
        image: "quay.io/external_storage/cephfs-provisioner:latest"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 64Mi        
        env:
        - name: PROVISIONER_NAME                # 与storageclass的provisioner参数相同
          value: ceph.com/cephfs
        - name: PROVISIONER_SECRET_NAMESPACE    # 与rbac的namespace相同
          value: cephfs
        command:
        - "/usr/local/bin/cephfs-provisioner"
        args:
        - "-id=cephfs-provisioner-1"
      serviceAccount: cephfs-provisioner
```


#  4. 部署storageclass


```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: cephfs-provisioner-sc
provisioner: ceph.com/cephfs
volumeBindingMode: WaitForFirstConsumer
parameters:
  monitors: 192.168.27.43:6789,192.168.27.44:6789,192.168.27.45:6789
  adminId: admin
  adminSecretName: csi-cephfs-secret
  adminSecretNamespace: "kube-csi"
  claimRoot: /pvc-volumes
```


# 5. 部署statefulset


```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cephfs-provisioner-nginx
spec:
  serviceName: "nginx"
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest   #nginx的镜像
        imagePullPolicy: IfNotPresent
        volumeMounts:
        - mountPath: "/mnt"      #容器里面的挂载目录，该目录挂载到NFS的共享目录上
          name: test
  volumeClaimTemplates:
  - metadata:
      name: test
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 2Gi
      storageClassName: cephfs-provisioner-sc
```

# 6. 日志

## 6.1. cephfs-provisoner 执行日志


```bash
I0327 07:18:19.742239       1 controller.go:987] provision "default/test-cephfs-ngx-wait-22-0" class "cephfs-provisioner-sc": started
I0327 07:18:19.745239       1 event.go:221] Event(v1.ObjectReference{Kind:"PersistentVolumeClaim", Namespace:"default", Name:"test-cephfs-ngx-wait-22-0", UID:"7f6b60d5-5060-11e9-9a9c-c81f66bcff65", APIVersion:"v1", ResourceVersion:"347214256", FieldPath:""}): type: 'Normal' reason: 'Provisioning' External provisioner is provisioning volume for claim "default/test-cephfs-ngx-wait-22-0"
I0327 07:18:23.281277       1 cephfs-provisioner.go:222] successfully created CephFS share &CephFSPersistentVolumeSource{Monitors:[192.168.27.43:6789 192.168.27.44:6789 192.168.27.45:6789],Path:/pvc-volumes/kubernetes/kubernetes-dynamic-pvc-7f7cb62f-5060-11e9-85c0-0adb8ef08100,User:kubernetes-dynamic-user-7f7cb69f-5060-11e9-85c0-0adb8ef08100,SecretFile:,SecretRef:&SecretReference{Name:ceph-kubernetes-dynamic-user-7f7cb69f-5060-11e9-85c0-0adb8ef08100-secret,Namespace:default,},ReadOnly:false,}
I0327 07:18:23.281371       1 controller.go:1087] provision "default/test-cephfs-ngx-wait-22-0" class "cephfs-provisioner-sc": volume "pvc-7f6b60d5-5060-11e9-9a9c-c81f66bcff65" provisioned
I0327 07:18:23.281415       1 controller.go:1101] provision "default/test-cephfs-ngx-wait-22-0" class "cephfs-provisioner-sc": trying to save persistentvvolume "pvc-7f6b60d5-5060-11e9-9a9c-c81f66bcff65"
I0327 07:18:23.284621       1 controller.go:1108] provision "default/test-cephfs-ngx-wait-22-0" class "cephfs-provisioner-sc": persistentvolume "pvc-7f6b60d5-5060-11e9-9a9c-c81f66bcff65" saved
I0327 07:18:23.284723       1 controller.go:1149] provision "default/test-cephfs-ngx-wait-22-0" class "cephfs-provisioner-sc": succeeded
I0327 07:18:23.284810       1 event.go:221] Event(v1.ObjectReference{Kind:"PersistentVolumeClaim", Namespace:"default", Name:"test-cephfs-ngx-wait-22-0", UID:"7f6b60d5-5060-11e9-9a9c-c81f66bcff65", APIVersion:"v1", ResourceVersion:"347214256", FieldPath:""}): type: 'Normal' reason: 'ProvisioningSucceeded' Successfully provisioned volume pvc-7f6b60d5-5060-11e9-9a9c-c81f66bcff65
```

## 6.2. debug 日志


```bash
I0327 08:08:11.789608       1 controller.go:987] provision "default/test-cephfs-ngx-wait-44-0" class "cephfs-sc-wait": started
I0327 08:08:11.793258       1 event.go:221] Event(v1.ObjectReference{Kind:"PersistentVolumeClaim", Namespace:"default", Name:"test-cephfs-ngx-wait-44-0", UID:"81846859-5067-11e9-9a9c-c81f66bcff65", APIVersion:"v1", ResourceVersion:"347237916", FieldPath:""}): type: 'Normal' reason: 'Provisioning' External provisioner is provisioning volume for claim "default/test-cephfs-ngx-wait-44-0"
E0327 08:08:12.164705       1 cephfs-provisioner.go:158] failed to provision share "kubernetes-dynamic-pvc-76ecdc5a-5067-11e9-9421-2a1b1be1aeef" for "kubernetes-dynamic-user-76ecdcee-5067-11e9-9421-2a1b1be1aeef", err: exit status 1, output: Traceback (most recent call last):
  File "/usr/local/bin/cephfs_provisioner", line 364, in <module>
    main()
  File "/usr/local/bin/cephfs_provisioner", line 358, in main
    print cephfs.create_share(share, user, size=size)
  File "/usr/local/bin/cephfs_provisioner", line 228, in create_share
    volume = self.volume_client.create_volume(volume_path, size=size, namespace_isolated=not self.ceph_namespace_isolation_disabled)
  File "/usr/local/bin/cephfs_provisioner", line 112, in volume_client
    self._volume_client.connect(None)
  File "/lib/python2.7/site-packages/ceph_volume_client.py", line 458, in connect
    self.rados.connect()
  File "rados.pyx", line 895, in rados.Rados.connect (/home/jenkins-build/build/workspace/ceph-build/ARCH/x86_64/AVAILABLE_ARCH/x86_64/AVAILABLE_DIST/centos7/DIST/centos7/MACHINE_SIZE/huge/release/13.2.1/rpm/el7/BUILD/ceph-13.2.1/build/src/pybind/rados/pyrex/rados.c:9815)
rados.IOError: [errno 5] error connecting to the cluster
W0327 08:08:12.164908       1 controller.go:746] Retrying syncing claim "default/test-cephfs-ngx-wait-44-0" because failures 2 < threshold 15
E0327 08:08:12.164977       1 controller.go:761] error syncing claim "default/test-cephfs-ngx-wait-44-0": failed to provision volume with StorageClass "cephfs-sc-wait": exit status 1
I0327 08:08:12.165974       1 event.go:221] Event(v1.ObjectReference{Kind:"PersistentVolumeClaim", Namespace:"default", Name:"test-cephfs-ngx-wait-44-0", UID:"81846859-5067-11e9-9a9c-c81f66bcff65", APIVersion:"v1", ResourceVersion:"347237916", FieldPath:""}): type: 'Warning' reason: 'ProvisioningFailed' failed to provision volume with StorageClass "cephfs-sc-wait": exit status 1
```



参考

- https://github.com/kubernetes-incubator/external-storage/tree/master/ceph/cephfs/deploy
  