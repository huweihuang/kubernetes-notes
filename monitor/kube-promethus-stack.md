---
title: "kube-prometheus-stack的使用"
weight: 1
catalog: true
date: 2023-05-18 10:50:57
subtitle:
header-img: 
tags:
- Monitor
catagories:
- Monitor
---

# 1. kube-prometheus-stack简介

kube-prometheus-stack是prometheus监控k8s集群的套件，可以通过helm一键安装，同时带有监控的模板。

各组件包括

- grafana
- kube-state-metrics
- prometheus
- alertmanager
- node-exporter

# 2. 安装kube-prometheus-stack

执行以下命令

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n prometheus
```

示例：

```bash
# helm install kube-prometheus-stack  prometheus-community/kube-prometheus-stack -n prometheus
NAME: kube-prometheus-stack
LAST DEPLOYED: Wed May 17 17:12:24 2023
NAMESPACE: prometheus
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace prometheus get pods -l "release=kube-prometheus-stack"

Visit https://github.com/prometheus-operator/kube-prometheus for instructions on how to create & configure Alertmanager and Prometheus instances using the Operator.
```

# 3. 查看安装结果

- deployment

  - kube-prometheus-stack-grafana 
  - kube-prometheus-stack-kube-state-metrics
  - kube-prometheus-stack-operator 

- statefulset

  - prometheus-kube-prometheus-stack-prometheus 
  - alertmanager-kube-prometheus-stack-alertmanager

- daemonset

  - kube-prometheus-stack-prometheus-node-exporter

```bash
# kg all -n prometheus
NAME                                                            READY   STATUS    RESTARTS   AGE
pod/alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          9m34s
pod/kube-prometheus-stack-grafana-5bb7689dc8-lgrws              3/3     Running   0          9m35s
pod/kube-prometheus-stack-kube-state-metrics-5d6578867c-25xbq   1/1     Running   0          9m35s
pod/kube-prometheus-stack-operator-9c5fbdc68-nrn7h              1/1     Running   0          9m35s
pod/kube-prometheus-stack-prometheus-node-exporter-8ghd8        1/1     Running   0          48s
pod/kube-prometheus-stack-prometheus-node-exporter-brtp9        1/1     Running   0          29s
pod/kube-prometheus-stack-prometheus-node-exporter-n4kdp        1/1     Running   0          88s
pod/kube-prometheus-stack-prometheus-node-exporter-ttksv        1/1     Running   0          35s
pod/prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          9m34s

NAME                                                     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
service/alertmanager-operated                            ClusterIP   None             <none>        9093/TCP,9094/TCP,9094/UDP   9m34s
service/kube-prometheus-stack-alertmanager               ClusterIP   10.99.108.180    <none>        9093/TCP                     9m36s
service/kube-prometheus-stack-grafana                    ClusterIP   10.110.62.28     <none>        80/TCP                       9m36s
service/kube-prometheus-stack-kube-state-metrics         ClusterIP   10.110.105.139   <none>        8080/TCP                     9m35s
service/kube-prometheus-stack-operator                   ClusterIP   10.96.147.204    <none>        443/TCP                      9m36s
service/kube-prometheus-stack-prometheus                 ClusterIP   10.98.235.203    <none>        9090/TCP                     9m36s
service/kube-prometheus-stack-prometheus-node-exporter   ClusterIP   10.105.99.77     <none>        9100/TCP                     9m36s
service/prometheus-operated                              ClusterIP   None             <none>        9090/TCP                     9m34s

NAME                                                            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/kube-prometheus-stack-prometheus-node-exporter   4         4         4       4            4           <none>          9m35s

NAME                                                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kube-prometheus-stack-grafana              1/1     1            1           9m35s
deployment.apps/kube-prometheus-stack-kube-state-metrics   1/1     1            1           9m35s
deployment.apps/kube-prometheus-stack-operator             1/1     1            1           9m35s


NAME                                                               READY   AGE
statefulset.apps/alertmanager-kube-prometheus-stack-alertmanager   1/1     9m34s
statefulset.apps/prometheus-kube-prometheus-stack-prometheus       1/1     9m34s
```

# 4. 登录grafana

默认账号密码

```bash
账号：admin
密码：prom-operator
```

默认账号密码位于secret中，通过base64解码可得上述密码。

```bash
kg secret -n prometheus kube-prometheus-stack-grafana -oyaml
apiVersion: v1
data:
  admin-password: cHJvbS1vcGVyYXRvcg==
  admin-user: YWRtaW4=
```

模板内容：

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1684392039/article/kubernetes/monitor/grafana.png)

pod数据：

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1684392101/article/kubernetes/monitor/pod-stats.png)

参考：

- https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- https://github.com/prometheus-operator/kube-prometheus
