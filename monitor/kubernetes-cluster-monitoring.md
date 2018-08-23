---
title: "[Kubernetes] Kubernetes集群监控"
catalog: true
date: 2017-08-13 10:50:57
type: "categories"
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. 概述

## 1.1. cAdvisor

cAdvisor对Node机器上的资源及容器进行实时监控和性能数据采集，包括CPU使用情况、内存使用情况、网络吞吐量及文件系统使用情况，cAdvisor集成在Kubelet中，当kubelet启动时会自动启动cAdvisor，即一个cAdvisor仅对一台Node机器进行监控。kubelet的启动参数--cadvisor-port可以定义cAdvisor对外提供服务的端口，默认为4194。可以通过浏览器`Node_IP:port`访问。项目主页：http://github.com/google/cadvisor。

## 1.2. Heapster

是对集群中的各个Node、Pod的资源使用数据进行采集，通过访问每个Node上Kubelet的API，再通过Kubelet调用cAdvisor的API来采集该节点上所有容器的性能数据。由Heapster进行数据汇聚，保存到后端存储系统中，例如InfluxDB，Google Cloud Logging等。项目主页为：https://github.com/kubernetes/heapster。

## 1.3. InfluxDB

是分布式时序数据库（每条记录带有时间戳属性），主要用于实时数据采集、事件跟踪记录、存储时间图表、原始数据等。提供REST API用于数据的存储和查询。项目主页为http://InfluxDB.com。

## 1.4. Grafana

通过Dashboard将InfluxDB的时序数据展现成图表形式，便于查看集群运行状态。项目主页为http://Grafana.org。

## 1.5. 总体架构图

![k8s监控架构图](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510579058/article/kubernetes/monitor/k8s-monitor-arch.png)

其中当前Kubernetes中，Heapster、InfluxDB、Grafana均以Pod的形式启动和运行。Heapster与Master需配置安全连接。

# 2. 部署与使用

## 2.1. cAdvisor

kubelet的启动参数--cadvisor-port可以定义cAdvisor对外提供服务的端口，默认为4194。可以通过浏览器`Node_IP:port`访问。也提供了REST API供客户端远程调用，API返回的格式为JSON，可以采用URL访问：http://`hostname`:`port`/api/`version`/`request`/

