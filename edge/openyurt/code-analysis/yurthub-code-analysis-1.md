---
title: "OpenYurt之YurtHub源码分析"
linkTitle: "YurtHub源码分析（1）"
weight: 1
catalog: true
date: 2023-04-16 10:50:57
subtitle:
header-img: 
tags:
- OpenYurt
catagories:
- OpenYurt
---

> 本文分析`yurthub`源码，第一部分。
> 
> 本文以commit id：`180282663457080119a1bc6076cce20c922b5c50`， 对应版本tag: `v1.2.1` 的源码分析yurthub的实现逻辑。

yurthub是部署在每个边缘节点上用来实现边缘自治的组件。在云边通信正常的情况下实现apiserver的请求转发，断网的情况下通过本地的缓存数据保证节点上容器的正常运行。

基本架构图：

![](https://res.cloudinary.com/dqxtn0ick/image/upload/v1681567428/article/openyurt/yurthub.png)

pkg包中yurthub代码目录结构；

```bash
yurthub
├── cachemanager  # cache 管理器，
├── certificate # 证书token管理
├── filter 
├── gc # GCManager
├── healthchecker # cloud apiserver 探火机制
├── kubernetes # 
├── metrics
├── network # 网络iptables配置 
├── otaupdate
├── poolcoordinator
├── proxy # 核心代码，反向代理机制，包括remote proxy和local proxy
├── server # yurthub server
├── storage # 本地存储的实现
├── tenant
├── transport
└── util
```

# 1. NewCmdStartYurtHub

`openyurt`的代码风格与k8s的一致，由cmd为入口，pkg为主要的实现逻辑。

以下是cmd的main函数。

```go
func main() {
    newRand := rand.New(rand.NewSource(time.Now().UnixNano()))
    newRand.Seed(time.Now().UnixNano())

    cmd := app.NewCmdStartYurtHub(server.SetupSignalContext())
    cmd.Flags().AddGoFlagSet(flag.CommandLine)
    if err := cmd.Execute(); err != nil {
        panic(err)
    }
}
```

main 函数主要创建 NewCmdStartYurtHub 对象。NewCmd的函数一般都包含以下的几个部分，运行顺序从上到下：

1. NewYurtHubOptions：创建option参数对象，主要用于flag参数解析到option的结构体。

2. yurtHubOptions.AddFlags(cmd.Flags())：添加AddFlags，设置flag参数信息。

3. yurtHubOptions.Validate()：校验flag解析后的option的参数合法性。

4. yurtHubCfg, err := config.Complete(yurtHubOptions)：将option的参数转换为config的对象。

5. Run(ctx, yurtHubCfg)：基于config执行run函数，运行cmd的核心逻辑。

```go
// NewCmdStartYurtHub creates a *cobra.Command object with default parameters
func NewCmdStartYurtHub(ctx context.Context) *cobra.Command {
    yurtHubOptions := options.NewYurtHubOptions()

    cmd := &cobra.Command{
        Use:   projectinfo.GetHubName(),
        Short: "Launch " + projectinfo.GetHubName(),
        Long:  "Launch " + projectinfo.GetHubName(),
        Run: func(cmd *cobra.Command, args []string) {
            if yurtHubOptions.Version {
                fmt.Printf("%s: %#v\n", projectinfo.GetHubName(), projectinfo.Get())
                return
            }
            fmt.Printf("%s version: %#v\n", projectinfo.GetHubName(), projectinfo.Get())

            cmd.Flags().VisitAll(func(flag *pflag.Flag) {
                klog.V(1).Infof("FLAG: --%s=%q", flag.Name, flag.Value)
            })
            if err := yurtHubOptions.Validate(); err != nil {
                klog.Fatalf("validate options: %v", err)
            }

            yurtHubCfg, err := config.Complete(yurtHubOptions)
            if err != nil {
                klog.Fatalf("complete %s configuration error, %v", projectinfo.GetHubName(), err)
            }
            klog.Infof("%s cfg: %#+v", projectinfo.GetHubName(), yurtHubCfg)

            if err := Run(ctx, yurtHubCfg); err != nil {
                klog.Fatalf("run %s failed, %v", projectinfo.GetHubName(), err)
            }
        },
    }

    yurtHubOptions.AddFlags(cmd.Flags())
    return cmd
}
```

以上flag、option、config的构建函数此处不做分析，以下分析run函数的逻辑。

# 2. Run(ctx, yurtHubCfg)

Run函数部分主要构建了几个manager，每个manager各司其职，负责对应的逻辑。有的manager在该函数中直接构建后执行manager.run的逻辑。有的则作为参数传入下一级函数中再执行manager.run函数。

主要包括以下的manager：

- transportManager

- cloudHealthChecker

- restConfigMgr

- cacheMgr

- gcMgr

- tenantMgr

- NetworkMgr

每个manager的实现细节此处暂不做分析。

此处先贴一下完整源码，避免读者还需要去翻代码。

> 代码：[/cmd/yurthub/app/start.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/cmd/yurthub/app/start.go)

```go
// Run runs the YurtHubConfiguration. This should never exit
func Run(ctx context.Context, cfg *config.YurtHubConfiguration) error {
    defer cfg.CertManager.Stop()
    trace := 1
    klog.Infof("%d. new transport manager", trace)
    // 构造NewTransportManager
    transportManager, err := transport.NewTransportManager(cfg.CertManager, ctx.Done())
    if err != nil {
        return fmt.Errorf("could not new transport manager, %w", err)
    }
    trace++

    klog.Infof("%d. prepare cloud kube clients", trace)
    cloudClients, err := createClients(cfg.HeartbeatTimeoutSeconds, cfg.RemoteServers, cfg.CoordinatorServerURL, transportManager)
    if err != nil {
        return fmt.Errorf("failed to create cloud clients, %w", err)
    }
    trace++

    var cloudHealthChecker healthchecker.MultipleBackendsHealthChecker
    if cfg.WorkingMode == util.WorkingModeEdge {
        klog.Infof("%d. create health checkers for remote servers and pool coordinator", trace)
        cloudHealthChecker, err = healthchecker.NewCloudAPIServerHealthChecker(cfg, cloudClients, ctx.Done())
        if err != nil {
            return fmt.Errorf("could not new cloud health checker, %w", err)
        }
    } else {
        klog.Infof("%d. disable health checker for node %s because it is a cloud node", trace, cfg.NodeName)
        // In cloud mode, cloud health checker is not needed.
        // This fake checker will always report that the cloud is healthy and pool coordinator is unhealthy.
        cloudHealthChecker = healthchecker.NewFakeChecker(true, make(map[string]int))
    }
    trace++

    klog.Infof("%d. new restConfig manager", trace)
    restConfigMgr, err := hubrest.NewRestConfigManager(cfg.CertManager, cloudHealthChecker)
    if err != nil {
        return fmt.Errorf("could not new restConfig manager, %w", err)
    }
    trace++

    var cacheMgr cachemanager.CacheManager
    if cfg.WorkingMode == util.WorkingModeEdge {
        klog.Infof("%d. new cache manager with storage wrapper and serializer manager", trace)
        cacheMgr = cachemanager.NewCacheManager(cfg.StorageWrapper, cfg.SerializerManager, cfg.RESTMapperManager, cfg.SharedFactory)
    } else {
        klog.Infof("%d. disable cache manager for node %s because it is a cloud node", trace, cfg.NodeName)
    }
    trace++

    if cfg.WorkingMode == util.WorkingModeEdge {
        klog.Infof("%d. new gc manager for node %s, and gc frequency is a random time between %d min and %d min", trace, cfg.NodeName, cfg.GCFrequency, 3*cfg.GCFrequency)
        gcMgr, err := gc.NewGCManager(cfg, restConfigMgr, ctx.Done())
        if err != nil {
            return fmt.Errorf("could not new gc manager, %w", err)
        }
        // 直接运行manager
        gcMgr.Run()
    } else {
        klog.Infof("%d. disable gc manager for node %s because it is a cloud node", trace, cfg.NodeName)
    }
    trace++

    klog.Infof("%d. new tenant sa manager", trace)
    tenantMgr := tenant.New(cfg.TenantNs, cfg.SharedFactory, ctx.Done())
    trace++

    var coordinatorHealthCheckerGetter func() healthchecker.HealthChecker = getFakeCoordinatorHealthChecker
    var coordinatorTransportManagerGetter func() transport.Interface = getFakeCoordinatorTransportManager
    var coordinatorGetter func() poolcoordinator.Coordinator = getFakeCoordinator

    if cfg.EnableCoordinator {
        klog.Infof("%d. start to run coordinator", trace)
        trace++

        coordinatorInformerRegistryChan := make(chan struct{})
        // coordinatorRun will register secret informer into sharedInformerFactory, and start a new goroutine to periodically check
        // if certs has been got from cloud APIServer. It will close the coordinatorInformerRegistryChan if the secret channel has
        // been registered into informer factory.
        coordinatorHealthCheckerGetter, coordinatorTransportManagerGetter, coordinatorGetter = coordinatorRun(ctx, cfg, restConfigMgr, cloudHealthChecker, coordinatorInformerRegistryChan)
        // wait for coordinator informer registry
        klog.Infof("waiting for coordinator informer registry")
        <-coordinatorInformerRegistryChan
        klog.Infof("coordinator informer registry finished")
    }

    // Start the informer factory if all informers have been registered
    cfg.SharedFactory.Start(ctx.Done())
    cfg.YurtSharedFactory.Start(ctx.Done())

    klog.Infof("%d. new reverse proxy handler for remote servers", trace)
    // 将之前构造的manager作为参数构建yurtProxyHandler
    yurtProxyHandler, err := proxy.NewYurtReverseProxyHandler(
        cfg,
        cacheMgr,
        transportManager,
        cloudHealthChecker,
        tenantMgr,
        coordinatorGetter,
        coordinatorTransportManagerGetter,
        coordinatorHealthCheckerGetter,
        ctx.Done())
    if err != nil {
        return fmt.Errorf("could not create reverse proxy handler, %w", err)
    }
    trace++

    if cfg.NetworkMgr != nil {
        cfg.NetworkMgr.Run(ctx.Done())
    }

    klog.Infof("%d. new %s server and begin to serve", trace, projectinfo.GetHubName())
    // 基于yurtProxyHandler运行一个http server.
    if err := server.RunYurtHubServers(cfg, yurtProxyHandler, restConfigMgr, ctx.Done()); err != nil {
        return fmt.Errorf("could not run hub servers, %w", err)
    }
    <-ctx.Done()
    klog.Infof("hub agent exited")
    return nil
}
```

除了上述的各种manager的构造及运行外，run函数中还构建了`yurtProxyHandler`，最终执行`RunYurtHubServers`运行一组不会退出的http server。以下先不对manager的实现做展开，而直接分析RunYurtHubServers的逻辑。RunYurtHubServers的代码在pkg包中。

# 3. RunYurtHubServers

RunYurtHubServers就是一个传统的http server的运行逻辑，主要包括几个不同类型的http server。http server的运行逻辑可以概括如下：

1. hubServerHandler := mux.NewRouter()： 新建路由创建handler

2. registerHandlers(hubServerHandler, cfg, rest)： 注册路由

3. YurtHubServerServing.Serve：执行http server.Serve函数启动一个server服务。

http server分为两类：

- yurthub http server: yurthub metrics, healthz的接口。

- yurthub proxy server: 代理kube-apiserver的请求。

## 3.1. YurtHubServerServing

```go
    hubServerHandler := mux.NewRouter()
    registerHandlers(hubServerHandler, cfg, rest)

    // start yurthub http server for serving metrics, pprof.
    if cfg.YurtHubServerServing != nil {
        if err := cfg.YurtHubServerServing.Serve(hubServerHandler, 0, stopCh); err != nil {
            return err
        }
    }
```

registerHandlers的路由内容如下：

```go
// registerHandler registers handlers for yurtHubServer, and yurtHubServer can handle requests like profiling, healthz, update token.
func registerHandlers(c *mux.Router, cfg *config.YurtHubConfiguration, rest *rest.RestConfigManager) {
    // register handlers for update join token
    c.Handle("/v1/token", updateTokenHandler(cfg.CertManager)).Methods("POST", "PUT")

    // register handler for health check
    c.HandleFunc("/v1/healthz", healthz).Methods("GET")
    c.Handle("/v1/readyz", readyz(cfg.CertManager)).Methods("GET")

    // register handler for profile
    if cfg.EnableProfiling {
        profile.Install(c)
    }

    // register handler for metrics
    c.Handle("/metrics", promhttp.Handler())

    // register handler for ota upgrade
    c.Handle("/pods", ota.GetPods(cfg.StorageWrapper)).Methods("GET")
    c.Handle("/openyurt.io/v1/namespaces/{ns}/pods/{podname}/upgrade",
        ota.HealthyCheck(rest, cfg.NodeName, ota.UpdatePod)).Methods("POST")
}
```

以上路由不做深入分析。

## 3.2. YurtHubProxyServerServing

YurtHubProxyServerServing主要代理kube-apiserver的转发请求。

```go
    // start yurthub proxy servers for forwarding requests to cloud kube-apiserver
    if cfg.WorkingMode == util.WorkingModeEdge {
        proxyHandler = wrapNonResourceHandler(proxyHandler, cfg, rest)
    }
    if cfg.YurtHubProxyServerServing != nil {
        if err := cfg.YurtHubProxyServerServing.Serve(proxyHandler, 0, stopCh); err != nil {
            return err
        }
    }
```

以下分析yurtProxyHandler的逻辑。

## 3.3. NewYurtReverseProxyHandler

NewYurtReverseProxyHandler主要创建了http handler 代理所有转发请求。

1、创建Load Balancer，主要用来转发apiserver的请求。

```go
    lb, err := remote.NewLoadBalancer(
        yurtHubCfg.LBMode,
        yurtHubCfg.RemoteServers,
        localCacheMgr,
        transportMgr,
        coordinatorGetter,
        cloudHealthChecker,
        yurtHubCfg.FilterManager,
        yurtHubCfg.WorkingMode,
        stopCh)
```

2、创建local Proxy，主要用来转发本地缓存的请求。

```go
        // When yurthub works in Edge mode, we may use local proxy or pool proxy to handle
        // the request when offline.
        localProxy = local.NewLocalProxy(localCacheMgr,
            cloudHealthChecker.IsHealthy,
            isCoordinatorHealthy,
            yurtHubCfg.MinRequestTimeout,
        )
        localProxy = local.WithFakeTokenInject(localProxy, yurtHubCfg.SerializerManager)
```

3、创建yurtReverseProxy

```go
    yurtProxy := &yurtReverseProxy{
        resolver:                      resolver,
        loadBalancer:                  lb,
        cloudHealthChecker:            cloudHealthChecker,
        coordinatorHealtCheckerGetter: coordinatorHealthCheckerGetter,
        localProxy:                    localProxy,
        poolProxy:                     poolProxy,
        maxRequestsInFlight:           yurtHubCfg.MaxRequestInFlight,
        isCoordinatorReady:            isCoordinatorReady,
        enablePoolCoordinator:         yurtHubCfg.EnableCoordinator,
        tenantMgr:                     tenantMgr,
        workingMode:                   yurtHubCfg.WorkingMode,
    }

    return yurtProxy.buildHandlerChain(yurtProxy), nil
```

# 4. yurtReverseProxy

`yurtReverseProxy`主要是作为实现反向代理的结构体。

```go
type yurtReverseProxy struct {
    resolver                      apirequest.RequestInfoResolver
    loadBalancer                  remote.LoadBalancer
    cloudHealthChecker            healthchecker.MultipleBackendsHealthChecker
    coordinatorHealtCheckerGetter func() healthchecker.HealthChecker
    localProxy                    http.Handler
    poolProxy                     http.Handler
    maxRequestsInFlight           int
    tenantMgr                     tenant.Interface
    isCoordinatorReady            func() bool
    workingMode                   hubutil.WorkingMode
    enablePoolCoordinator         bool
}
```

反向代理服务

```go
func (p *yurtReverseProxy) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
    if p.workingMode == hubutil.WorkingModeCloud {
        p.loadBalancer.ServeHTTP(rw, req)
        return
    }

    switch {
    case util.IsKubeletLeaseReq(req):
        p.handleKubeletLease(rw, req)
    case util.IsEventCreateRequest(req):
        p.eventHandler(rw, req)
    case util.IsPoolScopedResouceListWatchRequest(req):
        p.poolScopedResouceHandler(rw, req)
    case util.IsSubjectAccessReviewCreateGetRequest(req):
        p.subjectAccessReviewHandler(rw, req)
    default:
        // For resource request that do not need to be handled by pool-coordinator,
        // handling the request with cloud apiserver or local cache.
        if p.cloudHealthChecker.IsHealthy() {
            p.loadBalancer.ServeHTTP(rw, req)
        } else {
            p.localProxy.ServeHTTP(rw, req)
        }
    }
}
```

核心逻辑：如果是云端apiserver可以访问的通，则通过loadbalaner来转发，否则就通过localproxy来转发读取本地节点的数据。

# 5. LoadBalancer

LoadBalancer是个本地的负载均衡逻辑，通过轮询的方式去请求cloud的apiserver，当云边网络通信是正常的时候反向代理apiserver的请求，并做本地缓存持久化。断网的时候则读取本地的缓存数据。

- backends：真实反向代理的后端

- algo: 处理负载均衡策略，轮询或者按优先级

- localCacheMgr: 本地缓存管理的manager

> 代码：[/pkg/yurthub/proxy/remote/loadbalancer.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurthub/proxy/remote/loadbalancer.go)

```go
type loadBalancer struct {
    backends          []*util.RemoteProxy
    algo              loadBalancerAlgo
    localCacheMgr     cachemanager.CacheManager
    filterManager     *manager.Manager
    coordinatorGetter func() poolcoordinator.Coordinator
    workingMode       hubutil.WorkingMode
    stopCh            <-chan struct{}
}
```

## 5.1. NewLoadBalancer

NewLoadBalancer构建一个remote的反向代理，主要包含添加romote server proxy和处理负载均衡策略两部分。

1、添加多个apiserver的地址，创建remote proxy实现反向代理操作。

```go
    backends := make([]*util.RemoteProxy, 0, len(remoteServers))
    for i := range remoteServers {
        b, err := util.NewRemoteProxy(remoteServers[i], lb.modifyResponse, lb.errorHandler, transportMgr, stopCh)
        if err != nil {
            klog.Errorf("could not new proxy backend(%s), %v", remoteServers[i].String(), err)
            continue
        }
        backends = append(backends, b)
    }
```

2、处理负载均衡策略：

```go
    var algo loadBalancerAlgo
    switch lbMode {
    case "rr":
        algo = &rrLoadBalancerAlgo{backends: backends, checker: healthChecker}
    case "priority":
        algo = &priorityLoadBalancerAlgo{backends: backends, checker: healthChecker}
    default:
        algo = &rrLoadBalancerAlgo{backends: backends, checker: healthChecker}
    }
```

## 5.2. loadBalancer.ServeHTTP

loadBalancer实现ServeHTTP的接口，通过负载均衡策略挑选出一个可用的反向代理backend。再调用backend的ServeHTTP方法实现具体的反向代理操作。

```go
    // pick a remote proxy based on the load balancing algorithm.
    rp := lb.algo.PickOne()
    rp.ServeHTTP(rw, req)
```

## 5.3. errorHandler

如果请求apiserver失败，当verb=get/list, 则读取cache中的内容。

```go
func (lb *loadBalancer) errorHandler(rw http.ResponseWriter, req *http.Request, err error) {
    klog.Errorf("remote proxy error handler: %s, %v", hubutil.ReqString(req), err)
    if lb.localCacheMgr == nil || !lb.localCacheMgr.CanCacheFor(req) {
        rw.WriteHeader(http.StatusBadGateway)
        return
    }

    ctx := req.Context()
    if info, ok := apirequest.RequestInfoFrom(ctx); ok {
        if info.Verb == "get" || info.Verb == "list" {
            # 读取cache内容
            if obj, err := lb.localCacheMgr.QueryCache(req); err == nil {
                hubutil.WriteObject(http.StatusOK, obj, rw, req)
                return
            }
        }
    }
    rw.WriteHeader(http.StatusBadGateway)
}
```

## 5.4. QueryCache

```go
// QueryCache get runtime object from backend storage for request
func (cm *cacheManager) QueryCache(req *http.Request) (runtime.Object, error) {
    ctx := req.Context()
    info, ok := apirequest.RequestInfoFrom(ctx)
    if !ok || info == nil || info.Resource == "" {
        return nil, fmt.Errorf("failed to get request info for request %s", util.ReqString(req))
    }
    if !info.IsResourceRequest {
        return nil, fmt.Errorf("failed to QueryCache for getting non-resource request %s", util.ReqString(req))
    }

    # 根据verb查询storage中的数据
    switch info.Verb {
    case "list":
        return cm.queryListObject(req)
    case "get", "patch", "update":
        return cm.queryOneObject(req)
    default:
        return nil, fmt.Errorf("failed to QueryCache, unsupported verb %s of request %s", info.Verb, util.ReqString(req))
    }
}
```

## 5.5. 查询storage中的数据

```go
func (cm *cacheManager) queryOneObject(req *http.Request) (runtime.Object, error) {
    ...
    klog.V(4).Infof("component: %s try to get key: %s", comp, key.Key())
    obj, err := cm.storage.Get(key)
    if err != nil {
        klog.Errorf("failed to get obj %s from storage, %v", key.Key(), err)
        return nil, err
    }
    ...
}
```

目前存储有两种接口实现，一个是本地磁盘存储，一个是etcd存储。以下以磁盘存储为例分析。

> 代码：[/pkg/yurthub/storage/disk/storage.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurthub/storage/disk/storage.go)

```go
// Get will get content from the regular file that specified by key.
// If key points to a dir, return ErrKeyHasNoContent.
func (ds *diskStorage) Get(key storage.Key) ([]byte, error) {
    if err := utils.ValidateKey(key, storageKey{}); err != nil {
        return []byte{}, storage.ErrKeyIsEmpty
    }
    storageKey := key.(storageKey)

    if !ds.lockKey(storageKey) {
        return nil, storage.ErrStorageAccessConflict
    }
    defer ds.unLockKey(storageKey)

    path := filepath.Join(ds.baseDir, storageKey.Key())
    buf, err := ds.fsOperator.Read(path)
    switch err {
    case nil:
        return buf, nil
    case fs.ErrNotExists:
        return nil, storage.ErrStorageNotFound
    case fs.ErrIsNotFile:
        return nil, storage.ErrKeyHasNoContent
    default:
        return buf, fmt.Errorf("failed to read file at %s, %v", path, err)
    }
}
```

# 6. RemoteProxy

RemoteProxy实现一个具体的反向代理操作。

字段说明：

- reverseProxy：http的ReverseProxy

- remoteServer：apiserver的地址

> 代码：[/pkg/yurthub/proxy/util/remote.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurthub/proxy/util/remote.go)

```go
// RemoteProxy is an reverse proxy for remote server
type RemoteProxy struct {
    reverseProxy         *httputil.ReverseProxy
    remoteServer         *url.URL
    currentTransport     http.RoundTripper
    bearerTransport      http.RoundTripper
    upgradeHandler       *proxy.UpgradeAwareHandler
    bearerUpgradeHandler *proxy.UpgradeAwareHandler
    stopCh               <-chan struct{}
}
```

实现ReverseProxy的ServeHTTP接口。

```go
func (rp *RemoteProxy) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
    if httpstream.IsUpgradeRequest(req) {
        klog.V(5).Infof("get upgrade request %s", req.URL)
        if isBearerRequest(req) {
            rp.bearerUpgradeHandler.ServeHTTP(rw, req)
        } else {
            rp.upgradeHandler.ServeHTTP(rw, req)
        }
        return
    }

    rp.reverseProxy.ServeHTTP(rw, req)
}
```

实现错误处理的接口。

```go
func (r *responder) Error(w http.ResponseWriter, req *http.Request, err error) {
    klog.Errorf("failed while proxying request %s, %v", req.URL, err)
    http.Error(w, err.Error(), http.StatusInternalServerError)
}
```

# 7. LocalProxy

LocalProxy是一个当云边网络断开的时候，用于处理本地kubelet请求的数据的代理。

字段说明：

- cacheMgr：主要包含本地cache的一个处理管理器。

> 代码：[/pkg/yurthub/proxy/local/local.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurthub/proxy/local/local.go)

```go
// LocalProxy is responsible for handling requests when remote servers are unhealthy
type LocalProxy struct {
    cacheMgr           manager.CacheManager
    isCloudHealthy     IsHealthy
    isCoordinatorReady IsHealthy
    minRequestTimeout  time.Duration
}
```

LocalProxy实现ServeHTTP接口，根据不同的k8s请求类型，执行不同的操作：

- watch：lp.localWatch(w, req)

- create：lp.localPost(w, req)

- delete, deletecollection: localDelete(w, req)

- list., get, update：lp.localReqCache(w, req)

```go
// ServeHTTP implements http.Handler for LocalProxy
func (lp *LocalProxy) ServeHTTP(w http.ResponseWriter, req *http.Request) {
    var err error
    ctx := req.Context()
    if reqInfo, ok := apirequest.RequestInfoFrom(ctx); ok && reqInfo != nil && reqInfo.IsResourceRequest {
        klog.V(3).Infof("go into local proxy for request %s", hubutil.ReqString(req))
        switch reqInfo.Verb {
        case "watch":
            err = lp.localWatch(w, req)
        case "create":
            err = lp.localPost(w, req)
        case "delete", "deletecollection":
            err = localDelete(w, req)
        default: // list, get, update
            err = lp.localReqCache(w, req)
        }

        if err != nil {
            klog.Errorf("could not proxy local for %s, %v", hubutil.ReqString(req), err)
            util.Err(err, w, req)
        }
    } else {
        klog.Errorf("local proxy does not support request(%s), requestInfo: %s", hubutil.ReqString(req), hubutil.ReqInfoString(reqInfo))
        util.Err(apierrors.NewBadRequest(fmt.Sprintf("local proxy does not support request(%s)", hubutil.ReqString(req))), w, req)
    }
}
```

## 7.1. localReqCache

当边缘网络断连的时候，kubelet执行get list的操作时，通过localReqCache请求本地缓存的数据，返回给kubelet对应的k8s元数据。

```go
// localReqCache handles Get/List/Update requests when remote servers are unhealthy
func (lp *LocalProxy) localReqCache(w http.ResponseWriter, req *http.Request) error {
    if !lp.cacheMgr.CanCacheFor(req) {
        klog.Errorf("can not cache for %s", hubutil.ReqString(req))
        return apierrors.NewBadRequest(fmt.Sprintf("can not cache for %s", hubutil.ReqString(req)))
    }

    obj, err := lp.cacheMgr.QueryCache(req)
    if errors.Is(err, storage.ErrStorageNotFound) || errors.Is(err, hubmeta.ErrGVRNotRecognized) {
        klog.Errorf("object not found for %s", hubutil.ReqString(req))
        reqInfo, _ := apirequest.RequestInfoFrom(req.Context())
        return apierrors.NewNotFound(schema.GroupResource{Group: reqInfo.APIGroup, Resource: reqInfo.Resource}, reqInfo.Name)
    } else if err != nil {
        klog.Errorf("failed to query cache for %s, %v", hubutil.ReqString(req), err)
        return apierrors.NewInternalError(err)
    } else if obj == nil {
        klog.Errorf("no cache object for %s", hubutil.ReqString(req))
        return apierrors.NewInternalError(fmt.Errorf("no cache object for %s", hubutil.ReqString(req)))
    }

    return util.WriteObject(http.StatusOK, obj, w, req)
}
```

核心代码为：

查询本地缓存，返回缓存数据。

```go
obj, err := lp.cacheMgr.QueryCache(req)
return util.WriteObject(http.StatusOK, obj, w, req)
```

# 总结

yurthub是实现边缘断网自治的核心组件，核心逻辑是kubelet向apiserver的请求会通过yurhub进行转发，如果apiserver的接口可通，则将请求结果返回，并存储到本地，如果接口不可通，则读取本地的数据。

yurthub本质是一个反向代理的http server, 核心逻辑主要包括 ：

```go
- proxy: 反向代理的实现
- cachemanager：cache的实现
- storage：本地存储的实现
```

参考：

- [https://github.com/openyurtio/openyurt](https://github.com/openyurtio/openyurt)
