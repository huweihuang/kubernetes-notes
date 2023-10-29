---
title: "Pod健康检查"
weight: 4
catalog: true
date: 2017-08-13 10:50:57
subtitle:
header-img: 
tags:
- Pod
catagories:
- Pod
---

# Pod健康检查

Pod的健康状态由两类探针来检查：`LivenessProbe`和`ReadinessProbe`。

## 1. 探针类型

**1. livenessProbe(存活探针)**

- 表明容器是否正在运行。
- **如果存活探测失败，则 kubelet 会杀死容器**，并且容器将受到其 `重启策略`的影响。
- 如果容器不提供存活探针，则默认状态为 `Success`。

**2. readinessProbe(就绪探针)**

- 表明容器是否可以正常接受请求。
- **如果就绪探测失败，端点控制器将从与 Pod 匹配的所有 Service 的端点中删除该 Pod 的 IP 地址**。
- 初始延迟之前的就绪状态默认为 `Failure`。
- 如果容器不提供就绪探针，则默认状态为 `Success`。

## 2. 探针使用场景

- 如果容器异常可以自动崩溃，则不一定要使用探针，可以由Pod的`restartPolicy`执行重启操作。
- `存活探针`适用于希望容器探测失败后被杀死并重新启动，需要指定`restartPolicy` 为 Always 或 OnFailure。
- `就绪探针`适用于希望Pod在不能正常接收流量的时候被剔除，并且在就绪探针探测成功后才接收流量。

`探针`是`kubelet`对容器执行定期的诊断，主要通过调用容器配置的四类`Handler`实现：

**Handler的类型**：

- `ExecAction`：在容器内执行指定命令。如果命令退出时返回码为 0 则认为诊断成功。
- `TCPSocketAction`：对指定端口上的容器的 IP 地址进行 TCP 检查。如果端口打开，则诊断被认为是成功的。
- `HTTPGetAction`：对指定的端口和路径上的容器的 IP 地址执行 HTTP Get 请求。如果响应的状态码大于等于200 且小于 400，则诊断被认为是成功的。
- `GRPCAction`：调用GRPC接口来判断服务是否健康。 如果响应的状态是 "SERVING"，则认为诊断成功。

**探测结果**为以下三种之一：

- `成功`：容器通过了诊断。
- `失败`：容器未通过诊断。
- `未知`：诊断失败，因此不会采取任何行动。

## 3. 探针的配置

探针配置在pod的container结构体下，`livenessProbe`和`readinessProbe`参数基本一致。

### 3.1. 探针通用参数

常用的参数为`timeoutSeconds`、`periodSeconds`、`periodSeconds`，即接口超时时间，重试频率，重试次数三个值。

- `initialDelaySeconds`：启动容器后首次进行健康检查的等待时间，单位为秒，**默认值为0**。
- `timeoutSeconds`:健康检查接口超时响应的时间，**默认为1秒**，最小值为1秒。
- `periodSeconds`：重试的频率，**默认值为10秒**，即10秒重试一次，最小值是1秒，**建议可以设置为3-5秒**。
- `failureThreshold`：失败重试的次数，**默认值为3**，最小值为1。
- `successThreshold`：最小探测成功次数，**默认值为1**，一般不设置。

除了以上的通用参数外，`livenessProbe`和`readinessProbe`参数基本一致。以下以`readinessProbe`为例说明探针的使用方式。

### 3.2. ReadinessProbe三种实现方式

#### 3.2.1. HTTPGetAction

通过容器的IP地址、端口号及路径调用HTTP Get方法，如果响应的状态码大于等于200且小于等于400，则认为容器健康。

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
    readinessProbe:
      httpGet:
        path: /_status/healthz
        port: 80
        scheme: HTTP
      initialDelaySeconds: 1
      periodSeconds: 5
      timeoutSeconds: 5
```

#### 3.2.2. TCPSocketAction

通过容器IP地址和端口号执行TCP检查，如果能够建立TCP连接，则表明容器健康。

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
    readinessProbe:
      tcpSocket:
        port: 80
      initialDelaySeconds: 1
      timeoutSeconds: 5
```

#### 3.2.3. ExecAction

