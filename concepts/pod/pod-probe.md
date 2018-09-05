# Pod健康检查

Pod的健康状态由两类探针来检查：`LivenessProbe`和`ReadinessProbe`。

## 1. 探针类型

**1. livenessProbe(存活探针)**

- 表明容器是否正在运行。
- 如果存活探测失败，则 kubelet 会杀死容器，并且容器将受到其 `重启策略`的影响。
- 如果容器不提供存活探针，则默认状态为 `Success`。

**2. readinessProbe(就绪探针)**

- 表明容器是否可以正常接受请求。
- 如果就绪探测失败，端点控制器将从与 Pod 匹配的所有 Service 的端点中删除该 Pod 的 IP 地址。
- 初始延迟之前的就绪状态默认为 `Failure`。
- 如果容器不提供就绪探针，则默认状态为 `Success`。

## 2. Handler

`探针`是`kubelet`对容器执行定期的诊断，主要通过调用容器配置的三类`Handler`实现：

**Handler的类型**：

- `ExecAction`：在容器内执行指定命令。如果命令退出时返回码为 0 则认为诊断成功。
- `TCPSocketAction`：对指定端口上的容器的 IP 地址进行 TCP 检查。如果端口打开，则诊断被认为是成功的。
- `HTTPGetAction`：对指定的端口和路径上的容器的 IP 地址执行 HTTP Get 请求。如果响应的状态码大于等于200 且小于 400，则诊断被认为是成功的。

**探测结果**为以下三种之一：

- `成功`：容器通过了诊断。
- `失败`：容器未通过诊断。
- `未知`：诊断失败，因此不会采取任何行动。

## 3. 探针使用方式

- 如果容器异常可以自动崩溃，则不一定要使用探针，可以由Pod的`restartPolicy`执行重启操作。
- `存活探针`适用于希望容器探测失败后被杀死并重新启动，需要指定`restartPolicy` 为 Always 或 OnFailure。
- `就绪探针`适用于希望Pod在不能正常接收流量的时候被剔除，并且在就绪探针探测成功后才接收流量。

存活探针由 kubelet 来执行，因此所有的请求都在 kubelet 的网络命名空间中进行。

### 3.1. LivenessProbe参数

- **initialDelaySeconds**：启动容器后首次进行健康检查的等待时间，单位为秒。
- **timeoutSeconds**:健康检查发送请求后等待响应的时间，如果超时响应kubelet则认为容器非健康，重启该容器，单位为秒。

### 3.2. LivenessProbe三种实现方式

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


参考文章：

- https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
- 《Kubernetes权威指南》
