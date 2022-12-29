---
title: "Pod的DNS策略"
weight: 3
catalog: true
date: 2022-12-29 18:50:57
subtitle:
header-img: 
tags:
- Network
catagories:
- Network
---

# 1. Pod的DNS策略

可以在pod中定义`dnsPolicy`字段来设置dns的策略。

- "`Default`": Pod 从运行所在的节点继承名称解析配置。就是该Pod的DNS配置会跟宿主机完全一致。

- "`ClusterFirst`": 如果没有配置，即为默认的DNS策略。预先把kube-dns（或CoreDNS）的信息当作预设参数写入到该Pod内的DNS配置。与配置的集群域后缀不匹配的任何 DNS 查询（例如 "www.kubernetes.io"） 都会由 DNS 服务器转发到上游名称服务器。

- "`ClusterFirstWithHostNet`": 对于以 hostNetwork 方式运行的 Pod，应将其 DNS 策略显式设置为 "`ClusterFirstWithHostNet`"。否则，以 hostNetwork 方式和 `"ClusterFirst"` 策略运行的 Pod 将会做出回退至 `"Default"` 策略的行为。

- "`None`": 此设置允许 Pod 忽略 Kubernetes 环境中的 DNS 设置。Pod 会使用其 `dnsConfig` 字段所提供的 DNS 设置。

# 2. Pod DNS的配置

当 Pod 的 `dnsPolicy` 设置为 "`None`" 时，必须指定 `dnsConfig` 字段。

`dnsConfig` 字段中属性：

- `nameservers`：将用作于 Pod 的 DNS 服务器的 IP 地址列表。 最多可以指定 3 个 IP 地址。例如 coredns的Cluster IP。

- `searches`：用于在 Pod 中查找主机名的 DNS 搜索域的列表。此属性是可选的。

- `options`：可选的对象列表，其中每个对象可能具有 `name` 属性（必需）和 `value` 属性（可选）。

示例：

```yaml
apiVersion: v1
kind: Pod
metadata:
  namespace: default
  name: dns-example
spec:
  containers:
    - name: test
      image: nginx
  dnsPolicy: "None"
  dnsConfig:
    nameservers:
      - 1.2.3.4
    searches:
      - ns1.svc.cluster-domain.example
      - my.dns.search.suffix
    options:
      - name: ndots
        value: "2"
      - name: edns0
```

通过以上配置，容器内的`/etc/resolv.conf`文件内容为：

```bash
kubectl exec -it dns-example -- cat /etc/resolv.conf
```

```bash
nameserver 1.2.3.4
search ns1.svc.cluster-domain.example my.dns.search.suffix
options ndots:2 edns0
```

# 3. 自定义DNS服务

默认一般使用coredns来作为k8s的dns服务器。默认使用deployment的方式来运行coredns，会创建一个名为`kube-dns`的service，并用ClusterIP（默认为10.96.0.10）来作为集群内的pod的nameserver。

kubelet 使用 `--cluster-dns=<DNS 服务 IP>` 标志将 DNS 解析器的信息传递给每个容器。使用 `--cluster-domain=<默认本地域名>` 标志配置本地域名。

可查看默认配置：

```bash
# cat /var/lib/kubelet/config.yaml
...
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
```

总结：

当没有给pod设置任何dns策略时，则默认使用ClusterFirst的策略，即nameserver的IP为coredns的ClusterIP。通过coredns来解析服务。

## 3.1. 配置继承节点的DNS解析

- 如果 Pod 的 `dnsPolicy` 设置为 `default`，则它将从 Pod 运行所在节点继承名称解析配置。

- 使用 kubelet 的 `--resolv-conf` 标志设置为宿主机的/etc/resolv.conf文件。

## 3.2. 配置CoreDNS

 配置

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefi: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
```

配置说明：

Corefile 配置包括以下 CoreDNS [插件](https://coredns.io/plugins/)：

- [errors](https://coredns.io/plugins/errors/)：错误记录到标准输出。

- [health](https://coredns.io/plugins/health/)：在 `http://localhost:8080/health` 处提供 CoreDNS 的健康报告。 在这个扩展语法中，`lameduck` 会使此进程不健康，等待 5 秒后进程被关闭。

