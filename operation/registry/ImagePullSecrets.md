[TOC]


> 本文介绍通过pod指定 ImagePullSecrets来拉取私有镜像仓库的镜像

## 1. 创建secret

secret是namespace级别的，创建时候需要指定namespace。

```bash
kubectl create secret docker-registry <name> --docker-server=DOCKER_REGISTRY_SERVER --docker-username=DOCKER_USER --docker-password=DOCKER_PASSWORD -n <NAMESPACE>
```

##  2. 添加ImagePullSecrets到serviceAccount

可以通过将ImagePullSecrets到serviceAccount的方式来自动给pod添加imagePullSecrets参数值。

serviceAccount同样是namespace级别，只对该namespace生效。

```bash
#kubectl get secrets -n dev
NAME                  TYPE                                  DATA   AGE
docker.xxxx.com         kubernetes.io/dockerconfigjson        1      6h23m
```

将ImagePullSecrets添加到serviceAccount对象中。

默认serviceAccount对象如下

```bash
#kubectl get serviceaccount default -n dev -o yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  creationTimestamp: "2020-02-27T03:30:38Z"
  name: default
  namespace: dev
  resourceVersion: "11651567"
  selfLink: /api/v1/namespaces/dev/serviceaccounts/default
  uid: 85bcdd31-5911-11ea-9429-6c92bf3b7c33
secrets:
- name: default-token-s7wfn
```

编辑或修改serviceAccount内容，增加imagePullSecrets字段。

```bash
imagePullSecrets:
- name: docker.xxxx.com
```

`kubectl edit serviceaccount default -n dev`

修改后内容为：

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  creationTimestamp: "2020-02-27T03:30:38Z"
  name: default
  namespace: dev
  resourceVersion: "11651567"
  selfLink: /api/v1/namespaces/dev/serviceaccounts/default
  uid: 85bcdd31-5911-11ea-9429-6c92bf3b7c33
secrets:
- name: default-token-s7wfn
imagePullSecrets:
- name: docker.xxxx.com
```

## 3. 创建带有imagePullSecrets的pod

如果已经执行了第二步操作，添加ImagePullSecrets到serviceAccount，则无需在pod中指定imagePullSecrets参数，默认会自动添加。

如果没有添加ImagePullSecrets到serviceAccount，则在pod中指定imagePullSecrets参数引用创建的镜像仓库的secret。

```yaml
spec:
  imagePullSecrets:
  - name: docker.xxxx.com
```

## 4. 说明

由于secret和serviceaccount对象是对namespace级别生效，因此不同的namespace需要再次创建和更新这两个对象。该场景适合不同用户具有独立的镜像仓库的密码，可以通过该方式创建不同的镜像密码使用的secret来拉取不同的镜像部署。



参考：

- https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#add-imagepullsecrets-to-a-service-account