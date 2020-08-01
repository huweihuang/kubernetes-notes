> 本文主要介绍etcd-operator的部署及使用

# 1. 部署RBAC

下载[create_role.sh](https://github.com/coreos/etcd-operator/blob/master/example/rbac/create_role.sh)、[cluster-role-binding-template.yaml](https://github.com/coreos/etcd-operator/blob/master/example/rbac/cluster-role-binding-template.yaml)、[cluster-role-template.yaml](https://github.com/coreos/etcd-operator/blob/master/example/rbac/cluster-role-template.yaml)

例如：

```bash
|-- cluster-role-binding-template.yaml
|-- cluster-role-template.yaml
|-- create_role.sh

# 部署rbac
kubectl create ns operator
bash create_role.sh --namespace=operator  # namespace与etcd-operator的ns一致
```

示例：

```bash
bash create_role.sh --namespace=operator
+ ROLE_NAME=etcd-operator
+ ROLE_BINDING_NAME=etcd-operator
+ NAMESPACE=default
+ for i in '"$@"'
+ case $i in
+ NAMESPACE=operator
+ echo 'Creating role with ROLE_NAME=etcd-operator, NAMESPACE=operator'
Creating role with ROLE_NAME=etcd-operator, NAMESPACE=operator
+ sed -e 's/<ROLE_NAME>/etcd-operator/g' -e 's/<NAMESPACE>/operator/g' cluster-role-template.yaml
+ kubectl create -f -
clusterrole.rbac.authorization.k8s.io/etcd-operator created
+ echo 'Creating role binding with ROLE_NAME=etcd-operator, ROLE_BINDING_NAME=etcd-operator, NAMESPACE=operator'
Creating role binding with ROLE_NAME=etcd-operator, ROLE_BINDING_NAME=etcd-operator, NAMESPACE=operator
+ sed -e 's/<ROLE_NAME>/etcd-operator/g' -e 's/<ROLE_BINDING_NAME>/etcd-operator/g' -e 's/<NAMESPACE>/operator/g' cluster-role-binding-template.yaml
+ kubectl create -f -
clusterrolebinding.rbac.authorization.k8s.io/etcd-operator created
```

## 1.1. create_role.sh 脚本

create_role.sh有三个入参，可以指定--namespace参数，该参数与etcd-operator部署的namespace应一致。默认为default。

```bash
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

ETCD_OPERATOR_ROOT=$(dirname "${BASH_SOURCE}")/../..

print_usage() {
  echo "$(basename "$0") - Create Kubernetes RBAC role and role bindings for etcd-operator
Usage: $(basename "$0") [options...]
Options:
  --role-name=STRING         Name of ClusterRole to create
                               (default=\"etcd-operator\", environment variable: ROLE_NAME)
  --role-binding-name=STRING Name of ClusterRoleBinding to create
                               (default=\"etcd-operator\", environment variable: ROLE_BINDING_NAME)
  --namespace=STRING         namespace to create role and role binding in. Must already exist.
                               (default=\"default\", environment variable: NAMESPACE)
" >&2
}

ROLE_NAME="${ROLE_NAME:-etcd-operator}"
ROLE_BINDING_NAME="${ROLE_BINDING_NAME:-etcd-operator}"
NAMESPACE="${NAMESPACE:-default}"

for i in "$@"
do
case $i in
    --role-name=*)
    ROLE_NAME="${i#*=}"
    ;;
    --role-binding-name=*)
    ROLE_BINDING_NAME="${i#*=}"
    ;;
    --namespace=*)
    NAMESPACE="${i#*=}"
    ;;
    -h|--help)
      print_usage
      exit 0
    ;;
    *)
      print_usage
      exit 1
    ;;
esac
done

echo "Creating role with ROLE_NAME=${ROLE_NAME}, NAMESPACE=${NAMESPACE}"
sed -e "s/<ROLE_NAME>/${ROLE_NAME}/g" \
  -e "s/<NAMESPACE>/${NAMESPACE}/g" \
  "cluster-role-template.yaml" | \
  kubectl create -f -

echo "Creating role binding with ROLE_NAME=${ROLE_NAME}, ROLE_BINDING_NAME=${ROLE_BINDING_NAME}, NAMESPACE=${NAMESPACE}"
sed -e "s/<ROLE_NAME>/${ROLE_NAME}/g" \
  -e "s/<ROLE_BINDING_NAME>/${ROLE_BINDING_NAME}/g" \
  -e "s/<NAMESPACE>/${NAMESPACE}/g" \
  "cluster-role-binding-template.yaml" | \
  kubectl create -f -
```

## 1.2. cluster-role-binding-template.yaml

```yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: <ROLE_BINDING_NAME>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: <ROLE_NAME>
subjects:
- kind: ServiceAccount
  name: default
  namespace: <NAMESPACE>
```

## 1.3. cluster-role-template.yaml

```yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: <ROLE_NAME>
rules:
- apiGroups:
  - etcd.database.coreos.com
  resources:
  - etcdclusters
  - etcdbackups
  - etcdrestores
  verbs:
  - "*"
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
  - "*"
- apiGroups:
  - ""
  resources:
  - pods
  - services
  - endpoints
  - persistentvolumeclaims
  - events
  verbs:
  - "*"
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - "*"
# The following permissions can be removed if not using S3 backup and TLS
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
```

# 2. 部署etcd-operator

```bash
kubectl create -f etcd-operator.yaml
```

etcd-operator.yaml如下：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: etcd-operator
  namespace: operator   # 与rbac指定的ns一致
  labels:
    app: etcd-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: etcd-operator
  template:
    metadata:
      labels:
        app: etcd-operator
    spec:
      containers:
      - name: etcd-operator
        image: registry.cn-shenzhen.aliyuncs.com/huweihuang/etcd-operator:v0.9.4
        command:
        - etcd-operator
        # Uncomment to act for resources in all namespaces. More information in doc/user/clusterwide.md
        - -cluster-wide
        env:
        - name: MY_POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
```

查看CRD

```bash
#kubectl get customresourcedefinitions
NAME                                       CREATED AT
etcdclusters.etcd.database.coreos.com      2020-08-01T13:02:18Z
```

查看etcd-operator的日志是否OK。

```bash
k logs -f etcd-operator-545df8d445-qpf6n -n operator
time="2020-08-01T13:02:18Z" level=info msg="etcd-operator Version: 0.9.4"
time="2020-08-01T13:02:18Z" level=info msg="Git SHA: c8a1c64"
time="2020-08-01T13:02:18Z" level=info msg="Go Version: go1.11.5"
time="2020-08-01T13:02:18Z" level=info msg="Go OS/Arch: linux/amd64"
time="2020-08-01T13:02:18Z" level=info msg="Event(v1.ObjectReference{Kind:\"Endpoints\", Namespace:\"operator\", Name:\"etcd-operator\", UID:\"7de38cff-1b7b-4bf2-9837-473fa66c9366\", APIVersion:\"v1\", ResourceVersion:\"41195930\", FieldPath:\"\"}): type: 'Normal' reason: 'LeaderElection' etcd-operator-545df8d445-qpf6n became leader"
```

以上内容表示etcd-operator运行正常。

# 3. 部署etcd集群

```bash
kubectl create -f etcd-cluster.yaml
```

> 当开启clusterwide则etcd集群与etcd-operator的ns可不同。

etcd-cluster.yaml

```yaml
apiVersion: "etcd.database.coreos.com/v1beta2"
kind: "EtcdCluster"
metadata:
  name: "default-etcd-cluster"
  ## Adding this annotation make this cluster managed by clusterwide operators
  ## namespaced operators ignore it
  annotations:
    etcd.database.coreos.com/scope: clusterwide
  namespace: etcd   # 此处的ns表示etcd集群部署在哪个ns下
spec:
  size: 3
  version: "v3.3.18"
  repository: registry.cn-shenzhen.aliyuncs.com/huweihuang/etcd
  pod:
    busyboxImage: registry.cn-shenzhen.aliyuncs.com/huweihuang/busybox:1.28.0-glibc
```

查看集群部署结果

```bash
$ kgpo -n etcd
NAME                              READY   STATUS    RESTARTS   AGE
default-etcd-cluster-b6phnpf8z8   1/1     Running   0          3m3s
default-etcd-cluster-hhgq4sbtgr   1/1     Running   0          109s
default-etcd-cluster-ttfh5fj92b   1/1     Running   0          2m29s
```

# 4. 访问etcd集群

查看service 

```bash
$ kgsvc -n etcd
NAME                          TYPE        CLUSTER-IP        EXTERNAL-IP   PORT(S)             AGE
default-etcd-cluster          ClusterIP   None              <none>        2379/TCP,2380/TCP   5m37s
default-etcd-cluster-client   ClusterIP   192.168.255.244   <none>        2379/TCP            5m37s
```

使用service地址访问

```bash
# 查看集群健康状态
$ ETCDCTL_API=3 etcdctl --endpoints 192.168.255.244:2379 endpoint health
192.168.255.244:2379 is healthy: successfully committed proposal: took = 1.96126ms

# 写数据
$ ETCDCTL_API=3 etcdctl --endpoints 192.168.255.244:2379 put foo bar
OK

# 读数据
$ ETCDCTL_API=3 etcdctl --endpoints 192.168.255.244:2379 get foo
foo
bar
```

# 5. 销毁etcd-operator

```bash
kubectl delete -f example/deployment.yaml
kubectl delete endpoints etcd-operator
kubectl delete crd etcdclusters.etcd.database.coreos.com
kubectl delete clusterrole etcd-operator
kubectl delete clusterrolebinding etcd-operator
```


参考：

- https://github.com/coreos/etcd-operator
- https://github.com/coreos/etcd-operator/blob/master/doc/user/install_guide.md
- https://github.com/coreos/etcd-operator/blob/master/doc/user/client_service.md