- [ready](https://coredns.io/plugins/ready/)：在端口 8181 上提供的一个 HTTP 端点， 当所有能够表达自身就绪的插件都已就绪时，在此端点返回 200 OK。

- [kubernetes](https://coredns.io/plugins/kubernetes/)：CoreDNS 将基于服务和 Pod 的 IP 来应答 DNS 查询。 你可以在 CoreDNS 网站找到有关此插件的[更多细节](https://coredns.io/plugins/kubernetes/)。
  
  - 你可以使用 `ttl` 来定制响应的 TTL。默认值是 5 秒钟。TTL 的最小值可以是 0 秒钟， 最大值为 3600 秒。将 TTL 设置为 0 可以禁止对 DNS 记录进行缓存。
  
  - `pods insecure` 选项是为了与 kube-dns 向后兼容。
  
  - 你可以使用 `pods verified` 选项，该选项使得仅在相同名字空间中存在具有匹配 IP 的 Pod 时才返回 A 记录。
  
  - 如果你不使用 Pod 记录，则可以使用 `pods disabled` 选项。

- [prometheus](https://coredns.io/plugins/prometheus/)：CoreDNS 的度量指标值以 [Prometheus](https://prometheus.io/) 格式（也称为 OpenMetrics）在 `http://localhost:9153/metrics` 上提供。

- [forward](https://coredns.io/plugins/forward/): 不在 Kubernetes 集群域内的任何查询都将转发到预定义的解析器 (/etc/resolv.conf)。

- [cache](https://coredns.io/plugins/cache/)：启用前端缓存。

- [loop](https://coredns.io/plugins/loop/)：检测简单的转发环，如果发现死循环，则中止 CoreDNS 进程。

- [reload](https://coredns.io/plugins/reload)：允许自动重新加载已更改的 Corefile。 编辑 ConfigMap 配置后，请等待两分钟，以使更改生效。

- [loadbalance](https://coredns.io/plugins/loadbalance)：这是一个轮转式 DNS 负载均衡器， 它在应答中随机分配 A、AAAA 和 MX 记录的顺序。

## 3.3. 配置存根域和上游域名服务器

CoreDNS 能够使用 [forward 插件](https://coredns.io/plugins/forward/)配置存根域和上游域名服务器。

示例：

在 "10.150.0.1" 处运行了 [Consul](https://www.consul.io/) 域服务器， 且所有 Consul 名称都带有后缀 `.consul.local`。

```yaml
consul.local:53 {
    errors
    cache 30
    forward . 10.150.0.1
}
```

要显式强制所有非集群 DNS 查找通过特定的域名服务器（位于 172.16.0.1），可将 `forward` 指向该域名服务器，而不是 `/etc/resolv.conf`。

```yaml
forward .  172.16.0.1
```

完整示例；

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . 172.16.0.1
        cache 30
        loop
        reload
        loadbalance
    }
    consul.local:53 {
        errors
        cache 30
        forward . 10.150.0.1
    }    
```

# 4. 调试DNS问题

创建一个调试的pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dnsutils
  namespace: default
spec:
  containers:
  - name: dnsutils
    image: registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3
    command:
      - sleep
      - "infinity"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
```

部署调试pod

## 4.1. 查看Coredns服务是否正常

```bash
kubectl get svc --namespace=kube-system 

NAME         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
...
kube-dns     ClusterIP   10.0.0.10      <none>        53/UDP,53/TCP        1h
...
```

## 4.2. 查看/etc/resolv.conf

查看容器内dns配置是否符合预期。

```bash
kubectl exec -ti dnsutils -- cat /etc/resolv.conf
```

## 4.3. nslookup查看解析报错

```bash
kubectl exec -i -t dnsutils -- nslookup kubernetes.default


Server:    10.0.0.10
Address 1: 10.0.0.10

Name:      kubernetes.default
Address 1: 10.0.0.1
```

参考：

- [Service 与 Pod 的 DNS | Kubernetes](https://kubernetes.io/zh-cn/docs/concepts/services-networking/dns-pod-service/)

- [自定义 DNS 服务 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/dns-custom-nameservers/)

- [调试 DNS 问题 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/dns-debugging-resolution/)

- [使用 CoreDNS 进行服务发现 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/coredns/)

- [自动扩缩集群 DNS 服务 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/dns-horizontal-autoscaling/)

- [resolv.conf(5) - Linux manual page](https://www.man7.org/linux/man-pages/man5/resolv.conf.5.html)

- [dns/specification.md at master · kubernetes/dns · GitHub](https://github.com/kubernetes/dns/blob/master/docs/specification.md)

- [deployment/CoreDNS-k8s_version.md at master · coredns/deployment · GitHub](https://github.com/coredns/deployment/blob/master/kubernetes/CoreDNS-k8s_version.md)

- [forward](https://coredns.io/plugins/forward/)
