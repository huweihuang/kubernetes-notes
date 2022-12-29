---
title: "安装APISIX"
weight: 1
catalog: true
date: 2022-09-10 10:50:57
subtitle:
header-img: 
tags:
- ApiSix
catagories:
- ApiSix
---

> 本文主要介绍通过k8s来部署apisix及apisix-ingress-controller，使用apisix作为k8s内Pod互相访问的网关。

## 1.  环境准备

### 1.1. 安装helm

参考：[Helm | 安装](https://helm.sh/zh/docs/intro/install/)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

helm添加仓库

```bash
helm repo add apisix https://charts.apiseven.com
helm repo update
```

### 1.2. 安装ETCD

可以提前准备好etcd环境，也可以使用apisix官方的helm命令安装，但是需要存在默认是storageclass来提供pv挂载。

## 2. 一键安装全部

```bash
helm install apisix apisix/apisix --set gateway.type=NodePort --set ingress-controller.enabled=true --namespace=apisix --create-namespace
```

或通过以下方式分别安装各组件。

## 3. 安装apisix

参考：[apisix-helm-chart/apisix.md at master · apache/apisix-helm-chart · GitHub](https://github.com/apache/apisix-helm-chart/blob/master/docs/en/latest/apisix.md)

### 3.1. 安装

```bash
helm install apisix apisix/apisix --namespace apisix --create-namespace  
```

卸载

```bash
helm uninstall apisix --namespace apisix
```

### 3.2. 修改配置

```bash
kubectl edit cm apisix-napisix
```

可选：

- 修改apisix端口。

- 修改etcd地址。

- 修改admin key值。

- 修改日志路径。

- 使用etcd存储stream配置或者静态文件存储stream配置

```bash
apisix:
  node_listen: 8000 # APISIX listening port
  config_center: etcd     # etcd: use etcd to store the config value
                          # yaml: fetch the config value from local yaml file `/your_path/conf/apisix.yaml`

etcd:
  host: "http://foo:2379" # etcd address

admin_key
  -
    name: "admin"
    key: newsupersecurekey  # 请修改 key 的值
    role: admin

nginx_config:
  error_log: /var/log/apisix_error.log
  http:
    access_log: /var/log/apisix_access.log
    access_log_format: "$time_iso8601|$remote_addr - $remote_user|$http_host|\"$request\"|$status|$body_bytes_sent|$request_time|\"$http_referer\"|\"$http_user_agent\"|$upstream_addr|$upstream_status|$upstream_response_time|\"$upstream_scheme://$upstream_host$upstream_uri\""


plugin_attr:
  log-rotate:
    interval: 3600    # rotate interval (unit: second)
    max_kept: 48     # max number of log files will be kept
    enable_compression: false
```

## 4. 安装apisix-ingress-controller

参考：[apisix-helm-chart/apisix-ingress-controller.md at master · apache/apisix-helm-chart · GitHub](https://github.com/apache/apisix-helm-chart/blob/master/docs/en/latest/apisix-ingress-controller.md)

### 4.1. 安装

```bash
helm install apisix-ingress-controller apisix/apisix-ingress-controller --namespace apisix --create-namespace
```

卸载

```bash
helm uninstall apisix-ingress-controller --namespace apisix
```

### 4.2. 修改配置

```bash
kubectl edit cm apisix-configmap -napisix
```

配置

- apisix地址

- apisix admin key

```bash
default_cluster_base_url: http://apisix-admin.apisix.svc.cluster.local:9180/apisix/admin
default_cluster_admin_key: "edd1c9f034335f136f87ad84b625c8f1"
```

## 5. 安装dashboard

### 5.1. 安装

```bash
helm repo add apisix https://charts.apiseven.com
helm repo update
helm install apisix-dashboard apisix/apisix-dashboard --namespace apisix --create-namespace 
```

卸载

```bash
helm uninstall apisix-dashboard --namespace apisix
```

### 5.2. 修改配置

```bash
kubectl edit cm apisix-dashboard -napisix
```

- 端口

- etcd地址

- 登录账号密码

```bash
data:
  conf.yaml: |-
    conf:
      listen:
        host: 0.0.0.0
        port: 9000
      etcd:
        prefix: "/apisix"
        endpoints:
          - 10.65.240.210:2379
      log:
        error_log:
          level: warn
          file_path: /dev/stderr
        access_log:
          file_path: /dev/stdout
    authentication:
      secert: secert
      expire_time: 3600
      users:
        - username: admin
          password: admin
```

## 6. 查看helm安装列表

```bash
# helm list -n apisix
NAME                NAMESPACE    REVISION    UPDATED                                    STATUS      CHART                     APP VERSION
apisix              apisix       1           2022-08-23 16:19:47.678174579 +0800 +08    deployed    apisix-0.11.0             2.15.0
apisix-dashboard    apisix       1           2022-08-23 20:36:37.55042356 +0800 +08     deployed    apisix-dashboard-0.6.0    2.13.0
```

参考：

- https://github.com/apache/apisix-helm-chart

- https://apisix.apache.org/zh/docs/apisix/installation-guide/

- https://github.com/apache/apisix-ingress-controller/blob/master/install.md
