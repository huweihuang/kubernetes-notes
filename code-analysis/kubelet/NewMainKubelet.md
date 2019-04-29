# kubelet源码分析（二）之 NewMainKubelet

> 以下代码分析基于 `kubernetes v1.12.0` 版本。
>
> 本文主要分析 https://github.com/kubernetes/kubernetes/tree/v1.12.0/pkg/kubelet 部分的代码。

本文主要分析kubelet中的`NewMainKubelet`部分。

# 1. [NewMainKubelet](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L327)

`NewMainKubelet`主要用来初始化和构造一个`kubelet`结构体，kubelet结构体定义参考:https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L888

```go
// NewMainKubelet instantiates a new Kubelet object along with all the required internal modules.
// No initialization of Kubelet and its modules should happen here.
func NewMainKubelet(kubeCfg *kubeletconfiginternal.KubeletConfiguration,
	kubeDeps *Dependencies,
	crOptions *config.ContainerRuntimeOptions,
	containerRuntime string,
	runtimeCgroups string,
	hostnameOverride string,
	nodeIP string,
	providerID string,
	cloudProvider string,
	certDirectory string,
	rootDirectory string,
	registerNode bool,
	registerWithTaints []api.Taint,
	allowedUnsafeSysctls []string,
	remoteRuntimeEndpoint string,
	remoteImageEndpoint string,
	experimentalMounterPath string,
	experimentalKernelMemcgNotification bool,
	experimentalCheckNodeCapabilitiesBeforeMount bool,
	experimentalNodeAllocatableIgnoreEvictionThreshold bool,
	minimumGCAge metav1.Duration,
	maxPerPodContainerCount int32,
	maxContainerCount int32,
	masterServiceNamespace string,
	registerSchedulable bool,
	nonMasqueradeCIDR string,
	keepTerminatedPodVolumes bool,
	nodeLabels map[string]string,
	seccompProfileRoot string,
	bootstrapCheckpointPath string,
	nodeStatusMaxImages int32) (*Kubelet, error) {
    ...
}    
```

## 1.1. PodConfig

通过`makePodSourceConfig`生成Pod config。

```go
if kubeDeps.PodConfig == nil {
	var err error
	kubeDeps.PodConfig, err = makePodSourceConfig(kubeCfg, kubeDeps, nodeName, bootstrapCheckpointPath)
	if err != nil {
		return nil, err
	}
}
```

### 1.1.1. makePodSourceConfig

```go
// makePodSourceConfig creates a config.PodConfig from the given
// KubeletConfiguration or returns an error.
func makePodSourceConfig(kubeCfg *kubeletconfiginternal.KubeletConfiguration, kubeDeps *Dependencies, nodeName types.NodeName, bootstrapCheckpointPath string) (*config.PodConfig, error) {
	...
	// source of all configuration
	cfg := config.NewPodConfig(config.PodConfigNotificationIncremental, kubeDeps.Recorder)
	
    // define file config source
	if kubeCfg.StaticPodPath != "" {
		glog.Infof("Adding pod path: %v", kubeCfg.StaticPodPath)
		config.NewSourceFile(kubeCfg.StaticPodPath, nodeName, kubeCfg.FileCheckFrequency.Duration, cfg.Channel(kubetypes.FileSource))
	}

	// define url config source
	if kubeCfg.StaticPodURL != "" {
		glog.Infof("Adding pod url %q with HTTP header %v", kubeCfg.StaticPodURL, manifestURLHeader)
		config.NewSourceURL(kubeCfg.StaticPodURL, manifestURLHeader, nodeName, kubeCfg.HTTPCheckFrequency.Duration, cfg.Channel(kubetypes.HTTPSource))
	}
    
	// Restore from the checkpoint path
	// NOTE: This MUST happen before creating the apiserver source
	// below, or the checkpoint would override the source of truth.
	...
	if kubeDeps.KubeClient != nil {
		glog.Infof("Watching apiserver")
		if updatechannel == nil {
			updatechannel = cfg.Channel(kubetypes.ApiserverSource)
		}
		config.NewSourceApiserver(kubeDeps.KubeClient, nodeName, updatechannel)
	}
	return cfg, nil
}
```

### 1.1.2. NewPodConfig

