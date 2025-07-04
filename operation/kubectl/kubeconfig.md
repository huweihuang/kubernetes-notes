---
title: "kubeconfig的使用"
weight: 6
catalog: true
date: 2023-4-19 20:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. kubeconfig说明

默认情况下，`kubectl` 在 `$HOME/.kube` 目录下查找名为 `config` 的文件。 你可以通过设置 `KUBECONFIG` 环境变量或者设置 [`--kubeconfig`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl/)参数来指定其他 kubeconfig 文件。

kubeconfig内容示例：

以下证书以文件的形式读取。

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: */ca.crt
    server: https://******
  name: demo
contexts:
- context:
    cluster: demo
    user: demo
  name: demo
current-context: demo
preferences: {}
users:
- name: demo
  user:
    client-certificate: */client.crt
    client-key: */client.key
```

# 2. 将 Kubeconfig 中的证书文件转为证书数据

## 2.1. 证书文件转为证书数据

如果需要将证书文件替换为证书数据格式，可以通过base64的命令解码成data数据，同时修改相应的参数。

获取证书文件的 base64 编码：

```bash
cat "证书文件" | base64
```

将输出结果的换行符去掉，填到对应证书的data中。

1. 将 `certificate-authority` 改为 `certificate-authority-data`，并且将 `*/ca.crt` 证书文件经 base64 编码后的字符串填入该位置。

2. 将 `client-certificate` 改为 `client-certificate-data`，并且将 `*/client.crt` 证书文件经 base64 编码后的字符串填入该位置。

3. 将 `client-key` 改为 `client-key-data`，并且将 `*/client.key` 证书文件 base64 编码后的字符串填入该位置。

例如：

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZADQFURS0tLS0tCk1JSUM1ekNDQWMrZ0F3SUJBZ0lCQVRBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwdGFXNXAKYTNWaVpVTkJNQjRYRFRJd01ESXhNREEwTURJMU1Wb1hEVE13TURJd09EQTBNREkxTVZvd0ZURVRNQkVHQTFVRQpBeE1LYldsdWFXdDFZbVZEUVRDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTUc1CjYwU0txcHVXeE1mWlVabmVFakM5bjFseHFQSzdUTlVQbzROejFWcWxaQkt6NzJDVVErZjBtVGNQLy9oS3BQUVAKaG9pNndyaXJRUmVERTErRFIrOTZHVDIrSGZ3L2VHQTI5ZmErNS80UG5PWlpTUEVpS3MxVVdhc0VqSDJVZG4xTwpEejVRZk1ESkFjZlBoTzV0eUZFaGZNa2hid0Y2QkJONnh5RmJJdXl4OThmZGx5SWJJUnpLSml6VWZQcUx2WUZoCmFQbjF4WFZyT2QyMnFtblgzL2VxZXM4aG51SmpJdlVPbWRDRlhjQVRYdE00Wmw2bERvWUs2VS9vaEFzM0x4VzAKWUV4ZkcxMzFXdjIrR0t4WWV2Q0FuMitSQ3NBdFpTZk9zcVljMmorYS9FODVqdzcySlFkNGd6eGlHMCszaU14WApWaGhpcWFrY1owZlRCc0FtZHY4Q0F3RUFBYU5DTUVBd0RnWURWUjBQQVFIL0JBUURBZ0trTUIwR0ExVWRKUVFXCk1CUUdDQ3NHQVFVRkJ3TUNCZ2dyQmdFRkJRY0RBVEFQQmdOVkhSTUJBZjhFQlRBREFRSC9NQTBHQ1NxR1NJYjMKRFFFQkN3VUFBNElCQVFDKzFuU2w0dnJDTEV6eWg0VWdXR3ZWSldtV2ltM2dBWFFJU1R2WG56NXZqOXE3Z0JYSwpCRVUyakVHTFF2UEJQWUZwUjhmZllCZCtqT2xtYS9IdU9ISmw0RUxhaHJKbnIwaU9YcytoeVlpV0ZUKzZ2R05RCmY4QnAvNTlkYzY1ejVVMnlUQjd4VkhMcGYzRTRZdUN2NmZhdy9PZTNUUzZUbThZdFBXREgxNDBOR2ZKMHlWRlYKSzZsQnl5THMwMzZzT1V5ZUJpcEduOUxyKytvb09mTVZIU2dpaEJlcEl3ZVVvYk05YU1ram1Hb2VjNk5HTUN3NwpkaFNWTmdMNGxMSnRvRktoVDdTZHFjMmk2SWlwbkJrdUlHUWRJUFliQnF6MkN5eVMyRkZmeEJsV2lmNmcxMTFTClphSUlpQ0lLbXNqeDJvTFBhOUdNSjR6bERNR1hLY1ZyNnhhVQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    server: https://******
  name: demo
contexts:
- context:
    cluster: demo
    user: demo
  name: demo
current-context: demo
preferences: {}
users:
- name: demo
  user:
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURBRENDQWVpZ0F3SUJBZ0lCQWpBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwdGFXNXAKYTNWaVpVTkJNQjRYRFRJd01ESXhNekV5TXpreU5sb1hEVEl4TURJeE16RXlNemt5Tmxvd01URVhNQlVHQTFVRQpDaE1PYzNsemRHVnRPbTFoYzNSbGNuTXhGakFVQmdOVkJBTVREVzFwYm1scmRXSmxMWFZ6WlhJd2dnRWlNQTBHCkNTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFDdEp5MThYOGVBaVlJc1g3Z0xQazBOZEFuRlNJU0kKeXNGMGIzS21CTk9VclRIcGtnaUFwRldmZDJaVXNZR3Iwd0VBL0FIWm9PMUxPUHdqYzEyb2o1bGIwWlNNWTlMaQpVeW9UQ3huREZIVDJIQnlPNCtGRk5pVCtXTU5FTURURWxERXhlano1WVIwb1pZVjN2V2Z5T3l2SlBna1dFU29IClVVcnVvQmRRbU5LUzhCeXhIUmFvcnFJUFRVRGkzUFJIbTlGZERKV1lNTWpnbDZmbmdHWkRQMnpjTlNFZjRGNzYKc2FUK0VhMU1kbjV5akRCNXczaHJvZXBBclc0QVUyR3NTRFZyTHY2UDFiSWV0RDdONjZrT1BBNklIUlRKbUNLLwp2aEJrbGVPMGFwcERzTERDT3hpMkc2Q1BRNDZVYVZUOEhZMk9sQU5nSmtRRDNwYjFXTnlhQlVpRkFnTUJBQUdqClB6QTlNQTRHQTFVZER3RUIvd1FFQXdJRm9EQWRCZ05WSFNVRUZqQVVCZ2dyQmdFRkJRY0RBUVlJS3dZQkJRVUgKQXdJd0RBWURWUjBUQVFIL0JBSXdBREFOQmdrcWhraUc5dzBCQVFzRkFBT0NBUUVBTHVrZ1dxWnRtbkZITlcxYgpqL012ekcxTmJyUEtWYXVobml5RzRWWnRZYzR1Uk5iSGhicEhEdThyamc2dVB1Y0xMdHAzblU2UGw4S2J2WFpiCmplNmJQR2xvV3VBcFIrVW9KRFQ2VEpDK2o2Qm5CSXpWQkNOL21lSWVPQ0hEK1k5L2dtbzRnd2Q4c2F3U0Z1bjMKZTFVekF2cHBwdTVZY05wcU92aUkxT2NjNGdxNTd2V1h1MFRIdUJkM0VtQ2JZRXUzYXhOL25ldnhOYnYxbDFRSQovSzRaOWw3MXFqaEp3SVlBaHUzek5pTWpCU1VTRjJkZnd2NmFnclhSUnN6b1Z4ejE5Mm9qM2pWU215cXZxeVFrCmZXckpsc3VhY1NDdTlKUE44OUQrVXkwVnZXZmhPdmp4cXVRSktwUW9hMzlQci81Q3YweXFKUkFIMkk5Wk1IZEYKNkJQRVBRPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
    client-key-data: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVQSLS0tLQpNSUlFcEFJQkFBS0NBUUVBclNjdGZGL0hnSW1DTEYrNEN6NU5EWFFKeFVpRWlNckJkRzl5cGdUVGxLMHg2WklJCmdLUlZuM2RtVkxHQnE5TUJBUHdCMmFEdFN6ajhJM05kcUkrWlc5R1VqR1BTNGxNcUV3c1p3eFIwOWh3Y2p1UGgKUlRZay9sakRSREEweEpReE1YbzgrV0VkS0dXRmQ3MW44anNyeVQ0SkZoRXFCMUZLN3FBWFVKalNrdkFjc1IwVwpxSzZpRDAxQTR0ejBSNXZSWFF5Vm1EREk0SmVuNTRCbVF6OXMzRFVoSCtCZStyR2svaEd0VEhaK2Nvd3dlY040CmE2SHFRSzF1QUZOaHJFZzFheTcrajlXeUhyUSt6ZXVwRGp3T2lCMFV5Wmdpdjc0UVpKWGp0R3FhUTdDd3dqc1kKdGh1Z2owT09sR2xVL0IwdGpwUURZQ1pFQTk2VzlWamNtZ1ZJaFFJREFRQUJBb0lCQUdDazVGTnVGaWtkRndYegphd01EZy9oRlV3ckZIZ3hIdHRCcFFBRi80aVF5d3hBT0RTYllFbDVPUTFSME90OFBoNWpvRDVSTHFRWjZTT2owCmhFc0gwMTRYVFNWS3RqTFNua0pBeU9GRWNyL0hFdjJDSFlNRzVJRCtSQWEwTFUrbk13bmRvMWpCcG9lY21uRXAKeTNHOUt3Ukkxc04xVXhNQWdhVk12NWFocGE2UzRTdENpalh3VGVVWUxpc1pSZGp5UGljUWlQN0xaSnhBcjRLTgpTUHlDNE1IZTJtV3F3cjM5cnBrMWZ3WkViMTRPMjR2Z3dMYmROTFJYdVhZSTdicEpOUGRJbEQvRExOQkJSL0FVCjhJYjNDaTZwZ2M4dFA4VzJCeW9TQUJVZUNpWDRFM21wQUttVytKbzFuU3FwQ1FnM2JGV0RpRjFrKzdEZjJZM3IKc09UT0srVUNnWUVBMTBEb3BtRVcrNnowanZadVFZdFlPWlVQQzZwV0dBaDFLWlVHZndYVWVLQ3dnNlNuQW9qRwpuMjR4bWJVdTlzRzBjd2syK0VVcXh3S2IrR2NJVTdyNVdOaUNXNVZYQzV5ZUp3OFZiMWtQekRzMSs4YzA4VjNhCkkzNHluOHpjZm1WTkZOUm1ZS1FMK1FGbnZ3ZXM4NFRleGVBb1hGY2FQcVZTNDNVV2JHRW02ZThDZ1lFQXplNFkKeUxYQ2pWNVppajFsUTdkQ2FweEQvL0dCT2JsemRocXRuSjl1OWxyVkQ4Y3RvUEVKYVkwVFFWc3FaNVhCdTNtVApLb0w4bmZjWHg4cWR3Z3gvZFRHa2c3d00rZFkrUTFuVDNOWnRFSVdVUkR3T0hLT1N1Tm5kdnU1a1Q4aXRrdHhhCktrYVlSMlNOT25iMlFzb1ZHa3F5OS9QK0xWL0FyeWdScmtaYXVNc0NnWUVBaGpUTkdUYzltaXNxeTV2d0FHTzkKM1NFSG9YRlJmbWgvakM2RFAxMUdMUE9iT21qRlREbzFCS0F5d3JBSm1RWUsyUkpzdUh4L2dGY3JJY1F6bCtqaQpvRGRWaDM1a0tEUTlFd00valE0TllIdW1XOVhITjVvWmNMbTFISmNnL3Bsd1pzVkxFNFFVaHVzT1lUZUs2TVgyCkU0OS8rcHJBSFVEOG5oNlpuWGN4U1BjQ2dZRUFub0lQcDZab1MwSjliMi9VbTJ2YS9vNnJ0TDBpOTlpc2JCTWEKNFR6RFAzTXBIc3owYlRZN1JYaW1ncDcybytiY3lUNUtMZVhISnB3RVBPL1R3SUs0Tk8veUxzZzN3TExOR0RCegphRC9Ra1hBUWNQazg3NFJrc2s1WVpkZS9kTDRHQk00QnhScXpxZmhXME5LeXVUUXRUQ0NGWTEvMm5OeGdSekp6CmNZNkwxRU1DZ1lCdXpHRkJVeXM4TFpHekFNTWdmN1VRQ0dVZERrT2dJRHdzd0dxVVlxQ2ZLcnlGYVdCOUJvSi8KMnJMVmVYNDVXTnFpa0tCMlgvckdRbGFIK25YalRBaDlpN0NrWGRySUQzeXA1cGJBa0VnYjg3dGo2Y3hONlBOcQo5cnhzOU1lR0NleFhsdjBkUUpMUkowNXU2OEVxYm44Q0RIOXFRSWZaTml0NXA0S0JFVkp3L1E9PQotLS0tLUVORCBSU0EgUFJJVkFURSBLRVktLS0tLQo=
```

