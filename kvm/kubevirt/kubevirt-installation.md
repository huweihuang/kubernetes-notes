# 1. 安装kubevirt

## 1.1. 修改镜像仓库

针对私有环境，需要将所需镜像上传到自己的镜像仓库中。

涉及的镜像组件有

```
virt-operator
virt-api
virt-controller
virt-launcher
```

重命名镜像脚本如下:

```bash
#!/bin/bash

# kubevirt组件版本
version=$1

# 私有镜像仓库
registry=$2

# 私有镜像仓库的namespace
namespace=$3

kubevirtRegistry="quay.io/kubevirt"

readonly APPLIST=(
    virt-operator
    virt-api
    virt-controller
    virt-launcher
)

for app in "${APPLIST[@]}"; do
    # 拉取镜像
    docker pull ${kubevirtRegistry}/${app}:${version}
    # 重命名
    docker tag ${kubevirtRegistry}/${app}:${version} ${registry}/${namespace}/${app}:${version}
    # 推送镜像
    docker push ${registry}/${namespace}/${app}:${version}
done

echo "重新命名成功"
```

## 1.2. 部署virt-operator

通过kubevirt operator安装kubevirt相关组件，选择指定版本，下载`kubevirt-operator.yaml`和`kubevirt-cr.yaml`文件，并创建k8s相关对象。

> 如果是私有镜像仓库，则需要将kubevirt-operator.yaml文件中镜像的名字替换为私有镜像仓库的地址，并提前按步骤1推送所需镜像到私有镜像仓库。

```bash
# Pick an upstream version of KubeVirt to install
$ export RELEASE=v0.52.0
# Deploy the KubeVirt operator
$ kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
# Create the KubeVirt CR (instance deployment request) which triggers the actual installation
$ kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-cr.yaml
# wait until all KubeVirt components are up
$ kubectl -n kubevirt wait kv kubevirt --for condition=Available
```

## 1.3. 部署virtctl

virtctl用来启动和关闭虚拟机。

```bash
VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.observedKubeVirtVersion}")
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/') || windows-amd64.exe
echo ${ARCH}
curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH}
chmod +x virtctl
sudo install virtctl /usr/local/bin
```

# 2. kubevirt部署产物

通过手动部署virt-operator，会自动部署以下组件

| 组件              | 部署方式       | 副本数 |
| --------------- | ---------- | --- |
| virt-api        | deployment | 2   |
| virt-controller | deployment | 2   |
| virt-handler    | daemonset  | -   |

具体参考:

```bash
#kg all -n kubevirt
NAME                                   READY   STATUS    RESTARTS   AGE
pod/virt-api-5fb5cffb7f-hgjjh          1/1     Running   0          23h
pod/virt-api-5fb5cffb7f-jcp7x          1/1     Running   0          23h
pod/virt-controller-844cd4f58c-h8vsx   1/1     Running   0          23h
pod/virt-controller-844cd4f58c-vlxqs   1/1     Running   0          23h
pod/virt-handler-lb5ft                 1/1     Running   0          23h
pod/virt-handler-mtr4d                 1/1     Running   0          22h
pod/virt-handler-sxd2t                 1/1     Running   0          23h
pod/virt-operator-8595f577cd-b9txg     1/1     Running   0          23h
pod/virt-operator-8595f577cd-p2f69     1/1     Running   0          23h

NAME                                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/kubevirt-operator-webhook     ClusterIP   10.254.159.81    <none>        443/TCP   23h
service/kubevirt-prometheus-metrics   ClusterIP   10.254.7.231     <none>        443/TCP   23h
service/virt-api                      ClusterIP   10.254.244.139   <none>        443/TCP   23h

NAME                          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
daemonset.apps/virt-handler   3         3         3       3            3           kubernetes.io/os=linux   23h

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/virt-api          2/2     2            2           23h
deployment.apps/virt-controller   2/2     2            2           23h
deployment.apps/virt-operator     2/2     2            2           23h

NAME                                         DESIRED   CURRENT   READY   AGE
replicaset.apps/virt-api-5fb5cffb7f          2         2         2       23h
replicaset.apps/virt-controller-844cd4f58c   2         2         2       23h
replicaset.apps/virt-operator-8595f577cd     2         2         2       23h

NAME                            AGE   PHASE
kubevirt.kubevirt.io/kubevirt   23h   Deployed
```

# 3. 创建虚拟机

通过vm.yaml创建虚拟机

```bash
# 下载vm.yaml
wget https://kubevirt.io/labs/manifests/vm.yaml
# 创建虚拟机
kubectl apply -f https://kubevirt.io/labs/manifests/vm.yaml
```

vm.yaml文件

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: testvm
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/size: small
        kubevirt.io/domain: testvm
    spec:
      domain:
        devices:
          disks:
            - name: containerdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          interfaces:
          - name: default
            masquerade: {}
        resources:
          requests:
            memory: 64M
      networks:
      - name: default
        pod: {}
      volumes:
        - name: containerdisk
          containerDisk:
            image: quay.io/kubevirt/cirros-container-disk-demo
        - name: cloudinitdisk
          cloudInitNoCloud:
            userDataBase64: SGkuXG4=
```

查看虚拟机

```bash
kubectl get vms
kubectl get vms -o yaml testvm
```

启动或暂停虚拟机

```bash
# 启动虚拟机
virtctl start testvm
# 关闭虚拟机
virtctl stop testvm
# 进入虚拟机
virtctl console testvm
```

删除虚拟机

```bash
kubectl delete vm testvm
```

参考：

- [Installation - KubeVirt User-Guide](http://kubevirt.io/user-guide/operations/installation/#installing-kubevirt-on-kubernetes)
- [KubeVirt quickstart with Minikube | KubeVirt.io](https://kubevirt.io/quickstart_minikube/)
- [Use KubeVirt | KubeVirt.io](https://kubevirt.io/labs/kubernetes/lab1.html)