```go
// NewPodConfig creates an object that can merge many configuration sources into a stream
// of normalized updates to a pod configuration.
func NewPodConfig(mode PodConfigNotificationMode, recorder record.EventRecorder) *PodConfig {
	updates := make(chan kubetypes.PodUpdate, 50)
	storage := newPodStorage(updates, mode, recorder)
	podConfig := &PodConfig{
		pods:    storage,
		mux:     config.NewMux(storage),
		updates: updates,
		sources: sets.String{},
	}
	return podConfig
}
```

### 1.1.3. NewSourceApiserver

```go
// NewSourceApiserver creates a config source that watches and pulls from the apiserver.
func NewSourceApiserver(c clientset.Interface, nodeName types.NodeName, updates chan<- interface{}) {
	lw := cache.NewListWatchFromClient(c.CoreV1().RESTClient(), "pods", metav1.NamespaceAll, fields.OneTermEqualSelector(api.PodHostField, string(nodeName)))
	newSourceApiserverFromLW(lw, updates)
}
```

## 1.2. Lister

`serviceLister`和`nodeLister`分别通过`List-Watch`机制监听`service`和`node`的列表变化。

### 1.2.1. serviceLister

```go
serviceIndexer := cache.NewIndexer(cache.MetaNamespaceKeyFunc, cache.Indexers{cache.NamespaceIndex: cache.MetaNamespaceIndexFunc})
if kubeDeps.KubeClient != nil {
	serviceLW := cache.NewListWatchFromClient(kubeDeps.KubeClient.CoreV1().RESTClient(), "services", metav1.NamespaceAll, fields.Everything())
	r := cache.NewReflector(serviceLW, &v1.Service{}, serviceIndexer, 0)
	go r.Run(wait.NeverStop)
}
serviceLister := corelisters.NewServiceLister(serviceIndexer)
```

### 1.2.2. nodeLister

```go
nodeIndexer := cache.NewIndexer(cache.MetaNamespaceKeyFunc, cache.Indexers{})
if kubeDeps.KubeClient != nil {
	fieldSelector := fields.Set{api.ObjectNameField: string(nodeName)}.AsSelector()
	nodeLW := cache.NewListWatchFromClient(kubeDeps.KubeClient.CoreV1().RESTClient(), "nodes", metav1.NamespaceAll, fieldSelector)
	r := cache.NewReflector(nodeLW, &v1.Node{}, nodeIndexer, 0)
	go r.Run(wait.NeverStop)
}
nodeInfo := &predicates.CachedNodeInfo{NodeLister: corelisters.NewNodeLister(nodeIndexer)}
```

## 1.3. 各种Manager

### 1.3.1. containerRefManager

```go
containerRefManager := kubecontainer.NewRefManager()
```

### 1.3.2. oomWatcher

```go
oomWatcher := NewOOMWatcher(kubeDeps.CAdvisorInterface, kubeDeps.Recorder)
```

### 1.3.3. dnsConfigurer

```go
clusterDNS := make([]net.IP, 0, len(kubeCfg.ClusterDNS))
for _, ipEntry := range kubeCfg.ClusterDNS {
	ip := net.ParseIP(ipEntry)
	if ip == nil {
		glog.Warningf("Invalid clusterDNS ip '%q'", ipEntry)
	} else {
		clusterDNS = append(clusterDNS, ip)
	}
}
...

dns.NewConfigurer(kubeDeps.Recorder, nodeRef, parsedNodeIP, clusterDNS, kubeCfg.ClusterDomain, kubeCfg.ResolverConfig),
```

### 1.3.4. secretManager & configMapManager

```go
var secretManager secret.Manager
var configMapManager configmap.Manager
switch kubeCfg.ConfigMapAndSecretChangeDetectionStrategy {
case kubeletconfiginternal.WatchChangeDetectionStrategy:
	secretManager = secret.NewWatchingSecretManager(kubeDeps.KubeClient)
	configMapManager = configmap.NewWatchingConfigMapManager(kubeDeps.KubeClient)
case kubeletconfiginternal.TTLCacheChangeDetectionStrategy:
	secretManager = secret.NewCachingSecretManager(
		kubeDeps.KubeClient, manager.GetObjectTTLFromNodeFunc(klet.GetNode))
	configMapManager = configmap.NewCachingConfigMapManager(
		kubeDeps.KubeClient, manager.GetObjectTTLFromNodeFunc(klet.GetNode))
case kubeletconfiginternal.GetChangeDetectionStrategy:
	secretManager = secret.NewSimpleSecretManager(kubeDeps.KubeClient)
	configMapManager = configmap.NewSimpleConfigMapManager(kubeDeps.KubeClient)
default:
	return nil, fmt.Errorf("unknown configmap and secret manager mode: %v", kubeCfg.ConfigMapAndSecretChangeDetectionStrategy)
}

klet.secretManager = secretManager
klet.configMapManager = configMapManager
```

