# 0. 说明

要求Kubernetes的版本在`1.11`及以上，k8s集群必须允许特权Pod（`privileged pods`），即apiserver和kubelet需要设置`--allow-privileged`为`true`。节点的`Docker daemon`需要允许挂载共享卷。

## 涉及镜像

- quay.io/k8scsi/csi-provisioner:v0.3.0
- quay.io/k8scsi/csi-attacher:v0.3.0
- quay.io/k8scsi/driver-registrar:v0.3.0
- quay.io/cephcsi/cephfsplugin:v0.3.0

# 1. 部署RBAC

部署`service accounts`, `cluster roles` 和 `cluster role bindings`，这些可供`RBD`和`CephFS CSI plugins`共同使用，他们拥有相同的权限。

```bash
$ kubectl create -f csi-attacher-rbac.yaml
$ kubectl create -f csi-provisioner-rbac.yaml
$ kubectl create -f csi-nodeplugin-rbac.yaml
```

## 1.1. csi-attacher-rbac.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-attacher

---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: external-attacher-runner
rules:
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch", "update"]

---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-attacher-role
subjects:
  - kind: ServiceAccount
    name: csi-attacher
    namespace: default
roleRef:
  kind: ClusterRole
  name: external-attacher-runner
  apiGroup: rbac.authorization.k8s.io
```

## 1.2. csi-provisioner-rbac.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-provisioner

---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: external-provisioner-runner
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
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
    verbs: ["list", "watch", "create", "update", "patch"]
    
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-provisioner-role
subjects:
  - kind: ServiceAccount
    name: csi-provisioner
    namespace: default
roleRef:
  kind: ClusterRole
  name: external-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
```

## 1.3. csi-nodeplugin-rbac.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-nodeplugin

---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-nodeplugin
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "update"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch", "update"]

---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-nodeplugin
subjects:
  - kind: ServiceAccount
    name: csi-nodeplugin
    namespace: default
roleRef:
  kind: ClusterRole
  name: csi-nodeplugin
  apiGroup: rbac.authorization.k8s.io          
```

# 2. 部署CSI sidecar containers

通过`StatefulSet`的方式部署`external-attacher`和`external-provisioner`供`CSI CephFS`使用。

```bash
$ kubectl create -f csi-cephfsplugin-attacher.yaml
$ kubectl create -f csi-cephfsplugin-provisioner.yaml
```

## 2.1. csi-cephfsplugin-provisioner.yaml

```yaml
kind: Service
apiVersion: v1
metadata:
  name: csi-cephfsplugin-provisioner
  labels:
    app: csi-cephfsplugin-provisioner
spec:
  selector:
    app: csi-cephfsplugin-provisioner
  ports:
    - name: dummy
      port: 12345

---
kind: StatefulSet
apiVersion: apps/v1beta1
metadata:
  name: csi-cephfsplugin-provisioner
spec:
  serviceName: "csi-cephfsplugin-provisioner"
  replicas: 1
  template:
    metadata:
      labels:
        app: csi-cephfsplugin-provisioner
    spec:
      serviceAccount: csi-provisioner
      containers:
        - name: csi-provisioner
          image: quay.io/k8scsi/csi-provisioner:v0.3.0
          args:
            - "--provisioner=csi-cephfsplugin"
            - "--csi-address=$(ADDRESS)"
            - "--v=5"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/plugins/csi-cephfsplugin/csi.sock
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /var/lib/kubelet/plugins/csi-cephfsplugin
      volumes:
        - name: socket-dir
          hostPath:
            path: /var/lib/kubelet/plugins/csi-cephfsplugin
            type: DirectoryOrCreate
```

## 2.2. csi-cephfsplugin-attacher.yaml

```yaml
kind: Service
apiVersion: v1
metadata:
  name: csi-cephfsplugin-attacher
  labels:
    app: csi-cephfsplugin-attacher
spec:
  selector:
    app: csi-cephfsplugin-attacher
  ports:
    - name: dummy
      port: 12345

---
kind: StatefulSet
apiVersion: apps/v1beta1
metadata:
  name: csi-cephfsplugin-attacher
spec:
  serviceName: "csi-cephfsplugin-attacher"
  replicas: 1
  template:
    metadata:
      labels:
        app: csi-cephfsplugin-attacher
    spec:
      serviceAccount: csi-attacher
      containers:
        - name: csi-cephfsplugin-attacher
          image: quay.io/k8scsi/csi-attacher:v0.3.0
          args:
            - "--v=5"
            - "--csi-address=$(ADDRESS)"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/plugins/csi-cephfsplugin/csi.sock
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /var/lib/kubelet/plugins/csi-cephfsplugin
      volumes:
        - name: socket-dir
          hostPath:
            path: /var/lib/kubelet/plugins/csi-cephfsplugin
            type: DirectoryOrCreate
