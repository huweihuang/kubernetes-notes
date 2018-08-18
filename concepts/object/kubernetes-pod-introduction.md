---
title: "[Kubernetes] Kubernetes之Pod详解"
catalog: true
date: 2017-09-17 10:50:57
type: "categories"
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. Pod的基本用法

### 1.1. 说明

1. Pod实际上是**容器的集合**，在k8s中对运行容器的要求为：容器的主程序需要一直在前台运行，而不是后台运行。应用可以改造成前台运行的方式，例如Go语言的程序，直接运行二进制文件；java语言则运行主类；tomcat程序可以写个运行脚本。或者通过supervisor的进程管理工具，即supervisor在前台运行，应用程序由supervisor管理在后台运行。具体可参考[supervisord](http://blog.csdn.net/huwh_/article/details/77108245)。
2. 当多个应用之间是紧耦合的关系时，可以将多个应用一起放在一个Pod中，同个Pod中的多个容器之间互相访问可以通过localhost来通信（可以把Pod理解成一个虚拟机，共享网络和存储卷）。

### 1.2. Pod相关命令

| 操作        | 命令                                       | 说明                   |
| --------- | ---------------------------------------- | -------------------- |
| 创建        | kubectl create -f frontend-localredis-pod.yaml |                      |
| 查询Pod运行状态 | kubectl get pods --namespace=`<NAMESPACE>` |                      |
| 查询Pod详情   | kebectl describe pod `<POD_NAME>` --namespace=`<NAMESPACE>` | 该命令常用来排查问题，查看Event事件 |
| 删除        | kubectl delete pod `<POD_NAME>` ;kubectl delete pod --all |                      |
| 更新        | kubectl replace pod.yaml                 |                      |

## 2. Pod的定义文件

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: string
  namaspace: string
  labels:
  - name: string
      annotations:
  - name: string
  spec:
    containers:
  - name: string
    images: string
    imagePullPolice: [Always | Never | IfNotPresent]
    command: [string]
    args: [string]
    workingDir: string
    volumeMounts:
    - name: string
      mountPath: string
      readOnly: boolean
      ports:
    - name: string
      containerPort: int
      hostPort: int
      protocol: string
      env:
    - name: string
      value: string
      resources:
      limits:
        cpu: string
        memory: string
      requests:
        cpu: string
        memory: string
      livenessProbe:
      exec:
        command: [string]
      httpGet:
        path: string
        port: int
        host: string
        scheme: string
        httpHeaders:
        - name: string
          value: string
          tcpSocket:
            port: int
          initialDelaySeconds: number
          timeoutSeconds: number
          periodSeconds: number
          successThreshold: 0
          failureThreshold: 0
          securityContext:
          privileged: false
          restartPolicy: [Always | Never | OnFailure]   
          nodeSelector: object
          imagePullSecrets:
  - name: string
      hostNetwork: false
        volumes:
  - name: string
    emptyDir: {}
    hostPath:
      path: string
    secret:
      secretName: string
      items:
      - key: string
        path: string
        configMap:
          name: string
          items:
      - key: string
        path: string
```


## 3. 静态pod

静态Pod是由kubelet进行管理，仅存在于特定Node上的Pod。它们不能通过API Server进行管理，无法与ReplicationController、Deployment或DaemonSet进行关联，并且kubelet也无法对其健康检查。

静态Pod总是由kubelet创建，并且总在kubelet所在的Node上运行。

创建静态Pod的方式：

### 3.1. 通过配置文件方式

需要设置kubelet的启动参数“–config”，指定kubelet需要监控的配置文件所在目录，kubelet会定期扫描该目录，并根据该目录的.yaml或.json文件进行创建操作。静态Pod无法通过API Server删除（若删除会变成pending状态），如需删除该Pod则将yaml或json文件从这个目录中删除。

例如：

配置目录为/etc/kubelet.d/，配置启动参数：--config=/etc/kubelet.d/，该目录下放入static-web.yaml。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  labels:
    name: static-web
spec:
  containers:
  - name: static-web
  image: nginx
  ports:
  - name: web
    containerPort: 80
```

## 4. Pod容器共享Volume

同一个Pod中的多个容器可以共享Pod级别的存储卷Volume,Volume可以定义为各种类型，多个容器各自进行挂载，将Pod的Volume挂载为容器内部需要的目录。

例如：Pod级别的Volume:"app-logs",用于tomcat向其中写日志文件，busybox读日志文件。

![这里写图片描述](http://res.cloudinary.com/dqxtn0ick/image/upload/v1512804287/article/kubernetes/pod/pod_volume.png)

**pod-volumes-applogs.yaml**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-pod
spec:
  containers:
  - name: tomcat
    image: tomcat
    ports:
    - containerPort: 8080
    volumeMounts:
    - name: app-logs
      mountPath: /usr/local/tomcat/logs
  - name: busybox
    image: busybox
    command: ["sh","-c","tailf /logs/catalina*.log"]
    volumeMounts:
    - name: app-logs
      mountPath: /logs
  volumes:
  - name: app-logs
    emptuDir: {}
```

**查看日志**

1. kubectl logs `<pod_name>` -c `<container_name>`
2. kubectl exec -it `<pod_name>` -c `<container_name>` – tail /usr/local/tomcat/logs/catalina.xx.log

## 5. Pod的配置管理

Kubernetes v1.2的版本提供统一的集群配置管理方案–ConfigMap。

### 5.1. ConfigMap：容器应用的配置管理

使用场景：

1. 生成为容器内的环境变量。
2. 设置容器启动命令的启动参数（需设置为环境变量）。
3. 以Volume的形式挂载为容器内部的文件或目录。

ConfigMap以一个或多个key:value的形式保存在kubernetes系统中供应用使用，既可以表示一个变量的值（例如：apploglevel=info），也可以表示完整配置文件的内容（例如：server.xml=<?xml...>...）。

可以通过yaml配置文件或者使用kubectl create configmap命令的方式创建ConfigMap。

### 5.2. 创建ConfigMap

#### 5.2.1. 通过yaml文件方式

cm-appvars.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cm-appvars
data:
  apploglevel: info
  appdatadir: /var/data
```

常用命令

kubectl create -f cm-appvars.yaml

kubectl get configmap

kubectl describe configmap cm-appvars

kubectl get configmap cm-appvars -o yaml

#### 5.2.2. 通过kubectl命令行方式

通过kubectl create configmap创建，使用参数--from-file或--from-literal指定内容，可以在一行中指定多个参数。

1）通过--from-file参数从文件中进行创建，可以指定key的名称，也可以在一个命令行中创建包含多个key的ConfigMap。

kubectl create configmap NAME --from-file=[key=]source --from-file=[key=]source

2）通过--from-file参数从目录中进行创建，该目录下的每个配置文件名被设置为key，文件内容被设置为value。

kubectl create configmap NAME --from-file=config-files-dir

3）通过--from-literal从文本中进行创建，直接将指定的key=value创建为ConfigMap的内容。

kubectl create configmap NAME --from-literal=key1=value1 --from-literal=key2=value2

 

容器应用对ConfigMap的使用有两种方法：

1. 通过环境变量获取ConfigMap中的内容。
2. 通过Volume挂载的方式将ConfigMap中的内容挂载为容器内部的文件或目录。

#### 5.2.3. 通过环境变量的方式

ConfigMap的yaml文件:cm-appvars.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cm-appvars
data:
  apploglevel: info
  appdatadir: /var/data
```

Pod的yaml文件：cm-test-pod.yaml

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cm-test-pod
spec:
  containers:
  - name: cm-test
    image: busybox
    command: ["/bin/sh","-c","env|grep APP"]
    env:
    - name: APPLOGLEVEL
      valueFrom:
        configMapKeyRef:
          name: cm-appvars
          key: apploglevel
    - name: APPDATADIR
      valueFrom:
        configMapKeyRef:
          name: cm-appvars
          key: appdatadir
```

创建命令：

kubectl create -f cm-test-pod.yaml

kubectl get pods --show-all

kubectl logs cm-test-pod

### 5.3. 使用ConfigMap的限制条件

- ConfigMap必须在Pod之前创建
- ConfigMap也可以定义为属于某个Namespace。只有处于相同Namespace中的Pod可以引用它。
- kubelet只支持可以被API Server管理的Pod使用ConfigMap。静态Pod无法引用。
- 在Pod对ConfigMap进行挂载操作时，容器内只能挂载为“目录”，无法挂载为文件。

## 6. Pod的生命周期

### 6.1. Pod的状态

| 状态值       | 说明                                       |
| --------- | ---------------------------------------- |
| Pending   | API Server已经创建了该Pod,但Pod中的一个或多个容器的镜像还没有创建，包括镜像下载过程 |
| Running   | Pod内所有容器已创建，且至少一个容器处于运行状态、正在启动状态或正在重启状态  |
| Succeeded | Pod内所有容器均成功执行退出，且不会再重启                   |
| Failed    | Pod内所有容器均已退出，但至少一个容器退出失败                 |
| Unknown   | 由于某种原因无法获取Pod状态，例如网络通信不畅                 |

### 6.2. Pod的重启策略

| 重启策略      | 说明                              |
| --------- | ------------------------------- |
| Always    | 当容器失效时，由kubelet自动重启该容器          |
| OnFailure | 当容器终止运行且退出码不为0时，由kubelet自动重启该容器 |
| Never     | 不论容器运行状态如何，kubelet都不会重启该容器      |

**说明**：

可以管理Pod的控制器有Replication Controller，Job，DaemonSet，及kubelet（静态Pod）。

1. RC和DaemonSet：必须设置为Always，需要保证该容器持续运行。
2. Job：OnFailure或Never，确保容器执行完后不再重启。
3. kubelet：在Pod失效的时候重启它，不论RestartPolicy设置为什么值，并且不会对Pod进行健康检查。

### 6.3. 常见的状态转换场景

| Pod的容器数 | Pod当前状态 | 发生的事件    | Pod结果状态              |                         |                     |
| ------- | ------- | -------- | -------------------- | ----------------------- | ------------------- |
|         |         |          | RestartPolicy=Always | RestartPolicy=OnFailure | RestartPolicy=Never |
| 包含一个容器  | Running | 容器成功退出   | Running              | Succeeded               | Succeeded           |
| 包含一个容器  | Running | 容器失败退出   | Running              | Running                 | Failure             |
| 包含两个容器  | Running | 1个容器失败退出 | Running              | Running                 | Running             |
| 包含两个容器  | Running | 容器被OOM杀掉 | Running              | Running                 | Failure             |

## 7. Pod健康检查

Pod的健康状态由两类探针来检查：LivenessProbe和ReadinessProbe。

- **LivenessProbe**

1. 用于判断容器是否存活（running状态）。
2. 如果LivenessProbe探针探测到容器非健康，则kubelet将杀掉该容器，并根据容器的重启策略做相应处理。
3. 如果容器不包含LivenessProbe探针，则kubelet认为该探针的返回值永远为“success”。

- **ReadinessProbe**

1. 用于判断容器是否启动完成（read状态），可以接受请求。
2. 如果ReadnessProbe探针检测失败，则Pod的状态将被修改。Endpoint Controller将从Service的Endpoint中删除包含该容器所在Pod的Endpoint。

kubelet定期执行LivenessProbe探针来判断容器的健康状态。

**LivenessProbe参数：**

- **initialDelaySeconds**：启动容器后首次进行健康检查的等待时间，单位为秒。
- **timeoutSeconds**:健康检查发送请求后等待响应的时间，如果超时响应kubelet则认为容器非健康，重启该容器，单位为秒。

**LivenessProbe三种实现方式**：

1）ExecAction:在一个容器内部执行一个命令，如果该命令状态返回值为0，则表明容器健康。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-exec
spec:
  containers:
  - name: liveness
    image: tomcagcr.io/google_containers/busybox
    args:
    - /bin/sh
    - -c
    - echo ok > /tmp/health;sleep 10;rm -fr /tmp/health;sleep 600
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/health
      initialDelaySeconds: 15
      timeoutSeconds: 1
```

2）TCPSocketAction:通过容器IP地址和端口号执行TCP检查，如果能够建立TCP连接，则表明容器健康。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-healthcheck
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containnerPort: 80
    livenessProbe:
      tcpSocket:
        port: 80
      initialDelaySeconds: 15
      timeoutSeconds: 1
```

3）HTTPGetAction:通过容器的IP地址、端口号及路径调用HTTP Get方法，如果响应的状态码大于等于200且小于等于400，则认为容器健康。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-healthcheck
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containnerPort: 80
    livenessProbe:
      httpGet:
        path: /_status/healthz
        port: 80
      initialDelaySeconds: 15
      timeoutSeconds: 1
```

## 8. Pod调度

在kubernetes集群中，Pod（container）是应用的载体，一般通过RC、Deployment、DaemonSet、Job等对象来完成Pod的调度与自愈功能。

### 8.1. RC、Deployment:全自动调度

RC的功能即保持集群中始终运行着指定个数的Pod。

在调度策略上主要有：

- 系统内置调度算法[最优Node]
- NodeSelector[定向调度]
- NodeAffinity[亲和性调度]

#### 8.1.1. NodeSelector[定向调度]

k8s中kube-scheduler负责实现Pod的调度，内部系统通过一系列算法最终计算出最佳的目标节点。如果需要将Pod调度到指定Node上，则可以通过Node的标签（Label）和Pod的nodeSelector属性相匹配来达到目的。

1、kubectl label nodes {node-name} {label-key}={label-value}

2、nodeSelector:
{label-key}:{label-value}

如果给多个Node打了相同的标签，则scheduler会根据调度算法从这组Node中选择一个可用的Node来调度。

如果Pod的nodeSelector的标签在Node中没有对应的标签，则该Pod无法被调度成功。

**Node标签的使用场景：**

对集群中不同类型的Node打上不同的标签，可控制应用运行Node的范围。例如role=frontend;role=backend;role=database。

#### 8.1.2. NodeAffinity[亲和性调度]

NodeAffinity意为Node亲和性调度策略，NodeSelector为精确匹配，NodeAffinity为条件范围匹配，通过In（属于）、NotIn（不属于）、Exists（存在一个条件）、DoesNotExist（不存在）、Gt（大于）、Lt（小于）等操作符来选择Node，使调度更加灵活。

- RequiredDuringSchedulingRequiredDuringExecution：类似于NodeSelector，但在Node不满足条件时，系统将从该Node上移除之前调度上的Pod。
- RequiredDuringSchedulingIgnoredDuringExecution：与上一个类似，区别是在Node不满足条件时，系统不一定从该Node上移除之前调度上的Pod。
- PreferredDuringSchedulingIgnoredDuringExecution：指定在满足调度条件的Node中，哪些Node应更优先地进行调度。同时在Node不满足条件时，系统不一定从该Node上移除之前调度上的Pod。

如果同时设置了NodeSelector和NodeAffinity，则系统将需要同时满足两者的设置才能进行调度。

#### 8.1.3. DaemonSet：特定场景调度

DaemonSet是kubernetes1.2版本新增的一种资源对象，用于管理在集群中**每个Node**上**仅运行一份Pod**的副本实例。

![这里写图片描述](<http://res.cloudinary.com/dqxtn0ick/image/upload/v1512804287/article/kubernetes/pod/monitor_pod.png>)

该用法适用的应用场景：

- 在每个Node上运行一个GlusterFS存储或者Ceph存储的daemon进程。
- 在每个Node上运行一个日志采集程序：fluentd或logstach。
- 在每个Node上运行一个健康程序，采集该Node的运行性能数据，例如：Prometheus Node Exportor、collectd、New Relic agent或Ganglia gmond等。

DaemonSet的Pod调度策略与RC类似，除了使用系统内置算法在每台Node上进行调度，也可以通过NodeSelector或NodeAffinity来指定满足条件的Node范围进行调度。

#### **8.1.4. Job：批处理调度**

kubernetes从1.2版本开始支持批处理类型的应用，可以通过kubernetes Job资源对象来定义并启动一个批处理任务。批处理任务通常并行（或串行）启动多个计算进程去处理一批工作项（work item），处理完后，整个批处理任务结束。

##### **8.1.4.1. 批处理的三种模式**

![这里写图片描述](<http://res.cloudinary.com/dqxtn0ick/image/upload/v1512804286/article/kubernetes/pod/k8s_job.png>)

批处理按任务实现方式不同分为以下几种模式：

- **Job Template Expansion模式**
  一个Job对象对应一个待处理的Work item，有几个Work item就产生几个独立的Job，通过适用于Work item数量少，每个Work item要处理的数据量比较大的场景。例如有10个文件（Work item）,每个文件（Work item）为100G。


- **Queue with Pod Per Work Item**
  采用一个任务队列存放Work item，一个Job对象作为消费者去完成这些Work item，其中Job会启动N个Pod，每个Pod对应一个Work item。


- **Queue with Variable Pod Count**
  采用一个任务队列存放Work item，一个Job对象作为消费者去完成这些Work item，其中Job会启动N个Pod，每个Pod对应一个Work item。**但Pod的数量是可变的**。

##### 8.1.4.2. Job的三种类型

**1）Non-parallel Jobs**

通常一个Job只启动一个Pod,除非Pod异常才会重启该Pod,一旦此Pod正常结束，Job将结束。

**2）Parallel Jobs with a fixed completion count**

并行Job会启动多个Pod，此时需要设定Job的.spec.completions参数为一个正数，当正常结束的Pod数量达到该值则Job结束。

**3）Parallel Jobs with a work queue**

任务队列方式的并行Job需要一个独立的Queue，Work item都在一个Queue中存放，不能设置Job的.spec.completions参数。

此时Job的特性：

- 每个Pod能独立判断和决定是否还有任务项需要处理
- 如果某个Pod正常结束，则Job不会再启动新的Pod
- 如果一个Pod成功结束，则此时应该不存在其他Pod还在干活的情况，它们应该都处于即将结束、退出的状态
- 如果所有的Pod都结束了，且至少一个Pod成功结束，则整个Job算是成功结束

## 9. Pod伸缩

k8s中RC的用来保持集群中始终运行指定数目的实例，通过RC的scale机制可以完成Pod的扩容和缩容（伸缩）。

### 9.1. 手动伸缩（scale）

```shell
kubectl scale rc redis-slave --replicas=3
```

### 9.2. 自动伸缩（HPA）

Horizontal Pod Autoscaler（HPA）控制器用于实现基于CPU使用率进行自动Pod伸缩的功能。HPA控制器基于Master的kube-controller-manager服务启动参数--horizontal-pod-autoscaler-sync-period定义是时长（默认30秒），周期性监控目标Pod的CPU使用率，并在满足条件时对ReplicationController或Deployment中的Pod副本数进行调整，以符合用户定义的平均Pod CPU使用率。Pod CPU使用率来源于heapster组件，因此需安装该组件。

可以通过kubectl autoscale命令进行快速创建或者使用yaml配置文件进行创建。创建之前需已存在一个RC或Deployment对象，并且该RC或Deployment中的Pod必须定义resources.requests.cpu的资源请求值，以便heapster采集到该Pod的CPU。

#### 9.2.1. 通过kubectl autoscale创建

例如：

php-apache-rc.yaml

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: php-apache
spec:
  replicas: 1
  template:
    metadata:
      name: php-apache
      labels:
        app: php-apache
    spec:
      containers:
      - name: php-apache
        image: gcr.io/google_containers/hpa-example
        resources:
          requests:
            cpu: 200m
        ports:
        - containerPort: 80
```

创建php-apache的RC

```shell
kubectl create -f php-apache-rc.yaml
```

php-apache-svc.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: php-apache
spec:
  ports:
  - port: 80
  selector:
    app: php-apache
```

创建php-apache的Service

```shell
kubectl create -f php-apache-svc.yaml
```

创建HPA控制器

```shell
kubectl autoscale rc php-apache --min=1 --max=10 --cpu-percent=50
```

#### 9.2.2. 通过yaml配置文件创建

hpa-php-apache.yaml

```yaml
apiVersion: v1
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: v1
    kind: ReplicationController
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
```

创建hpa

```shell
kubectl create -f hpa-php-apache.yaml
```

查看hpa

```shell
kubectl get hpa
```

## 10. Pod滚动升级

k8s中的滚动升级通过执行kubectl rolling-update命令完成，该命令创建一个新的RC（与旧的RC在同一个命名空间中），然后自动控制旧的RC中的Pod副本数逐渐减少为0，同时新的RC中的Pod副本数从0逐渐增加到附加值，但滚动升级中Pod副本数（包括新Pod和旧Pod）保持原预期值。

### 10.1. 通过配置文件实现

redis-master-controller-v2.yaml

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: redis-master-v2
  labels:
    name: redis-master
    version: v2
spec:
  replicas: 1
  selector:
    name: redis-master
    version: v2
  template:
    metadata:
      labels:
        name: redis-master
        version: v2
    spec:
      containers:
      - name: master
        image: kubeguide/redis-master:2.0
        ports:
        - containerPort: 6379
```

注意事项：

1. RC的名字（name）不能与旧RC的名字相同
2. 在selector中应至少有一个Label与旧的RC的Label不同，以标识其为新的RC。例如本例中新增了version的Label。

运行kubectl rolling-update

```shell
kubectl rolling-update redis-master -f redis-master-controller-v2.yaml
```

### 10.2. 通过kubectl rolling-update命令实现

```shell
kubectl rolling-update redis-master --image=redis-master:2.0
```

与使用配置文件实现不同在于，该执行结果旧的RC被删除，新的RC仍使用旧的RC的名字。

### 10.3. 升级回滚

kubectl rolling-update加参数--rollback实现回滚操作

```shell
kubectl rolling-update redis-master --image=kubeguide/redis-master:2.0 --rollback
```

参考《Kubernetes权威指南》

