---
title: "配置私有镜像仓库"
weight: 1
catalog: true
date: 2020-6-23 16:22:24
subtitle:
header-img:
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. 镜像仓库的基本操作

### 1.1. 登录镜像仓库

```bash
docker login -u <username> -p <password> <registry-addr>
```

### 1.2. 拉取镜像

```bash
docker pull https://registry.xxx.com/dev/nginx:latest
```

### 1.3. 推送镜像

```bash
docker push https://registry.xxx.com/dev/nginx:latest
```

### 1.4. 重命名镜像

```bash
docker tag <old-image> <new-image>
```

## 2. docker.xxx.com镜像仓库

使用docker.xxx.com镜像仓库。


### 2.1. 所有节点配置insecure-registries

```bash
#cat /etc/docker/daemon.json
{
  "data-root": "/data/docker",
  "debug": false,
  "insecure-registries": [
	...
    "docker.xxx.com:8080"
  ],
  ...
}
```

### 2.2. 所有节点配置/var/lib/kubelet/config.json

具体参考：[configuring-nodes-to-authenticate-to-a-private-registry](https://kubernetes.io/docs/concepts/containers/images/#configuring-nodes-to-authenticate-to-a-private-registry)

1. 在某个节点登录docker.xxx.com:8080镜像仓库，会更新 $HOME/.docker/config.json
2. 检查$HOME/.docker/config.json是否有该镜像仓库的auth信息。

```
#cat ~/.docker/config.json
{
	"auths": {
		"docker.xxx.com:8080": {
			"auth": "<此处为凭证信息>"
		}
	},
	"HttpHeaders": {
		"User-Agent": "Docker-Client/18.09.9 (linux)"
	}
}
```

3. 将`$HOME/.docker/config.json`拷贝到所有的Node节点上的`/var/lib/kubelet/config.json`。

```bash
# 获取所有节点的IP
nodes=$(kubectl get nodes -o jsonpath='{range .items[*].status.addresses[?(@.type=="ExternalIP")]}{.address} {end}')
# 拷贝到所有节点
for n in $nodes; do scp ~/.docker/config.json root@$n:/var/lib/kubelet/config.json; done
```

### 2.3. 创建docker.xxx.com镜像的pod

指定镜像为：docker.xxx.com:8080/public/2048:latest

完整pod.yaml

```yaml
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "1"
  generation: 1
  labels:
    k8s-app: dockeroa-hub
    qcloud-app: dockeroa-hub
  name: dockeroa-hub
  namespace: test
spec:
  progressDeadlineSeconds: 600
  replicas: 3
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      k8s-app: dockeroa-hub
      qcloud-app: dockeroa-hub
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      labels:
        k8s-app: dockeroa-hub
        qcloud-app: dockeroa-hub
    spec:
      containers:
      - image: docker.xxx.com:8080/public/2048:latest
        imagePullPolicy: Always
        name: game
        resources:
          limits:
            cpu: 500m
            memory: 1Gi
          requests:
            cpu: 250m
            memory: 256Mi
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      nodeName: 192.168.1.1
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
```

查看pod状态

```bash
#kgpoowide -n game
NAME                                     READY   STATUS    RESTARTS   AGE     IP             NODE            NOMINATED NODE   READINESS GATES
docker-oa-757bbbddb5-h6j7m               1/1     Running   0          14m     192.168.2.51   192.168.1.1    <none>           <none>
docker-oa-757bbbddb5-jp5dw               1/1     Running   0          14m     192.168.1.32   192.168.1.2    <none>           <none>
docker-oa-757bbbddb5-nlw9f               1/1     Running   0          14m     192.168.0.43   192.168.1.3   <none>           <none>
```

参考：

- https://kubernetes.io/docs/concepts/containers/images/#configuring-nodes-to-authenticate-to-a-private-registry