在一个容器内部执行一个命令，如果该命令状态返回值为0，则表明容器健康。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: readiness-exec
spec:
  containers:
  - name: readiness
    image: tomcagcr.io/google_containers/busybox
    args:
    - /bin/sh
    - -c
    - echo ok > /tmp/health;sleep 10;rm -fr /tmp/health;sleep 600
    readinessreadinessProbe:
      exec:
        command:
        - cat
        - /tmp/health
      initialDelaySeconds: 1
      timeoutSeconds: 5
```

## 4. 探针相关源码

探针配置在pod的container结构体下：

```go
    // 存活探针
    LivenessProbe *Probe `json:"livenessProbe,omitempty" protobuf:"bytes,10,opt,name=livenessProbe"`
    // 就绪探针
    ReadinessProbe *Probe `json:"readinessProbe,omitempty" protobuf:"bytes,11,opt,name=readinessProbe"`
```

### 4.1. Probe源码

```go
type Probe struct {
    // The action taken to determine the health of a container
    ProbeHandler `json:",inline" protobuf:"bytes,1,opt,name=handler"`
    // Number of seconds after the container has started before liveness probes are initiated.
    // More info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes
    // +optional
    InitialDelaySeconds int32 `json:"initialDelaySeconds,omitempty" protobuf:"varint,2,opt,name=initialDelaySeconds"`
    // Number of seconds after which the probe times out.
    // Defaults to 1 second. Minimum value is 1.
    // More info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes
    // +optional
    TimeoutSeconds int32 `json:"timeoutSeconds,omitempty" protobuf:"varint,3,opt,name=timeoutSeconds"`
    // How often (in seconds) to perform the probe.
    // Default to 10 seconds. Minimum value is 1.
    // +optional
    PeriodSeconds int32 `json:"periodSeconds,omitempty" protobuf:"varint,4,opt,name=periodSeconds"`
    // Minimum consecutive successes for the probe to be considered successful after having failed.
    // Defaults to 1. Must be 1 for liveness and startup. Minimum value is 1.
    // +optional
    SuccessThreshold int32 `json:"successThreshold,omitempty" protobuf:"varint,5,opt,name=successThreshold"`
    // Minimum consecutive failures for the probe to be considered failed after having succeeded.
    // Defaults to 3. Minimum value is 1.
    // +optional
    FailureThreshold int32 `json:"failureThreshold,omitempty" protobuf:"varint,6,opt,name=failureThreshold"`
    // Optional duration in seconds the pod needs to terminate gracefully upon probe failure.
    // The grace period is the duration in seconds after the processes running in the pod are sent
    // a termination signal and the time when the processes are forcibly halted with a kill signal.
    // Set this value longer than the expected cleanup time for your process.
    // If this value is nil, the pod's terminationGracePeriodSeconds will be used. Otherwise, this
    // value overrides the value provided by the pod spec.
    // Value must be non-negative integer. The value zero indicates stop immediately via
    // the kill signal (no opportunity to shut down).
    // This is a beta field and requires enabling ProbeTerminationGracePeriod feature gate.
    // Minimum value is 1. spec.terminationGracePeriodSeconds is used if unset.
    // +optional
    TerminationGracePeriodSeconds *int64 `json:"terminationGracePeriodSeconds,omitempty" protobuf:"varint,7,opt,name=terminationGracePeriodSeconds"`
}
```

### 4.2. ProbeHandler源码

```go
// ProbeHandler defines a specific action that should be taken in a probe.
// One and only one of the fields must be specified.
type ProbeHandler struct {
    // Exec specifies the action to take.
    // +optional
    Exec *ExecAction `json:"exec,omitempty" protobuf:"bytes,1,opt,name=exec"`
    // HTTPGet specifies the http request to perform.
    // +optional
    HTTPGet *HTTPGetAction `json:"httpGet,omitempty" protobuf:"bytes,2,opt,name=httpGet"`
    // TCPSocket specifies an action involving a TCP port.
    // +optional
    TCPSocket *TCPSocketAction `json:"tcpSocket,omitempty" protobuf:"bytes,3,opt,name=tcpSocket"`

    // GRPC specifies an action involving a GRPC port.
    // This is a beta field and requires enabling GRPCContainerProbe feature gate.
    // +featureGate=GRPCContainerProbe
    // +optional
    GRPC *GRPCAction `json:"grpc,omitempty" protobuf:"bytes,4,opt,name=grpc"`
}
```

### 4.3. ProbeAction

#### 4.3.1. HTTPGetAction

```go
// HTTPHeader describes a custom header to be used in HTTP probes
type HTTPHeader struct {
    // The header field name
    Name string `json:"name" protobuf:"bytes,1,opt,name=name"`
    // The header field value
    Value string `json:"value" protobuf:"bytes,2,opt,name=value"`
}

