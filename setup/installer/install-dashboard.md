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
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

镜像： kubernetesui/dashboard:v2.5.0

默认端口：8443

登录页面需要填入token或kubeconfig

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1658371511/article/kubernetes/dashboard/dashboard_token.png)

## 2. 登录dashboard

### 2.1. 创建超级管理员

参考：[dashboard/creating-sample-user](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md)

创建dashboard-adminuser.yaml文件如下：

> k8s 1.24+版本需要自行创建secret绑定serviceaccount

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
---
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-secret
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: "admin-user"   
type: kubernetes.io/service-account-token  
```

创建serviceaccount和ClusterRoleBinding，绑定cluster-admin的超级管理员的权限。

```bash
kubectl apply -f dashboard-adminuser.yaml 
```

创建用户token

```bash
kubectl -n kubernetes-dashboard create token admin-user --duration 8760h
```

或者通过secret查询token

```bash
kubectl get secret admin-user-secret -n kubernetes-dashboard -o jsonpath={".data.token"} | base64 -d
```

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

创建secret 可自动生成token

```bash
apiVersion: v1
kind: Secret
metadata:
  name: ${SecretName}
  namespace: ${ServiceAccountNS}
  annotations:
    kubernetes.io/service-account.name: "${ServiceAccountName}"   
type: kubernetes.io/service-account-token
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
kubectl -n <namespace> create token <ServiceAccount> --duration 8760h
```

或者通过上述secret中的token获得

```bash
kubectl get secret ${SecretName} -n ${ServiceAccountNS} -o jsonpath={".data.token"} | base64 -d
```

### 2.3. 创建只读账户

集群默认提供了几种命名空间级别的权限，分别设置ClusterRole: [admin, edit, view], 将授权设置为`ClusterRole`为`view`即可。

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: <namespace>-admin-user
  namespace: <namespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: <namespace>-admin-user
  namespace: <namespace>
```

# 3. 集成SSO登录

社区提供了添加`Authorization header`的方式来集成自定义的SSO登录。即在HTTP请求中增加**Header:  `Authorization: Bearer <token>`**。该操作可以通过apisix或Nginx等插件注入Header。





参考：

- [部署和访问 Kubernetes 仪表板（Dashboard） | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/web-ui-dashboard/)

- [dashboard/creating-sample-user.md at master · kubernetes/dashboard · GitHub](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md)

- [dashboard/docs/user/access-control at master · kubernetes/dashboard · GitHub](https://github.com/kubernetes/dashboard/tree/master/docs/user/access-control)
