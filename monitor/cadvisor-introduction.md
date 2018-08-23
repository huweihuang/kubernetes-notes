---
title: "[Kubernetes] cAdvisor介绍"
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

# 1. cAdvisor简介

​	cAdvisor对Node机器上的资源及容器进行实时监控和性能数据采集，包括CPU使用情况、内存使用情况、网络吞吐量及文件系统使用情况，cAdvisor集成在Kubelet中，当kubelet启动时会自动启动cAdvisor，即一个cAdvisor仅对一台Node机器进行监控。kubelet的启动参数--cadvisor-port可以定义cAdvisor对外提供服务的端口，默认为4194。可以通过浏览器<Node_IP:port>访问。项目主页：[http://github.com/google/cadvisor。]()

# 2. cAdvisor结构图

![cAdvisor](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510579058/article/kubernetes/monitor/cAdvisor.png)

# 3. Metrics

| 分类         | 字段                 | 描述                                       |
| ---------- | ------------------ | ---------------------------------------- |
| cpu        | cpu_usage_total    |                                          |
|            | cpu_usage_system   |                                          |
|            | cpu_usage_user     |                                          |
|            | cpu_usage_per_cpu  |                                          |
|            | load_average       | Smoothed average of number of runnable threads x 1000 |
| memory     | memory_usage       | Memory Usage                             |
|            | memory_working_set | Working set size                         |
| network    | rx_bytes           | Cumulative count of bytes received       |
|            | rx_errors          | Cumulative count of receive errors encountered |
|            | tx_bytes           | Cumulative count of bytes transmitted    |
|            | tx_errors          | Cumulative count of transmit errors encountered |
| filesystem | fs_device          | Filesystem device                        |
|            | fs_limit           | Filesystem limit                         |
|            | fs_usage           | Filesystem usage                         |

# 4. cAdvisor源码

## 4.1. cAdvisor入口函数

**cadvisor.go**

```go
func main() {
    defer glog.Flush()
    flag.Parse()
    if *versionFlag {
        fmt.Printf("cAdvisor version %s (%s)/n", version.Info["version"], version.Info["revision"])
        os.Exit(0)
    }
    setMaxProcs()
    memoryStorage, err := NewMemoryStorage()
    if err != nil {
        glog.Fatalf("Failed to initialize storage driver: %s", err)
    }
    sysFs, err := sysfs.NewRealSysFs()
    if err != nil {
        glog.Fatalf("Failed to create a system interface: %s", err)
    }
    collectorHttpClient := createCollectorHttpClient(*collectorCert, *collectorKey)
    containerManager, err := manager.New(memoryStorage, sysFs, *maxHousekeepingInterval, *allowDynamicHousekeeping, ignoreMetrics.MetricSet, &collectorHttpClient)
    if err != nil {
        glog.Fatalf("Failed to create a Container Manager: %s", err)
    }
    mux := http.NewServeMux()
    if *enableProfiling {
        mux.HandleFunc("/debug/pprof/", pprof.Index)
        mux.HandleFunc("/debug/pprof/cmdline", pprof.Cmdline)
        mux.HandleFunc("/debug/pprof/profile", pprof.Profile)
        mux.HandleFunc("/debug/pprof/symbol", pprof.Symbol)
    }
    // Register all HTTP handlers.
    err = cadvisorhttp.RegisterHandlers(mux, containerManager, *httpAuthFile, *httpAuthRealm, *httpDigestFile, *httpDigestRealm)
    if err != nil {
        glog.Fatalf("Failed to register HTTP handlers: %v", err)
    }
    cadvisorhttp.RegisterPrometheusHandler(mux, containerManager, *prometheusEndpoint, nil)
    // Start the manager.
    if err := containerManager.Start(); err != nil {
        glog.Fatalf("Failed to start container manager: %v", err)
    }
    // Install signal handler.
    installSignalHandler(containerManager)
    glog.Infof("Starting cAdvisor version: %s-%s on port %d", version.Info["version"], version.Info["revision"], *argPort)
    addr := fmt.Sprintf("%s:%d", *argIp, *argPort)
    glog.Fatal(http.ListenAndServe(addr, mux))
}
```

核心代码：

```go
memoryStorage, err := NewMemoryStorage()
sysFs, err := sysfs.NewRealSysFs()
#创建containerManager
containerManager, err := manager.New(memoryStorage, sysFs, *maxHousekeepingInterval, *allowDynamicHousekeeping, ignoreMetrics.MetricSet, &collectorHttpClient)
#启动containerManager
err := containerManager.Start()
```

## 4.2. cAdvisor Client的使用

```go
import "github.com/google/cadvisor/client"
func main(){
    client, err := client.NewClient("http://192.168.19.30:4194/")   //http://<host-ip>:<port>/
}
```

## 4.2.1 client定义

**cadvisor/client/client.go**

```go
// Client represents the base URL for a cAdvisor client.
type Client struct {
    baseUrl string
}
// NewClient returns a new v1.3 client with the specified base URL.
func NewClient(url string) (*Client, error) {
    if !strings.HasSuffix(url, "/") {
        url += "/"
    }
    return &Client{
        baseUrl: fmt.Sprintf("%sapi/v1.3/", url),
    }, nil
}
```

## 4.2.2. client方法

**1）MachineInfo**

```go
// MachineInfo returns the JSON machine information for this client.
// A non-nil error result indicates a problem with obtaining
// the JSON machine information data.
func (self *Client) MachineInfo() (minfo *v1.MachineInfo, err error) {
       u := self.machineInfoUrl()
       ret := new(v1.MachineInfo)
       if err = self.httpGetJsonData(ret, nil, u, "machine info"); err != nil {
              return
       }
       minfo = ret
       return
}
```

**2）ContainerInfo**

```go
// ContainerInfo returns the JSON container information for the specified
// container and request.
func (self *Client) ContainerInfo(name string, query *v1.ContainerInfoRequest) (cinfo *v1.ContainerInfo, err error) {
       u := self.containerInfoUrl(name)
       ret := new(v1.ContainerInfo)
       if err = self.httpGetJsonData(ret, query, u, fmt.Sprintf("container info for %q", name)); err != nil {
              return
       }
       cinfo = ret
       return
}
```

**3）DockerContainer**

```go
// Returns the JSON container information for the specified
// Docker container and request.
func (self *Client) DockerContainer(name string, query *v1.ContainerInfoRequest) (cinfo v1.ContainerInfo, err error) {
       u := self.dockerInfoUrl(name)
       ret := make(map[string]v1.ContainerInfo)
       if err = self.httpGetJsonData(&ret, query, u, fmt.Sprintf("Docker container info for %q", name)); err != nil {
              return
       }
       if len(ret) != 1 {
              err = fmt.Errorf("expected to only receive 1 Docker container: %+v", ret)
              return
       }
       for _, cont := range ret {
              cinfo = cont
       }
       return
}
```

**4）AllDockerContainers**

```go
// Returns the JSON container information for all Docker containers.
func (self *Client) AllDockerContainers(query *v1.ContainerInfoRequest) (cinfo []v1.ContainerInfo, err error) {
       u := self.dockerInfoUrl("/")
       ret := make(map[string]v1.ContainerInfo)
       if err = self.httpGetJsonData(&ret, query, u, "all Docker containers info"); err != nil {
              return
       }
       cinfo = make([]v1.ContainerInfo, 0, len(ret))
       for _, cont := range ret {
              cinfo = append(cinfo, cont)
       }
       return
}
```