// HTTPGetAction describes an action based on HTTP Get requests.
type HTTPGetAction struct {
    // Path to access on the HTTP server.
    // +optional
    Path string `json:"path,omitempty" protobuf:"bytes,1,opt,name=path"`
    // Name or number of the port to access on the container.
    // Number must be in the range 1 to 65534. 
    // Name must be an IANA_SVC_NAME.
    Port intstr.IntOrString `json:"port" protobuf:"bytes,2,opt,name=port"`
    // Host name to connect to, defaults to the pod IP. You probably want to set
    // "Host" in httpHeaders instead.
    // +optional
    Host string `json:"host,omitempty" protobuf:"bytes,3,opt,name=host"`
    // Scheme to use for connecting to the host.
    // Defaults to HTTP.
    // +optional
    Scheme URIScheme `json:"scheme,omitempty" protobuf:"bytes,4,opt,name=scheme,casttype=URIScheme"`
    // Custom headers to set in the request. HTTP allows repeated headers.
    // +optional
    HTTPHeaders []HTTPHeader `json:"httpHeaders,omitempty" protobuf:"bytes,5,rep,name=httpHeaders"`
}

// URIScheme identifies the scheme used for connection to a host for Get actions
// +enum
type URIScheme string

const (
    // URISchemeHTTP means that the scheme used will be http://
    URISchemeHTTP URIScheme = "HTTP"
    // URISchemeHTTPS means that the scheme used will be https://
    URISchemeHTTPS URIScheme = "HTTPS"
)
```

#### 4.3.2. TCPSocketAction

```go
// TCPSocketAction describes an action based on opening a socket
type TCPSocketAction struct {
    // Number or name of the port to access on the container.
    // Number must be in the range 1 to 65534. 
    // Name must be an IANA_SVC_NAME.
    Port intstr.IntOrString `json:"port" protobuf:"bytes,1,opt,name=port"`
    // Optional: Host name to connect to, defaults to the pod IP.
    // +optional
    Host string `json:"host,omitempty" protobuf:"bytes,2,opt,name=host"`
}
```

#### 4.3.3. ExecAction

```go
// ExecAction describes a "run in container" action.
type ExecAction struct {
    // Command is the command line to execute inside the container, the working directory for the
    // command  is root ('/') in the container's filesystem. The command is simply exec'd, it is
    // not run inside a shell, so traditional shell instructions ('|', etc) won't work. To use
    // a shell, you need to explicitly call out to that shell.
    // Exit status of 0 is treated as live/healthy and non-zero is unhealthy.
    // +optional
    Command []string `json:"command,omitempty" protobuf:"bytes,1,rep,name=command"`
}
```

#### 4.3.4. GRPCAction

```go
type GRPCAction struct {
    // Port number of the gRPC service. Number must be in the range 1 to 65534. 
    Port int32 `json:"port" protobuf:"bytes,1,opt,name=port"`

    // Service is the name of the service to place in the gRPC HealthCheckRequest
    // (see https://github.com/grpc/grpc/blob/master/doc/health-checking.md).
    //
    // If this is not specified, the default behavior is defined by gRPC.
    // +optional
    // +default=""
    Service *string `json:"service" protobuf:"bytes,2,opt,name=service"`
}
```

参考文章：

- https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
- [配置存活、就绪和启动探针 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- https://mp.weixin.qq.com/s/ApD8D0_UAPftUjw-0Txcyw
- 《Kubernetes权威指南》