例如：[http://14.152.49.100:4194/api/v1.3/machine](http://14.152.49.100:4194/api/v1.3/machine) 获取主机信息。

## 2.2. Service

## 2.2.1. heapster-service

**heapster-service.yaml**

```yaml
apiVersion:v1
kind:Service
metadata:
  label:
    kubenetes.io/cluster-service:"true"
    kubernetes.io/name:Heapster
  name:heapster
  namespace:kube-system
spec:
  ports:
    - port:80
      targetPort:8082
  selector:
    k8s-app:heapster
```

## 2.2.2. influxdb-service

**influxdb-service.yaml**

```yaml
apiVersion:v1
kind:Service
metadata:
  label:null
  name:monitoring-InfluxDB
  namespace:kube-system
spec:
  type:Nodeport
  ports:
    - name:http
      port:80
      targetPort:8083
    - name:api
      port:8086
      targetPort:8086
      Nodeport:8086
  selector:
    name:influxGrafana
```

## 2.2.3. grafana-service

**grafana-service.yaml**

```yaml
apiVersion:v1
kind:Service
metadata:
  label:
    kubenetes.io/cluster-service:"true"
    kubernetes.io/name:monitoring-Grafana
  name:monitoring-Grafana
  namespace:kube-system
spec:
  type:Nodeport
  ports:
      port:80
      targetPort:8080
      Nodeport:8085
  selector:
    name:influxGrafana
```

使用type=NodePort将InfluxDB和Grafana暴露在Node的端口上，以便通过浏览器进行访问。

## 2.2.4. 创建service

```bash
kubectl create -f heapster-service.yaml
kubectl create -f InfluxDB-service.yaml
kubectl create -f Grafana-service.yaml
```

## 2.3. ReplicationController

## 2.3.1. influxdb-grafana-controller

**influxdb-grafana-controller-v3.yaml** 

```yaml
apiVersion:v1
kind:ReplicationController
metadata:
  name:monitoring-influxdb-grafana-v3
  namespace:kube-system
  labels:
    k8s-app:influxGrafana
    version:v3
    kubernetes.io/cluster-service:"true
spec:
  replicas:1
  selector:
    k8s-app:influxGrafana
    version:v3
  template:
    metadata:
      labels:
        k8s-app:influxGrafana
        version:v3
        kubernetes.io/cluster-service:"true
    spec:
      containers:
        - image:gcr.io/google_containers/heapster_influxdb:v0.5
          name:influxdb
          resources:
            limits:
              cpu:100m
              memory:500Mi
            requests:
              cpu:100m
              memory:500Mi
          ports:
            - containerPort:8083
            - containerPort:8086
          volumeMounts:
            -name:influxdb-persistent-storage
             mountPath:/data
        - image:grc.io/google_containers/heapster_grafana:v2.6.0-2
          name:grafana
          resources:
            limits:
              cpu:100m
              memory:100Mi
            requests:
              cpu:100m
              memory:100Mi
          env:
            - name:INFLUXDB_SERVICE_URL
              value:http://monitoring-influxdb:8086
            - name:GF_AUTH_BASIC_ENABLED
              value:"false"
            - name:GF_AUTH_ANONYMOUS_ENABLED
              value:"true"
            - name:GF_AUTH_ANONYMOUS_ORG_ROLE
              value:Admin
            - name:GF_SERVER_ROOT_URL
              value:/api/v1/proxy/namespace/kube-system/services/monitoring-grafana/
          volumeMounts:
            - name:grafana-persistent-storage
              mountPath:/var
      volumes:
        - name:influxdb-persistent-storage
          emptyDir{}
        - name:grafana-persistent-storage
          emptyDir{}
```

## 2.3.2. heapster-controller

**heapster-controller.yaml**

```yaml
apiVersion:v1
kind:ReplicationController
metadata:
    labels:
        k8s-app:heapster
        name:heapster
        version:v6
    name:heapster
    namespace:kube-system
spec:
    replicas:1
    selector:
        name:heapster
        k8s-app:heapster
        version:v6
    template:
        metadata:
            labels:
                k8s-app:heapster
                version:v6
        spec:
            containers:
                - image:gcr.io/google_containers/heapster:v0.17.0
                  name:heapster
                  command:
                    - /heapster
                    - --source=kubernetes:http://192.168.1.128:8080?inClusterConfig=flase&kubeletHttps=true&useServiceAccount=true&auth=
                    - --sink=InfluxDB:http://monitoring-InfluxDB:8086
```

Heapster设置启动参数说明：

1、–source

配置监控来源，本例中表示从k8s-Master获取各个Node的信息。在URL的参数部分，修改kubeletHttps、inClusterConfig、useServiceAccount的值。

2、–sink

配置后端的存储系统，本例中使用InfluxDB。URL中主机名的地址是InfluxDB的Service名字，需要DNS服务正常工作，如果没有配置DNS服务可使用Service的ClusterIP地址。

## 2.3.3. 创建ReplicationController

```bash
kubelet create -f InfluxDB-Grafana-controller.yaml
kubelet create -f heapster-controller.yaml
```

# 3. 查看界面及数据

## 3.1. InfluxDB

访问任意一台Node机器的30083端口。

## 3.2. Grafana

访问任意一台Node机器的30080端口。

# 4. 容器化部署

## 4.1. 拉取镜像

```bash
docker pull influxdb:latest
docker pull cadvisor:latest
docker pull grafana:latest
docker pull heapster:latest
```

## 4.2. 运行容器

## 4.2.1. influxdb

```bash
#influxdb
docker run -d -p 8083:8083 -p 8086:8086 --expose 8090 --expose 8099 --volume=/opt/data/influxdb:/data --name influxsrv influxdb:latest
```

## 4.2.2. cadvisor

```bash
#cadvisor
docker run --volume=/:/rootfs:ro --volume=/var/run:/var/run:rw --volume=/sys:/sys:ro --volume=/var/lib/docker/:/var/lib/docker:ro --publish=8080:8080 --detach=true --link influxsrv:influxsrv --name=cadvisor cadvisor:latest -storage_driver=influxdb -storage_driver_db=cadvisor -storage_driver_host=influxsrv:8086
```

## 4.2.3. grafana

```bash
#grafana
docker run -d -p 3000:3000 -e INFLUXDB_HOST=influxsrv -e INFLUXDB_PORT=8086 -e INFLUXDB_NAME=cadvisor -e INFLUXDB_USER=root -e INFLUXDB_PASS=root --link influxsrv:influxsrv --name grafana grafana:latest
```

## 4.2.4. heapster

```bash
docker run -d -p 8082:8082 --net=host heapster:canary --source=kubernetes:http://`k8s-server-ip`:8080?inClusterConfig=false/&useServiceAccount=false --sink=influxdb:http://`influxdb-ip`:8086
```

## 4.3. 访问

在浏览器输入`IP`:`PORT`

 