## 2.2. 证书数据转成证书文件

```bash
grep 'certificate-authority-data' /etc/kubernetes/admin.conf | head -n 1 | awk '{print $2}' | base64 -d > ca.crt
grep 'client-key-data' /etc/kubernetes/admin.conf | head -n 1 | awk '{print $2}' | base64 -d > client.key
grep 'client-certificate-data' /etc/kubernetes/admin.conf | head -n 1 | awk '{print $2}' | base64 -d > client.crt
```

# 3. 生成集群级别的kubeconfig

## 3.1. 创建ServiceAccount

```bash
# 1. 创建用户
cat<<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: ${ServiceAccountNS}
  name: ${ServiceAccountName}
EOF

# 2. 创建Secret绑定ServiceAccount
# k8s 1.24后的版本不再自动生成secret，绑定后当删除ServiceAccount时会自动删除secret
cat<<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SecretName}
  namespace: ${ServiceAccountNS}
  annotations:
    kubernetes.io/service-account.name: "${ServiceAccountName}"   
type: kubernetes.io/service-account-token
EOF
```

## 3.2. 创建和绑定权限

如果不创建自定义权限，可以使用自带的ClusterRole: `cluster-admin/admin/edit/view`。如果需要生成集群admin的权限，可以绑定 `cluster-admin`的权限。建议权限授权时遵循最小权限原则。`即需要使用的权限授权，不需要使用的权限不授权，对于删除等敏感权限慎重授权`。

