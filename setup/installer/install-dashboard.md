---
title: "安装k8s dashboard"
weight: 5
catalog: true
date: 2022-10-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. 部署dashboard

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.6.0/aio/deploy/recommended.yaml
```

镜像： kubernetesui/dashboard:v2.5.0

默认端口：8443

登录页面需要填入token或kubeconfig

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1658371511/article/kubernetes/dashboard/dashboard_token.png)

## 2. 登录dashboard

### 2.1. 创建超级管理员

参考：[dashboard/creating-sample-user](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md)

创建dashboard-adminuser.yaml文件如下：

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
```

创建serviceaccount和ClusterRoleBinding，绑定cluster-admin的超级管理员的权限。

```bash
kubectl apply -f dashboard-adminuser.yaml t
```

创建用户

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

查询token

移除账号

```bash
kubectl -n kubernetes-dashboard delete serviceaccount admin-user
kubectl -n kubernetes-dashboard delete clusterrolebinding admin-user
```

### 2.2. 创建Namespace管理员

1、创建角色权限（role）

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: <namespace>
  name: <namespace>-admin-role
rules:
  - apiGroups:
    - '*'
    resources:
    - '*'
    verbs:
    - '*'
```

2、创建用户账号（ServiceAccount）

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <namespace>-admin-user
  namespace: <namespace>
```

3、创建角色绑定关系

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: <namespace>-admin-user
  namespace: <namespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: <namespace>-admin-role
subjects:
- kind: ServiceAccount
  name: <namespace>-admin-user
  namespace: <namespace>
```

4、生成token

```bash
kubectl -n <namespace> create token <ServiceAccount>
```

### 2.3. 创建只读账户

参考：

- [部署和访问 Kubernetes 仪表板（Dashboard） | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/web-ui-dashboard/)

- [dashboard/creating-sample-user.md at master · kubernetes/dashboard · GitHub](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md)

- [dashboard/docs/user/access-control at master · kubernetes/dashboard · GitHub](https://github.com/kubernetes/dashboard/tree/master/docs/user/access-control)