```

# 3. 部署CSI-CephFS-driver(plugin)

> csi-cephfs-plugin 的作用类似nfs-client，部署在所有node节点上，执行ceph的挂载等相关任务。

通过`DaemonSet`的方式部署，其中包括两个容器：`CSI driver-registrar` 和 `CSI CephFS driver`。

```bash
$ kubectl create -f csi-cephfsplugin.yaml
```

## 3.1. csi-cephfsplugin.yaml

```yaml
kind: DaemonSet
apiVersion: apps/v1beta2
metadata:
  name: csi-cephfsplugin
spec:
  selector:
    matchLabels:
      app: csi-cephfsplugin
  template:
    metadata:
      labels:
        app: csi-cephfsplugin
    spec:
      serviceAccount: csi-nodeplugin
      hostNetwork: true
      # to use e.g. Rook orchestrated cluster, and mons' FQDN is
      # resolved through k8s service, set dns policy to cluster first
      dnsPolicy: ClusterFirstWithHostNet      
      containers:
        - name: driver-registrar
          image: quay.io/k8scsi/driver-registrar:v0.3.0
          args:
            - "--v=5"
            - "--csi-address=$(ADDRESS)"
            - "--kubelet-registration-path=$(DRIVER_REG_SOCK_PATH)"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/plugins/csi-cephfsplugin/csi.sock
            - name: DRIVER_REG_SOCK_PATH
              value: /var/lib/kubelet/plugins/csi-cephfsplugin/csi.sock
            - name: KUBE_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          volumeMounts:
            - name: socket-dir
              mountPath: /var/lib/kubelet/plugins/csi-cephfsplugin
            - name: registration-dir
              mountPath: /registration
        - name: csi-cephfsplugin
          securityContext:
            privileged: true
            capabilities:
              add: ["SYS_ADMIN"]
            allowPrivilegeEscalation: true
          image: quay.io/cephcsi/cephfsplugin:v0.3.0
          args :
            - "--nodeid=$(NODE_ID)"
            - "--endpoint=$(CSI_ENDPOINT)"
            - "--v=5"
            - "--drivername=csi-cephfsplugin"
          env:
            - name: NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: CSI_ENDPOINT
              value: unix://var/lib/kubelet/plugins/csi-cephfsplugin/csi.sock
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: plugin-dir
              mountPath: /var/lib/kubelet/plugins/csi-cephfsplugin
            - name: pods-mount-dir
              mountPath: /var/lib/kubelet/pods
              mountPropagation: "Bidirectional"
            - mountPath: /sys
              name: host-sys
            - name: lib-modules
              mountPath: /lib/modules
              readOnly: true
            - name: host-dev
              mountPath: /dev
      volumes:
        - name: plugin-dir
          hostPath:
            path: /var/lib/kubelet/plugins/csi-cephfsplugin
            type: DirectoryOrCreate
        - name: registration-dir
          hostPath:
            path: /var/lib/kubelet/plugins/
            type: Directory
        - name: pods-mount-dir
          hostPath:
            path: /var/lib/kubelet/pods
            type: Directory
        - name: socket-dir
          hostPath:
            path: /var/lib/kubelet/plugins/csi-cephfsplugin
            type: DirectoryOrCreate
        - name: host-sys
          hostPath:
            path: /sys
        - name: lib-modules
          hostPath:
            path: /lib/modules
        - name: host-dev
          hostPath:
            path: /dev
```

# 4. 确认部署结果

```bash
$ kubectl get all
NAME                                 READY     STATUS    RESTARTS   AGE
pod/csi-cephfsplugin-attacher-0      1/1       Running   0          26s
pod/csi-cephfsplugin-provisioner-0   1/1       Running   0          25s
pod/csi-cephfsplugin-rljcv           2/2       Running   0          24s

NAME                                   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)     AGE
service/csi-cephfsplugin-attacher      ClusterIP   10.104.116.218   <none>        12345/TCP   27s
service/csi-cephfsplugin-provisioner   ClusterIP   10.101.78.75     <none>        12345/TCP   26s

...
```



参考文档：

- https://github.com/ceph/ceph-csi
- https://github.com/ceph/ceph-csi/blob/master/docs/deploy-cephfs.md
- https://github.com/ceph/ceph-csi/tree/master/deploy/cephfs/kubernetes