如果要创建自定义权限，使用`ClusterRole`和`ClusterRoleBinding`的对象。

- 只读权限：verbs: ["get","list","watch"]

- 可写权限：verbs: ["create","update","patch","delete","deletecollection"]

- 全部权限：verbs: ["*"]

```bash
# 3. 创建权限: 可以自定义权限，或者使用clusterrole: cluster-admin/admin/edit/view权限
# 只读权限：verbs: ["get","list","watch"]
# 可写权限：verbs: ["create","update","patch","delete","deletecollection"]
# 全部权限：verbs: ["*"]
cat<<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${ClusterRoleName}
rules:
- apiGroups: ["*"]
  resources: ["pods","deployments"]
  verbs: ["*"]
EOF

# 4. 绑定权限
cat<<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${ClusterRoleBindingName}
subjects:
- kind: ServiceAccount
  name: ${ServiceAccountName}
  namespace: ${ServiceAccountNS}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${ClusterRoleName}
EOF
```

## 3.3. 创建kubeconfig

```bash
# 5. 基于secret获取token
TOKEN=$(kubectl get secret ${SecretName} -n ${ServiceAccountNS} -o jsonpath={".data.token"} | base64 -d)

# 6. 创建kubeconfig文件
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config set-cluster ${KubeConfigCluster} \
  --server=https://${APISERVER} \
  --certificate-authority=${CaFilePath} \
  --embed-certs=true
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config set-credentials ${USER} --token=${TOKEN}
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config set-context ${USER}@${KubeConfigCluster} --cluster=${KubeConfigCluster} --user=${USER}
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config use-context ${USER}@${KubeConfigCluster}
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config view
```

