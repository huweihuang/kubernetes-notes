---
title: "创建路由"
weight: 2
catalog: true
date: 2022-09-10 10:50:57
subtitle:
header-img: 
tags:
- ApiSix
catagories:
- ApiSix
---

本文主要介绍三种方式来创建apisix的路由规则。需要提前创建好k8s service作为路由的后端标识来关联`endpoints`。

## 0. 创建k8s service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {APP}-service
  namespace: {NAMESPACE}
spec:
  selector:
    k8s-app: {APP}
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
```

路由规则主要包括：

- hosts：域名

- paths：访问路径

- backends:
  
  - serviceName
  
  - servicePort

## 1. 使用ApisixRoute创建路由规则

使用`ApisixRoute`自定义CRD创建路由规则，具体参考：[reference](https://github.com/apache/apisix-ingress-controller/blob/master/samples/deploy/crd/v1/ApisixRoute.yaml)。

示例：

```yaml
# httpbin-route.yaml
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  name: httpserver-route
spec:
  http:
  - name: rule1
    match:
      hosts:
      - local.httpbin.org
      paths:
      - /*
    backends:
       - serviceName: httpbin
         servicePort: 80
```

在k8s中创建ApisixRoute。

```bash
kubectl apply -f httpbin-route.yaml
```

## 2. 使用ingress创建路由规则

使用k8s ingress来创建路由规则，示例如下：

```yaml
# httpbin-ingress.yaml
# Note use apiVersion is networking.k8s.io/v1, so please make sure your
# Kubernetes cluster version is v1.19.0 or higher.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpserver-ingress
spec:
  # apisix-ingress-controller is only interested in Ingress
  # resources with the matched ingressClass name, in our case,
  # it's apisix.
  ingressClassName: apisix
  rules:
  - host: local.httpbin.org
    http:
      paths:
      - backend:
          service:
            name: httpbin
            port:
              number: 80
        path: /
        pathType: Prefix
```

创建k8s ingress。

```bash
kubectl apply -f httpbin-ingress.yaml
```

## 3. 使用Admin API创建路由规则

直接调用Admin API或者使用dashboard创建路由规则。

### 3.1. 一键创建路由和upstream

```bash
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/anything/*",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

### 3.2. 分开创建路由和upstream

> 推荐使用分开创建路由和upstream。

创建upstream

```bash
curl "http://127.0.0.1:9180/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "httpbin.org:80": 1
  }
}'
```

创建路由绑定upstream

```bash
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uris": ["/get","/list"],
  "host": "httpbin.org",
  "upstream_id": "1"
}'
```

删除upstream

DELETE /apisix/admin/upstreams/{id}

删除route

DELETE /apisix/admin/routes/{id}

## 4. 验证路由规则

基于上述的方式，apisix-ingress-controller会调用apisix admin的接口自动创建`routes`和`upstreams`两个信息存入etcd，通过业务域名访问apisix就可以访问到具体的pod。

**服务调用**

将业务域名解析到apisix的IP上（如果是物理机部署可以是VIP，或者k8s部署的clusterIP）。

访问业务域名：

```bash
curl -v http://local.httpbin.org
```

## 5. 查看etcd中的路由规则

```bash
etcdctl get /apisix --prefix
```

### 5.1. routes

/apisix/routes/

通过ingress创建的routes

```json
{
    "host": "local.httpbin.org",
    "create_time": 1661251916,
    "name": "ing_default_httpserver-ingress_37a4f3ae",
    "status": 1,
    "uris": [
        "\/",
        "\/*"
    ],
    "upstream_id": "5ce57b8e",
    "labels": {
        "managed-by": "apisix-ingress-controller"
    },
    "priority": 0,
    "desc": "Created by apisix-ingress-controller, DO NOT modify it manually",
    "update_time": 1661397119,
    "id": "148730bb"
}
```

通过ApisixRoute创建的routes

```json
{
    "priority": 0,
    "create_time": 1661397584,
    "name": "default_httpserver-route_rule1",
    "status": 1,
    "uris": [
        "\/*"
    ],
    "upstream_id": "5ce57b8e",
    "hosts": [
        "local.httpbin.org"
    ],
    "labels": {
        "managed-by": "apisix-ingress-controller"
    },
    "desc": "Created by apisix-ingress-controller, DO NOT modify it manually",
    "update_time": 1661397584,
    "id": "add8e28c"
}
```

### 5.2. upstreams

/apisix/upstreams/5ce57b8e

相同的backend，使用ingress或ApisixRoute创建后生成的`upstreams`相同。

```json
{
    "scheme": "http",
    "pass_host": "pass",
    "name": "default_httpbin_80",
    "nodes": [
        {
            "host": "10.244.3.167",
            "priority": 0,
            "port": 80,
            "weight": 100
        }
    ],
    "type": "roundrobin",
    "labels": {
        "managed-by": "apisix-ingress-controller"
    },
    "hash_on": "vars",
    "create_time": 1661251916,
    "id": "5ce57b8e",
    "update_time": 1661397584,
    "desc": "Created by apisix-ingress-controller, DO NOT modify it manually"
}
```

参考：

- https://apisix.apache.org/zh/docs/ingress-controller/getting-started/

- https://apisix.apache.org/zh/docs/ingress-controller/tutorials/index/

- https://apisix.apache.org/zh/docs/ingress-controller/tutorials/proxy-the-httpbin-service/

- https://apisix.apache.org/zh/docs/ingress-controller/tutorials/proxy-the-httpbin-service-with-ingress/
