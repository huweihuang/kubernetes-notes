# 1. 读取数据key

使用以下命令列出所有的key。

```bash
ETCDCTL_API=3 etcdctl --endpoints=<etcd-ip-1>:2379,<etcd-ip-2>:2379,<etcd-ip-3>:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt  --key=/etc/kubernetes/pki/apiserver-etcd-client.key  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt get / --prefix --keys-only
```

参数说明：

```bash
  --cacert=""				verify certificates of TLS-enabled secure servers using this CA bundle
  --cert=""					identify secure client using this TLS certificate file
  --key=""					identify secure client using this TLS key file
  --endpoints=[127.0.0.1:2379]		gRPC endpoints
```

可以使用alias来重命名etcdctl一串的命令

```bash
alias ectl='ETCDCTL_API=3 etcdctl --endpoints=<etcd-ip-1>:2379,<etcd-ip-2>:2379,<etcd-ip-3>:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt  --key=/etc/kubernetes/pki/apiserver-etcd-client.key  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt'
```

# 2. 集群数据

## 2.1. node

```bash
/registry/minions/<node-ip-1>
/registry/minions/<node-ip-2>
/registry/minions/<node-ip-3>
```

其他信息：

```bash
/registry/leases/kube-node-lease/<node-ip-1>
/registry/leases/kube-node-lease/<node-ip-2>
/registry/leases/kube-node-lease/<node-ip-3>

/registry/masterleases/<node-ip-2>
/registry/masterleases/<node-ip-3>
```

# 3. k8s对象数据

k8s对象数据的格式

## 3.1. namespace

```bash
/registry/namespaces/default
/registry/namespaces/game
/registry/namespaces/kube-node-lease
/registry/namespaces/kube-public
/registry/namespaces/kube-system
```

## 3.2. namespace级别对象

```bash
/registry/{resource}/{namespace}/{resource_name}
```

以下以常见k8s对象为例：

```bash
# deployment
/registry/deployments/default/game-2048
/registry/deployments/kube-system/prometheus-operator

# replicasets
/registry/replicasets/default/game-2048-c7d589ccf

# pod
/registry/pods/default/game-2048-c7d589ccf-8lsbw

# statefulsets
/registry/statefulsets/kube-system/prometheus-k8s

# daemonsets
/registry/daemonsets/kube-system/kube-proxy

# secrets
/registry/secrets/default/default-token-tbfmb

# serviceaccounts
/registry/serviceaccounts/default/default
```

**service**

```bash
# service
/registry/services/specs/default/game-2048

# endpoints
/registry/services/endpoints/default/game-2048
```

# 4. 读取数据value

由于k8s默认etcd中的数据是通过protobuf格式存储，因此看到的key和value的值是一串字符串。

> alias ectl='ETCDCTL_API=3 etcdctl --endpoints=<etcd-ip-1>:2379,<etcd-ip-2>:2379,<etcd-ip-3>:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt  --key=/etc/kubernetes/pki/apiserver-etcd-client.key  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt'

```bash
# ectl get /registry/namespaces/test -w json |jq
{
  "header": {
    "cluster_id": 12113422651334595000,
    "member_id": 8381627376898157000,
    "revision": 12321629,
    "raft_term": 20
  },
  "kvs": [
    {
      "key": "L3JlZ2lzdHJ5L25hbWVzcGFjZXMvdGVzdA==",
      "create_revision": 11670741,
      "mod_revision": 11670741,
      "version": 1,
      "value": "azhzAAoPCgJ2MRIJTmFtZXNwYWNlElwKQgoEdGVzdBIAGgAiACokYWM1YmJjOTQtNTkxZi0xMWVhLWJiOTQtNmM5MmJmM2I3NmI1MgA4AEIICJuf3fIFEAB6ABIMCgprdWJlcm5ldGVzGggKBkFjdGl2ZRoAIgA="
    }
  ],
  "count": 1
}
```

其中key可以通过base64解码出来

```bash
echo "L3JlZ2lzdHJ5L25hbWVzcGFjZXMvdGVzdA==" | base64 --decode

# output
/registry/namespaces/test
```