# 4. 生成namespace的kubeconfig

## 4.1. 创建ServiceAccount

创建ServiceAccout同上，没有区别。

## 4.2. 创建和绑定权限

创建namespace级别的权限用`Role`和`RoleBinding`的对象。一个ServiceAccount可以绑定多个权限，可以通过创建`ClusterRoleBinding`或`RoleBinding`来实现对多个namespace的权限控制。

```bash
# 3. 创建权限: 可以自定义权限，或者使用clusterrole: admin/edit/view权限
cat<<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${USER_NAMESPACE}
  name: ${RoleName}
rules:
- apiGroups: ["*"] 
  resources: ["pods"]
  verbs: ["*"]
EOF

# 4. 绑定权限
cat<<EOF | kubectl apply -f -
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: ${RoleBindingName}
  namespace: ${USER_NAMESPACE}
subjects:
- kind: ServiceAccount
  name: ${ServiceAccountName}
  namespace: ${ServiceAccountNS}
roleRef:
  kind: Role
  name: ${RoleName}
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 4.3. 创建kubeconfig

```bash
# 5. 基于secret获取token
TOKEN=$(kubectl get secret ${SecretName} -n ${ServiceAccountNS} -o jsonpath={".data.token"} | base64 -d)

# 6. 创建kubeconfig文件
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config set-cluster ${KubeConfigCluster} \
  --server=https://${APISERVER} \
  --certificate-authority=${CaFilePath} \
  --embed-certs=true
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config set-credentials ${USER} --token=${TOKEN}
# 与cluster级别kubeconfig不同的增加了--namespace
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config set-context ${USER}@${KubeConfigCluster} \
  --cluster=${KubeConfigCluster} --user=${USER} --namespace=${USER_NAMESPACE}
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config use-context ${USER}@${KubeConfigCluster}
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config view
```

# 5. 创建token来访问apiserver

以上方式是通过创建`ServiceAccount`的`Secret`的方式来获取token，该token是永久生效的，如果要使token失效可以删除对应的`Secret`对象，

如果要使用指定过期期限的token权限，可以通过以下命令生成：

```bash
# 生成过期时间365天的token
TOKEN=$(kubectl -n ${NAMESPACE} create token ${USER} --duration 8760h)
kubectl --kubeconfig=${KubeDir}/${USER}.yaml config set-credentials ${USER} --token=${TOKEN}
```

参考：

- [如何将 Kubeconfig 中的证书文件转为证书数据 - CODING 帮助中心](https://coding.net/help/docs/cd/question/convert-certfile-to-certdata.html)
