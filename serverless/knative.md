---
title: "knative介绍"
weight: 1
catalog: true
date: 2024-07-21 10:50:57
subtitle:
header-img: 
tags:
- Serverless
catagories:
- Serverless
---

# 1. knative简介

knative是一个将serverless的能力扩展到k8s中的开源项目。serverless让开发者无需关注容器、镜像、运维等事项，集中精力于开发代码本身，即将代码通过免运维的形式交付给serverless平台。代码会在设定的条件下运行，并自动实现扩缩容。

# 2. knative的组件

knative主要包含三个部分：

- **build**: 将代码转换为容器，主要包括
  - 将源代码从git仓库拉取下来，安装相关的依赖
  - 构建容器镜像
  - 将容器镜像推送到镜像仓库
- **Serving**：创建一个可伸缩的部署。
  - 配置定义了服务的状态，包括版本管理，每次修改都创建一个新版本部署，并保留旧版本。
  - 灵活的路由控制，可以控制百分比的路由到新版本和旧版本服务。
  - 自动弹性伸缩，可以快速创建上千个实例或快速调整实例数为0。

- **Eventing**：事件触发，通过定义各种事件使用knative自动来完成这些任务，而无需手动编写脚本。

# 3. 部署knative

部署knative主要是部署Serving和Eventing两个组件，可以单独部署也可以同时部署。

## 3.1. 部署Serving

1. 部署CRD

   ```bash
   kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.10.1/serving-crds.yaml
   ```

2. 部署Serving

   ```bash
   kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.10.1/serving-core.yaml
   ```

3. 部署HPA autoscaling（可选）

   ```bash
   kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.10.1/serving-hpa.yaml
   ```

查看部署结果

```bash
# kgdep -n knative-serving
NAME                                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/activator               1/1     1            1           107s
deployment.apps/autoscaler              1/1     1            1           107s
deployment.apps/autoscaler-hpa          1/1     1            1           107s
deployment.apps/controller              1/1     1            1           107s
deployment.apps/domain-mapping          1/1     1            1           107s
deployment.apps/domainmapping-webhook   1/1     1            1           107s
deployment.apps/webhook                 1/1     1            1           107s
```

## 3.2. 部署Eventing

1. 部署CRD

   ```bash
   kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.10.0/eventing-crds.yaml
   ```

2. 部署Eventing

   ```bash
   kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.10.0/eventing-core.yaml
   ```

查看部署结果

```bash
# kgdep -n knative-eventing
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
eventing-controller     1/1     1            1           2m13s
eventing-webhook        1/1     1            1           2m13s
pingsource-mt-adapter   0/0     0            0           2m13s
```

# 4. 部署knative客户端

```bash
 wget https://github.com/knative/client/releases/download/knative-v1.10.0/kn-linux-amd64
 chmod +x kn-linux-amd64
 mv kn-linux-amd64 /usr/bin/kn
```

kn命令：

```bash
kn
kn is the command line interface for managing Knative Serving and Eventing resources

Find more information about Knative at: https://knative.dev

Serving Commands:
  service      Manage Knative services
  revision     Manage service revisions
  route        List and describe service routes
  domain       Manage domain mappings
  container    Manage service's containers (experimental)

Eventing Commands:
  source       Manage event sources
  broker       Manage message brokers
  trigger      Manage event triggers
  channel      Manage event channels
  subscription Manage event subscriptions
  eventtype    Manage eventtypes

Other Commands:
  plugin       Manage kn plugins
  secret       Manage secrets
  completion   Output shell completion code
  version      Show the version of this client
```

# 5. 创建示例服务

以下通过yaml的方式演示。

> vi hello.yaml

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
spec:
  template:
    spec:
      containers:
        - image: ghcr.io/knative/helloworld-go:latest
          ports:
            - containerPort: 8080
          env:
            - name: TARGET
              value: "World"
```

创建文件

```bash
kubectl apply -f hello.yaml
```

查看服务

```bash
# kubectl get ksvc
NAME    URL                                      LATESTCREATED   LATESTREADY   READY     REASON
hello   http://hello.default.svc.cluster.local   hello-00001     hello-00001   Unknown   IngressNotConfigured

# kubectl get po
NAME                                     READY   STATUS    RESTARTS   AGE
hello-00001-deployment-6469df75c-qpp5v   2/2     Running   0          15m
```





参考：

- https://www.ibm.com/topics/knative
- https://knative.dev/docs/concepts/
- https://knative.dev/docs/serving/