value是值可以通过安装[etcdhelper](https://github.com/openshift/origin/tree/master/tools/etcdhelper)工具解析出来。

> alias ehelper='etcdhelper -key /etc/kubernetes/pki/apiserver-etcd-client.key -cert /etc/kubernetes/pki/apiserver-etcd-client.crt -cacert /etc/kubernetes/pki/etcd/ca.crt'

```bash
# ehelper get /registry/namespaces/test
/v1, Kind=Namespace
{
  "kind": "Namespace",
  "apiVersion": "v1",
  "metadata": {
    "name": "test",
    "uid": "ac5bbc94-591f-11ea-bb94-6c92bf3b76b5",
    "creationTimestamp": "2020-02-27T05:11:55Z"
  },
  "spec": {
    "finalizers": [
      "kubernetes"
    ]
  },
  "status": {
    "phase": "Active"
  }
}
```

# 5. 注意事项

- 由于k8s的etcd数据为了性能考虑，默认通过`protobuf`格式存储，不要通过手动的方式去修改或添加k8s数据。
- 不推荐使用json格式存储etcd数据，如果需要json格式，可以使用`--storage-media-type=application/json`参数存储，参考：https://github.com/kubernetes/kubernetes/issues/44670

# 6. 快捷命令

由于etcdctl的命令需要添加很多认证参数和endpoints的参数，因此可以使用别名的方式来简化命令。

```bash
# etcdctl 
alias ectl='ETCDCTL_API=3 etcdctl --endpoints=<etcd-ip-1>:2379,<etcd-ip-2>:2379,<etcd-ip-3>:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt  --key=/etc/kubernetes/pki/apiserver-etcd-client.key  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt'

# etcdhelper
alias ehelper='etcdhelper -key /etc/kubernetes/pki/apiserver-etcd-client.key -cert /etc/kubernetes/pki/apiserver-etcd-client.crt -cacert /etc/kubernetes/pki/etcd/ca.crt'
```

## 6.1. etcdhelper的使用

`etcdhelper`文档参考：https://github.com/openshift/origin/tree/master/tools/etcdhelper

```bash
# 必要的认证参数
-key - points to master.etcd-client.key
-cert - points to master.etcd-client.crt
-cacert - points to ca.crt

# 命令操作参数
ls - list all keys starting with prefix
get - get the specific value of a key
dump - dump the entire contents of the etcd
```

示例

```bash
$ ehelper ls /registry/leases/
/registry/leases/kube-node-lease/<ip-1>
/registry/leases/kube-node-lease/<ip-2>
/registry/leases/kube-node-lease/<ip-3>

$ ehelper get <key>
```

# 7. RBAC

附RBAC相关的key。

**clusterrolebindings**

```bash
/registry/clusterrolebindings/cluster-admin
/registry/clusterrolebindings/flannel
/registry/clusterrolebindings/galaxy
/registry/clusterrolebindings/helm
/registry/clusterrolebindings/kube-state-metrics
/registry/clusterrolebindings/kubeadm:kubelet-bootstrap
/registry/clusterrolebindings/kubeadm:node-autoapprove-bootstrap
/registry/clusterrolebindings/kubeadm:node-autoapprove-certificate-rotation
/registry/clusterrolebindings/kubeadm:node-proxier
/registry/clusterrolebindings/lbcf-controller
/registry/clusterrolebindings/prometheus-k8s
/registry/clusterrolebindings/prometheus-operator
/registry/clusterrolebindings/system:aws-cloud-provider
/registry/clusterrolebindings/system:basic-user
/registry/clusterrolebindings/system:controller:attachdetach-controller
/registry/clusterrolebindings/system:controller:certificate-controller
/registry/clusterrolebindings/system:controller:clusterrole-aggregation-controller
/registry/clusterrolebindings/system:controller:cronjob-controller
/registry/clusterrolebindings/system:controller:daemon-set-controller
/registry/clusterrolebindings/system:controller:deployment-controller
/registry/clusterrolebindings/system:controller:disruption-controller
/registry/clusterrolebindings/system:controller:endpoint-controller
/registry/clusterrolebindings/system:controller:expand-controller
/registry/clusterrolebindings/system:controller:generic-garbage-collector
/registry/clusterrolebindings/system:controller:horizontal-pod-autoscaler
/registry/clusterrolebindings/system:controller:job-controller
/registry/clusterrolebindings/system:controller:namespace-controller
/registry/clusterrolebindings/system:controller:node-controller
/registry/clusterrolebindings/system:controller:persistent-volume-binder
/registry/clusterrolebindings/system:controller:pod-garbage-collector
/registry/clusterrolebindings/system:controller:pv-protection-controller
/registry/clusterrolebindings/system:controller:pvc-protection-controller
/registry/clusterrolebindings/system:controller:replicaset-controller
/registry/clusterrolebindings/system:controller:replication-controller
/registry/clusterrolebindings/system:controller:resourcequota-controller
/registry/clusterrolebindings/system:controller:route-controller
/registry/clusterrolebindings/system:controller:service-account-controller
/registry/clusterrolebindings/system:controller:service-controller
/registry/clusterrolebindings/system:controller:statefulset-controller
/registry/clusterrolebindings/system:controller:ttl-controller
/registry/clusterrolebindings/system:coredns
/registry/clusterrolebindings/system:discovery
/registry/clusterrolebindings/system:kube-controller-manager
/registry/clusterrolebindings/system:kube-dns
/registry/clusterrolebindings/system:kube-scheduler
/registry/clusterrolebindings/system:node
/registry/clusterrolebindings/system:node-proxier
/registry/clusterrolebindings/system:public-info-viewer
/registry/clusterrolebindings/system:volume-scheduler
```

**clusterroles**

```bash
/registry/clusterroles/admin
/registry/clusterroles/cluster-admin
/registry/clusterroles/edit
/registry/clusterroles/flannel
/registry/clusterroles/kube-state-metrics
/registry/clusterroles/lbcf-controller
/registry/clusterroles/prometheus-k8s
/registry/clusterroles/prometheus-operator
/registry/clusterroles/system:aggregate-to-admin
/registry/clusterroles/system:aggregate-to-edit
/registry/clusterroles/system:aggregate-to-view
/registry/clusterroles/system:auth-delegator
/registry/clusterroles/system:aws-cloud-provider
/registry/clusterroles/system:basic-user
/registry/clusterroles/system:certificates.k8s.io:certificatesigningrequests:nodeclient
/registry/clusterroles/system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
/registry/clusterroles/system:controller:attachdetach-controller
/registry/clusterroles/system:controller:certificate-controller
/registry/clusterroles/system:controller:clusterrole-aggregation-controller
/registry/clusterroles/system:controller:cronjob-controller
/registry/clusterroles/system:controller:daemon-set-controller
/registry/clusterroles/system:controller:deployment-controller
/registry/clusterroles/system:controller:disruption-controller
/registry/clusterroles/system:controller:endpoint-controller
/registry/clusterroles/system:controller:expand-controller
/registry/clusterroles/system:controller:generic-garbage-collector
/registry/clusterroles/system:controller:horizontal-pod-autoscaler
/registry/clusterroles/system:controller:job-controller
/registry/clusterroles/system:controller:namespace-controller
/registry/clusterroles/system:controller:node-controller
/registry/clusterroles/system:controller:persistent-volume-binder
/registry/clusterroles/system:controller:pod-garbage-collector
/registry/clusterroles/system:controller:pv-protection-controller
/registry/clusterroles/system:controller:pvc-protection-controller
/registry/clusterroles/system:controller:replicaset-controller
/registry/clusterroles/system:controller:replication-controller
/registry/clusterroles/system:controller:resourcequota-controller
/registry/clusterroles/system:controller:route-controller
/registry/clusterroles/system:controller:service-account-controller
/registry/clusterroles/system:controller:service-controller
/registry/clusterroles/system:controller:statefulset-controller
/registry/clusterroles/system:controller:ttl-controller
/registry/clusterroles/system:coredns
/registry/clusterroles/system:csi-external-attacher
/registry/clusterroles/system:csi-external-provisioner
/registry/clusterroles/system:discovery
/registry/clusterroles/system:heapster
/registry/clusterroles/system:kube-aggregator
/registry/clusterroles/system:kube-controller-manager
/registry/clusterroles/system:kube-dns
/registry/clusterroles/system:kube-scheduler
/registry/clusterroles/system:kubelet-api-admin
/registry/clusterroles/system:node
/registry/clusterroles/system:node-bootstrapper
/registry/clusterroles/system:node-problem-detector
/registry/clusterroles/system:node-proxier
/registry/clusterroles/system:persistent-volume-provisioner
/registry/clusterroles/system:public-info-viewer
/registry/clusterroles/system:volume-scheduler
/registry/clusterroles/view
```

**rolebindings**

```bash
/registry/rolebindings/kube-public/kubeadm:bootstrap-signer-clusterinfo
/registry/rolebindings/kube-public/system:controller:bootstrap-signer
/registry/rolebindings/kube-system/kube-proxy
/registry/rolebindings/kube-system/kube-state-metrics
/registry/rolebindings/kube-system/kubeadm:kubeadm-certs
/registry/rolebindings/kube-system/kubeadm:kubelet-config-1.14
/registry/rolebindings/kube-system/kubeadm:nodes-kubeadm-config
/registry/rolebindings/kube-system/system::extension-apiserver-authentication-reader
/registry/rolebindings/kube-system/system::leader-locking-kube-controller-manager
/registry/rolebindings/kube-system/system::leader-locking-kube-scheduler
/registry/rolebindings/kube-system/system:controller:bootstrap-signer
/registry/rolebindings/kube-system/system:controller:cloud-provider
/registry/rolebindings/kube-system/system:controller:token-cleaner
```

**roles**

```bash
/registry/roles/kube-public/kubeadm:bootstrap-signer-clusterinfo
/registry/roles/kube-public/system:controller:bootstrap-signer
/registry/roles/kube-system/extension-apiserver-authentication-reader
/registry/roles/kube-system/kube-proxy
/registry/roles/kube-system/kube-state-metrics-resizer
/registry/roles/kube-system/kubeadm:kubeadm-certs
/registry/roles/kube-system/kubeadm:kubelet-config-1.14
/registry/roles/kube-system/kubeadm:nodes-kubeadm-config
/registry/roles/kube-system/system::leader-locking-kube-controller-manager
/registry/roles/kube-system/system::leader-locking-kube-scheduler
/registry/roles/kube-system/system:controller:bootstrap-signer
/registry/roles/kube-system/system:controller:cloud-provider
/registry/roles/kube-system/system:controller:token-cleaner
```



参考：

- https://github.com/etcd-io/etcd/tree/master/etcdctl
- https://github.com/openshift/origin/tree/master/tools/etcdhelper
- [using-etcdctl-to-access-kubernetes-data](https://jimmysong.io/kubernetes-handbook/guide/using-etcdctl-to-access-kubernetes-data.html)
- [如何读取Kubernetes存储在etcd上的数据](https://int32bit.me/2019/12/01/如何读取Kubernetes存储在etcd上的数据/)
- https://github.com/kubernetes/kubernetes/issues/44670

