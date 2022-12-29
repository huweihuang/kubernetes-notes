---
title: "使用 RBAC 鉴权"
weight: 1
catalog: true
date: 2022-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

> 本文基于https://kubernetes.io/zh-cn/docs/reference/access-authn-authz/rbac/ 整理。

## 1. RBAC介绍

基于角色的访问控制【Role-based access control (RBAC)】是一种基于组织中用户的角色来调节控制对 计算机或网络资源的访问的方法。

RBAC 鉴权机制使用 `rbac.authorization.k8s.io` [API 组](https://kubernetes.io/zh-cn/docs/concepts/overview/kubernetes-api/#api-groups-and-versioning)来驱动鉴权决定， 允许你通过 Kubernetes API 动态配置策略。

要启用 RBAC，在启动 [API 服务器](https://kubernetes.io/zh-cn/docs/concepts/overview/components/#kube-apiserver)时将 `--authorization-mode` 参数设置为一个逗号分隔的列表并确保其中包含 `RBAC`。

```shell
kube-apiserver --authorization-mode=Example,RBAC --<其他选项> --<其他选项>
```

## 2. API对象

|        | 集群范围               | namespace范围 |
| ------ | ------------------ | ----------- |
| 角色权限   | ClusterRole        | Role        |
| 角色权限绑定 | ClusterRoleBinding | RoleBinding |

**角色（权限）---角色绑定---用户（subject）**

## 3. Role

RBAC 的 **Role** 或 **ClusterRole** 中包含一组代表相关权限的规则。 这些权限是纯粹累加的（不存在拒绝某操作的规则）。

Role是针对指定namespace的权限，即创建的时候需要指定namespace。

示例：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: pod-reader
rules:
- apiGroups: [""] # "" 标明 core API 组
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
```

## 4. ClusterRole

ClusterRole用于指定集群内的资源：

- 集群范围资源（比如[节点（Node）](https://kubernetes.io/zh-cn/docs/concepts/architecture/nodes/)）

- 非资源端点（比如 `/healthz`）

- 跨名字空间访问的名字空间作用域的资源（如 访问所有namespace下的Pod）

示例：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  # "namespace" 被忽略，因为 ClusterRoles 不受名字空间限制
  name: secret-reader
rules:
- apiGroups: [""]
  # 在 HTTP 层面，用来访问 Secret 资源的名称为 "secrets"
  resources: ["secrets"]
  verbs: ["get", "watch", "list"]
```

## 5. RoleBinding

RoleBinding角色绑定（Role Binding）是将角色中定义的权限赋予一个或者一组用户。 它包含若干 **主体**（用户、组或服务账户）的列表和对这些主体所获得的角色的引用。 RoleBinding 在指定的名字空间中执行授权，而 ClusterRoleBinding 在集群范围执行授权。

字段说明：

- `subjects`：表示权限所授予的用户，包括`ServiceAccount`，`Group`，`User`。

- `roleRef`：表示权限对应的角色，包括`Role`，`ClusterRole`。

示例：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
# 此角色绑定允许 "jane" 读取 "default" 名字空间中的 Pod
# 你需要在该命名空间中有一个名为 “pod-reader” 的 Role
kind: RoleBinding
metadata:
  name: read-pods
  namespace: default
subjects:
# 你可以指定不止一个“subject（主体）”
- kind: ServiceAccount
  name: default # "name" 是区分大小写的
  apiGroup: rbac.authorization.k8s.io
roleRef:
  # "roleRef" 指定与某 Role 或 ClusterRole 的绑定关系
  kind: Role        # 此字段必须是 Role 或 ClusterRole
  name: pod-reader  # 此字段必须与你要绑定的 Role 或 ClusterRole 的名称匹配
  apiGroup: rbac.authorization.k8s.io
```

## 6. ClusterRoleBinding

要跨整个集群完成访问权限的授予，可以使用一个 ClusterRoleBinding。

示例：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
# 此集群角色绑定允许 “manager” 组中的任何人访问任何名字空间中的 Secret 资源
kind: ClusterRoleBinding
metadata:
  name: read-secrets-global
subjects:
- kind: Group
  name: manager      # 'name' 是区分大小写的
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

## 7. 默认角色权限

超级用户（Super-User）角色（`cluster-admin`）、 使用 ClusterRoleBinding 在集群范围内完成授权的角色（`cluster-status`）、 以及使用 RoleBinding 在特定名字空间中授予的角色（`admin`、`edit`、`view`）。

| 默认 ClusterRole    | 默认 ClusterRoleBinding | 描述                                                                                                                                                                                                                                                                                                              |
| ----------------- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **cluster-admin** | **system:masters** 组  | 允许超级用户在平台上的任何资源上执行所有操作。 当在 **ClusterRoleBinding** 中使用时，可以授权对集群中以及所有名字空间中的全部资源进行完全控制。 当在 **RoleBinding** 中使用时，可以授权控制角色绑定所在名字空间中的所有资源，包括名字空间本身。                                                                                                                                                                   |
| **admin**         | 无                     | 允许管理员访问权限，旨在使用 **RoleBinding** 在名字空间内执行授权。如果在 **RoleBinding** 中使用，则可授予对名字空间中的大多数资源的读/写权限， 包括创建角色和角色绑定的能力。 此角色不允许对资源配额或者名字空间本身进行写操作。 此角色也不允许对 Kubernetes v1.22+ 创建的 Endpoints 进行写操作。 更多信息参阅 [“Endpoints 写权限”小节](https://kubernetes.io/zh-cn/docs/reference/access-authn-authz/rbac/#write-access-for-endpoints)。 |
| **edit**          | 无                     | 允许对名字空间的大多数对象进行读/写操作。此角色不允许查看或者修改角色或者角色绑定。 不过，此角色可以访问 Secret，以名字空间中任何 ServiceAccount 的身份运行 Pod， 所以可以用来了解名字空间内所有服务账户的 API 访问级别。 此角色也不允许对 Kubernetes v1.22+ 创建的 Endpoints 进行写操作。 更多信息参阅 [“Endpoints 写操作”小节](https://kubernetes.io/zh-cn/docs/reference/access-authn-authz/rbac/#write-access-for-endpoints)。      |
| **view**          | 无                     | 允许对名字空间的大多数对象有只读权限。 它不允许查看角色或角色绑定。此角色不允许查看 Secrets，因为读取 Secret 的内容意味着可以访问名字空间中 ServiceAccount 的凭据信息，进而允许利用名字空间中任何 ServiceAccount 的身份访问 API（这是一种特权提升）。                                                                                                                                                           |

## 8. 给ServiceAccout授予权限

参考：

- [使用 RBAC 鉴权 | Kubernetes](https://kubernetes.io/zh-cn/docs/reference/access-authn-authz/rbac/)