### 1.3.5. livenessManager

```go
klet.livenessManager = proberesults.NewManager()
```

### 1.3.6. podManager

```go
// podManager is also responsible for keeping secretManager and configMapManager contents up-to-date.
klet.podManager = kubepod.NewBasicPodManager(kubepod.NewBasicMirrorClient(klet.kubeClient), secretManager, configMapManager, checkpointManager)
```

### 1.3.7. resourceAnalyzer

```go
klet.resourceAnalyzer = serverstats.NewResourceAnalyzer(klet, kubeCfg.VolumeStatsAggPeriod.Duration)
```

### 1.3.8. containerGC

```go
// setup containerGC
containerGC, err := kubecontainer.NewContainerGC(klet.containerRuntime, containerGCPolicy, klet.sourcesReady)
if err != nil {
	return nil, err
}
klet.containerGC = containerGC
klet.containerDeletor = newPodContainerDeletor(klet.containerRuntime, integer.IntMax(containerGCPolicy.MaxPerPodContainer, minDeadContainerInPod))
```

### 1.3.9. imageManager

```go
// setup imageManager
imageManager, err := images.NewImageGCManager(klet.containerRuntime, klet.StatsProvider, kubeDeps.Recorder, nodeRef, imageGCPolicy, crOptions.PodSandboxImage)
if err != nil {
	return nil, fmt.Errorf("failed to initialize image manager: %v", err)
}
klet.imageManager = imageManager
```

### 1.3.10. statusManager

```go
klet.statusManager = status.NewManager(klet.kubeClient, klet.podManager, klet)
```

### 1.3.11. probeManager

```go
klet.probeManager = prober.NewManager(
	klet.statusManager,
	klet.livenessManager,
	klet.runner,
	containerRefManager,
	kubeDeps.Recorder)
```

### 1.3.12. tokenManager

```go
tokenManager := token.NewManager(kubeDeps.KubeClient)
```

### 1.3.13. volumePluginMgr

```go
klet.volumePluginMgr, err =
	NewInitializedVolumePluginMgr(klet, secretManager, configMapManager, tokenManager, kubeDeps.VolumePlugins, kubeDeps.DynamicPluginProber)
if err != nil {
	return nil, err
}
if klet.enablePluginsWatcher {
	klet.pluginWatcher = pluginwatcher.NewWatcher(klet.getPluginsDir())
}
```

### 1.3.14. volumeManager

```go
// setup volumeManager
klet.volumeManager = volumemanager.NewVolumeManager(
	kubeCfg.EnableControllerAttachDetach,
	nodeName,
	klet.podManager,
	klet.statusManager,
	klet.kubeClient,
	klet.volumePluginMgr,
	klet.containerRuntime,
	kubeDeps.Mounter,
	klet.getPodsDir(),
	kubeDeps.Recorder,
	experimentalCheckNodeCapabilitiesBeforeMount,
	keepTerminatedPodVolumes)
```

### 1.3.15. evictionManager

```go
// setup eviction manager
evictionManager, evictionAdmitHandler := eviction.NewManager(klet.resourceAnalyzer, evictionConfig, killPodNow(klet.podWorkers, kubeDeps.Recorder), klet.imageManager, klet.containerGC, kubeDeps.Recorder, nodeRef, klet.clock)

klet.evictionManager = evictionManager
klet.admitHandlers.AddPodAdmitHandler(evictionAdmitHandler)
```

## 1.4. containerRuntime

目前pod所使用的`runtime`只有`docker`和`remote`两种，`rkt`已经废弃。

```go
if containerRuntime == "rkt" {
	glog.Fatalln("rktnetes has been deprecated in favor of rktlet. Please see https://github.com/kubernetes-incubator/rktlet for more information.")
}
```

当`runtime`是`docker`的时候，会执行`docker`相关操作。

```go
	switch containerRuntime {
	case kubetypes.DockerContainerRuntime:
		// Create and start the CRI shim running as a grpc server.
		...
		// The unix socket for kubelet <-> dockershim communication.
		...
		// Create dockerLegacyService when the logging driver is not supported.
		...
	case kubetypes.RemoteContainerRuntime:
		// No-op.
		break
	default:
		return nil, fmt.Errorf("unsupported CRI runtime: %q", containerRuntime)
	}
```

### 1.4.1. NewDockerService

```go
// Create and start the CRI shim running as a grpc server.
streamingConfig := getStreamingConfig(kubeCfg, kubeDeps, crOptions)
ds, err := dockershim.NewDockerService(kubeDeps.DockerClientConfig, crOptions.PodSandboxImage, streamingConfig,
	&pluginSettings, runtimeCgroups, kubeCfg.CgroupDriver, crOptions.DockershimRootDirectory, !crOptions.RedirectContainerStreaming)
if err != nil {
	return nil, err
}
if crOptions.RedirectContainerStreaming {
	klet.criHandler = ds
}
```

### 1.4.2. NewDockerServer

```go
// The unix socket for kubelet <-> dockershim communication.
glog.V(5).Infof("RemoteRuntimeEndpoint: %q, RemoteImageEndpoint: %q",
	remoteRuntimeEndpoint,
	remoteImageEndpoint)
glog.V(2).Infof("Starting the GRPC server for the docker CRI shim.")
server := dockerremote.NewDockerServer(remoteRuntimeEndpoint, ds)
if err := server.Start(); err != nil {
	return nil, err
}
```

### 1.4.3. DockerServer.Start

```go
// Start starts the dockershim grpc server.
func (s *DockerServer) Start() error {
	// Start the internal service.
	if err := s.service.Start(); err != nil {
		glog.Errorf("Unable to start docker service")
		return err
	}

	glog.V(2).Infof("Start dockershim grpc server")
	l, err := util.CreateListener(s.endpoint)
	if err != nil {
		return fmt.Errorf("failed to listen on %q: %v", s.endpoint, err)
	}
	// Create the grpc server and register runtime and image services.
	s.server = grpc.NewServer(
		grpc.MaxRecvMsgSize(maxMsgSize),
		grpc.MaxSendMsgSize(maxMsgSize),
	)
	runtimeapi.RegisterRuntimeServiceServer(s.server, s.service)
	runtimeapi.RegisterImageServiceServer(s.server, s.service)
	go func() {
		if err := s.server.Serve(l); err != nil {
			glog.Fatalf("Failed to serve connections: %v", err)
		}
	}()
	return nil
}
```

## 1.5. podWorker

构造`podWorkers`和`workQueue`。

```go
klet.workQueue = queue.NewBasicWorkQueue(klet.clock)
klet.podWorkers = newPodWorkers(klet.syncPod, kubeDeps.Recorder, klet.workQueue, klet.resyncInterval, backOffPeriod, klet.podCache)
```

### 1.5.1. PodWorkers接口

```go
// PodWorkers is an abstract interface for testability.
type PodWorkers interface {
	UpdatePod(options *UpdatePodOptions)
	ForgetNonExistingPodWorkers(desiredPods map[types.UID]empty)
	ForgetWorker(uid types.UID)
}
```

`podWorker`主要用来对pod相应事件进行处理和同步，包含以下三个方法：`UpdatePod`、`ForgetNonExistingPodWorkers`、`ForgetWorker`。


# 2. 总结

1. `NewMainKubelet`主要用来构造`kubelet`结构体，其中kubelet除了包含必要的配置和client（例如：kubeClient、csiClient等）外，最主要的包含各种manager来管理不同的任务。
2. 核心的manager有以下几种：
   - `oomWatcher`：监控pod内存是否发生OOM。
   - `podManager`：管理pod的生命周期，包括对pod的增删改查操作等。
   - `containerGC`：对死亡容器进行垃圾回收。
   - `imageManager`：对容器镜像进行垃圾回收。
   - `statusManager`：与apiserver同步pod状态，同时也作状态缓存。
   - `volumeManager`：对pod的volume进行`attached/detached/mounted/unmounted`操作。
   - `evictionManager`：保证节点稳定，必要时对pod进行驱逐（例如资源不足的情况下）。

3. `NewMainKubelet`还包含了`serviceLister`和`nodeLister`来监听`service`和`node`的列表变化。
4. kubelet使用到的`containerRuntime`目前主要是`docker`，其中`rkt`已废弃。`NewMainKubelet`启动了`dockershim grpc server`来执行docker相关操作。
5. 构建了`podWorker`来对pod相关的更新逻辑进行处理。


参考文章：

- https://github.com/kubernetes/kubernetes/tree/v1.12.0
- https://github.com/kubernetes/kubernetes/tree/v1.12.0/pkg/kubelet
