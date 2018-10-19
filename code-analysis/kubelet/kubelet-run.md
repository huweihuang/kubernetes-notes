> 以下代码分析基于 `kubernetes v1.12.0` 版本。
>
> 本文主要分析 https://github.com/kubernetes/kubernetes/tree/v1.12.0/pkg/kubelet 部分的代码。

本文主要分析`NewMainKubelet`和`kubelet.Run`的主要部分，对于kubelet所包含的各种manager的执行逻辑和pod的生命周期管理逻辑待后续文章分析。

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

# 2. [Kubelet.Run](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1382)

Kubelet.Run方法主要将`NewMainKubelet`构造的各种manager运行起来，让各种manager执行相应的功能，大部分manager为常驻进程的方式运行。

```go
// Run starts the kubelet reacting to config updates
func (kl *Kubelet) Run(updates <-chan kubetypes.PodUpdate) {
	...
	if err := kl.initializeModules(); err != nil {
		kl.recorder.Eventf(kl.nodeRef, v1.EventTypeWarning, events.KubeletSetupFailed, err.Error())
		glog.Fatal(err)
	}

	// Start volume manager
	go kl.volumeManager.Run(kl.sourcesReady, wait.NeverStop)

	if kl.kubeClient != nil {
		// Start syncing node status immediately, this may set up things the runtime needs to run.
		go wait.Until(kl.syncNodeStatus, kl.nodeStatusUpdateFrequency, wait.NeverStop)
		go kl.fastStatusUpdateOnce()

		// start syncing lease
		if utilfeature.DefaultFeatureGate.Enabled(features.NodeLease) {
			go kl.nodeLeaseController.Run(wait.NeverStop)
		}
	}
	go wait.Until(kl.updateRuntimeUp, 5*time.Second, wait.NeverStop)

	// Start loop to sync iptables util rules
	if kl.makeIPTablesUtilChains {
		go wait.Until(kl.syncNetworkUtil, 1*time.Minute, wait.NeverStop)
	}

	// Start a goroutine responsible for killing pods (that are not properly
	// handled by pod workers).
	go wait.Until(kl.podKiller, 1*time.Second, wait.NeverStop)

	// Start component sync loops.
	kl.statusManager.Start()
	kl.probeManager.Start()

	// Start syncing RuntimeClasses if enabled.
	if kl.runtimeClassManager != nil {
		go kl.runtimeClassManager.Run(wait.NeverStop)
	}

	// Start the pod lifecycle event generator.
	kl.pleg.Start()
	kl.syncLoop(updates, kl)
}
```

## 2.1. initializeModules

`initializeModules`包含了`imageManager`、`serverCertificateManager`、`oomWatcher`和`resourceAnalyzer`。

- `imageManager`：负责镜像垃圾回收。

- `serverCertificateManager`：负责处理证书。
- `oomWatcher`：监控内存使用，是否发生内存耗尽。
- `resourceAnalyzer`：监控资源使用情况。

```go
// initializeModules will initialize internal modules that do not require the container runtime to be up.
// Note that the modules here must not depend on modules that are not initialized here.
func (kl *Kubelet) initializeModules() error {
	// Prometheus metrics.
	metrics.Register(kl.runtimeCache, collectors.NewVolumeStatsCollector(kl))

	// Setup filesystem directories.
	if err := kl.setupDataDirs(); err != nil {
		return err
	}

	// If the container logs directory does not exist, create it.
	if _, err := os.Stat(ContainerLogsDir); err != nil {
		if err := kl.os.MkdirAll(ContainerLogsDir, 0755); err != nil {
			glog.Errorf("Failed to create directory %q: %v", ContainerLogsDir, err)
		}
	}

	// Start the image manager.
	kl.imageManager.Start()

	// Start the certificate manager if it was enabled.
	if kl.serverCertificateManager != nil {
		kl.serverCertificateManager.Start()
	}

	// Start out of memory watcher.
	if err := kl.oomWatcher.Start(kl.nodeRef); err != nil {
		return fmt.Errorf("Failed to start OOM watcher %v", err)
	}

	// Start resource analyzer
	kl.resourceAnalyzer.Start()

	return nil
}
```

## 2.2. 运行各种manager

### 2.2.1. volumeManager

`volumeManager`主要运行一组异步循环，根据在此节点上安排的pod调整哪些volume需要`attached/detached/mounted/unmounted`。

```go
// Start volume manager
go kl.volumeManager.Run(kl.sourcesReady, wait.NeverStop)
```

### 2.2.2. syncNodeStatus

`syncNodeStatus`通过goroutine的方式定期执行，它将节点的状态同步给master，必要的时候注册kubelet。

```go
if kl.kubeClient != nil {
	// Start syncing node status immediately, this may set up things the runtime needs to run.
	go wait.Until(kl.syncNodeStatus, kl.nodeStatusUpdateFrequency, wait.NeverStop)
	go kl.fastStatusUpdateOnce()

	// start syncing lease
	if utilfeature.DefaultFeatureGate.Enabled(features.NodeLease) {
		go kl.nodeLeaseController.Run(wait.NeverStop)
	}
}
```

### 2.2.3. updateRuntimeUp

`updateRuntimeUp`调用容器运行时状态回调，在容器运行时首次启动时初始化运行时相关模块，如果状态检查失败则返回错误。 如果状态检查正常，在kubelet runtimeState中更新容器运行时的正常运行时间。

```go
go wait.Until(kl.updateRuntimeUp, 5*time.Second, wait.NeverStop)
```

### 2.2.4. syncNetworkUtil

通过循环的方式同步iptables的规则，不过当前代码并没有执行任何操作。

```go
// Start loop to sync iptables util rules
if kl.makeIPTablesUtilChains {
	go wait.Until(kl.syncNetworkUtil, 1*time.Minute, wait.NeverStop)
}
```

### 2.2.5. podKiller

但pod没有被podworker正确处理的时候，启动一个goroutine负责杀死pod。

```go
// Start a goroutine responsible for killing pods (that are not properly
// handled by pod workers).
go wait.Until(kl.podKiller, 1*time.Second, wait.NeverStop)
```

### 2.2.6. statusManager

使用apiserver同步pods状态; 也用作状态缓存。

```go
// Start component sync loops.
kl.statusManager.Start()
```

### 2.2.7. probeManager

处理容器探针

```go
kl.probeManager.Start()
```

### 2.2.8. runtimeClassManager

```go
// Start syncing RuntimeClasses if enabled.
if kl.runtimeClassManager != nil {
	go kl.runtimeClassManager.Run(wait.NeverStop)
}
```

## 2.3. syncLoop

### 2.3.1. PodLifecycleEventGenerator

```go
// Start the pod lifecycle event generator.
kl.pleg.Start()
```

`PodLifecycleEventGenerator`是一个pod生命周期时间生成器接口，具体如下：

```go
// PodLifecycleEventGenerator contains functions for generating pod life cycle events.
type PodLifecycleEventGenerator interface {
	Start()
	Watch() chan *PodLifecycleEvent
	Healthy() (bool, error)
}
```

start方法具体实现如下：

```go
// Start spawns a goroutine to relist periodically.
func (g *GenericPLEG) Start() {
	go wait.Until(g.relist, g.relistPeriod, wait.NeverStop)
}
```

### 2.3.2. syncLoop

`syncLoop`是处理`podUpdate`的循环。 它监听来自三种channel（file，apiserver和http）的更改。 对于看到的任何新更改，将针对所需状态和运行状态运行同步。 如果没有看到配置的变化，将在每个同步频率秒同步最后已知的所需状态。

```go
// syncLoop is the main loop for processing changes. It watches for changes from
// three channels (file, apiserver, and http) and creates a union of them. For
// any new change seen, will run a sync against desired state and running state. If
// no changes are seen to the configuration, will synchronize the last known desired
// state every sync-frequency seconds. Never returns.
func (kl *Kubelet) syncLoop(updates <-chan kubetypes.PodUpdate, handler SyncHandler) {
	glog.Info("Starting kubelet main sync loop.")
	// The resyncTicker wakes up kubelet to checks if there are any pod workers
	// that need to be sync'd. A one-second period is sufficient because the
	// sync interval is defaulted to 10s.
	syncTicker := time.NewTicker(time.Second)
	defer syncTicker.Stop()
	housekeepingTicker := time.NewTicker(housekeepingPeriod)
	defer housekeepingTicker.Stop()
	plegCh := kl.pleg.Watch()
	const (
		base   = 100 * time.Millisecond
		max    = 5 * time.Second
		factor = 2
	)
	duration := base
	for {
		if rs := kl.runtimeState.runtimeErrors(); len(rs) != 0 {
			glog.Infof("skipping pod synchronization - %v", rs)
			// exponential backoff
			time.Sleep(duration)
			duration = time.Duration(math.Min(float64(max), factor*float64(duration)))
			continue
		}
		// reset backoff if we have a success
		duration = base

		kl.syncLoopMonitor.Store(kl.clock.Now())
		if !kl.syncLoopIteration(updates, handler, syncTicker.C, housekeepingTicker.C, plegCh) {
			break
		}
		kl.syncLoopMonitor.Store(kl.clock.Now())
	}
}
```

其中调用了`syncLoopIteration`的函数来执行更具体的监控pod变化的循环。

# 3. [syncLoopIteration](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1870)

`syncLoopIteration`主要通过几种`channel`来对不同类型的事件进行监听并处理。其中包括：`configCh`、`plegCh`、`syncCh`、`houseKeepingCh`、`livenessManager.Updates()`。

## 3.1. configCh

`configCh`将配置更改的pod分派给事件类型的相应处理程序回调，该部分主要通过`SyncHandler`对pod的不同事件进行增删改查等操作。

```go
func (kl *Kubelet) syncLoopIteration(configCh <-chan kubetypes.PodUpdate, handler SyncHandler,
	syncCh <-chan time.Time, housekeepingCh <-chan time.Time, plegCh <-chan *pleg.PodLifecycleEvent) bool {
	select {
	case u, open := <-configCh:
		// Update from a config source; dispatch it to the right handler
		// callback.
		if !open {
			glog.Errorf("Update channel is closed. Exiting the sync loop.")
			return false
		}

		switch u.Op {
		case kubetypes.ADD:
			glog.V(2).Infof("SyncLoop (ADD, %q): %q", u.Source, format.Pods(u.Pods))
			// After restarting, kubelet will get all existing pods through
			// ADD as if they are new pods. These pods will then go through the
			// admission process and *may* be rejected. This can be resolved
			// once we have checkpointing.
			handler.HandlePodAdditions(u.Pods)
		case kubetypes.UPDATE:
			glog.V(2).Infof("SyncLoop (UPDATE, %q): %q", u.Source, format.PodsWithDeletionTimestamps(u.Pods))
			handler.HandlePodUpdates(u.Pods)
		case kubetypes.REMOVE:
			glog.V(2).Infof("SyncLoop (REMOVE, %q): %q", u.Source, format.Pods(u.Pods))
			handler.HandlePodRemoves(u.Pods)
		case kubetypes.RECONCILE:
			glog.V(4).Infof("SyncLoop (RECONCILE, %q): %q", u.Source, format.Pods(u.Pods))
			handler.HandlePodReconcile(u.Pods)
		case kubetypes.DELETE:
			glog.V(2).Infof("SyncLoop (DELETE, %q): %q", u.Source, format.Pods(u.Pods))
			// DELETE is treated as a UPDATE because of graceful deletion.
			handler.HandlePodUpdates(u.Pods)
		case kubetypes.RESTORE:
			glog.V(2).Infof("SyncLoop (RESTORE, %q): %q", u.Source, format.Pods(u.Pods))
			// These are pods restored from the checkpoint. Treat them as new
			// pods.
			handler.HandlePodAdditions(u.Pods)
		case kubetypes.SET:
			// TODO: Do we want to support this?
			glog.Errorf("Kubelet does not support snapshot update")
		}
		...
}
```

可以看出`syncLoopIteration`根据`podUpdate`的值来执行不同的pod操作，具体如下：

- `ADD`：HandlePodAdditions
- `UPDATE`：HandlePodUpdates
- `REMOVE`：HandlePodRemoves
- `RECONCILE`：HandlePodReconcile
- `DELETE`：HandlePodUpdates
- `RESTORE`：HandlePodAdditions
- `podsToSync`：HandlePodSyncs

其中执行pod的handler操作的是`SyncHandler`，该类型是一个接口，实现体为kubelet本身，具体见后续分析。

## 3.2. plegCh

`plegCh`：更新runtime缓存，同步pod。此处调用了`HandlePodSyncs`的函数。

```go
case e := <-plegCh:
	if isSyncPodWorthy(e) {
		// PLEG event for a pod; sync it.
		if pod, ok := kl.podManager.GetPodByUID(e.ID); ok {
			glog.V(2).Infof("SyncLoop (PLEG): %q, event: %#v", format.Pod(pod), e)
			handler.HandlePodSyncs([]*v1.Pod{pod})
		} else {
			// If the pod no longer exists, ignore the event.
			glog.V(4).Infof("SyncLoop (PLEG): ignore irrelevant event: %#v", e)
		}
	}

	if e.Type == pleg.ContainerDied {
		if containerID, ok := e.Data.(string); ok {
			kl.cleanUpContainersInPod(e.ID, containerID)
		}
	}
```

## 3.3. syncCh

`syncCh`：同步所有等待同步的pod。此处调用了`HandlePodSyncs`的函数。

```go
case <-syncCh:
	// Sync pods waiting for sync
	podsToSync := kl.getPodsToSync()
	if len(podsToSync) == 0 {
		break
	}
	glog.V(4).Infof("SyncLoop (SYNC): %d pods; %s", len(podsToSync), format.Pods(podsToSync))
	handler.HandlePodSyncs(podsToSync)
```

## 3.4. livenessManager.Update

`livenessManager.Updates()`：对失败的pod或者liveness检查失败的pod进行sync操作。此处调用了`HandlePodSyncs`的函数。

```go
case update := <-kl.livenessManager.Updates():
	if update.Result == proberesults.Failure {
		// The liveness manager detected a failure; sync the pod.

		// We should not use the pod from livenessManager, because it is never updated after
		// initialization.
		pod, ok := kl.podManager.GetPodByUID(update.PodUID)
		if !ok {
			// If the pod no longer exists, ignore the update.
			glog.V(4).Infof("SyncLoop (container unhealthy): ignore irrelevant update: %#v", update)
			break
		}
		glog.V(1).Infof("SyncLoop (container unhealthy): %q", format.Pod(pod))
		handler.HandlePodSyncs([]*v1.Pod{pod})
	}
```

## 3.5. housekeepingCh

`houseKeepingCh`：触发清理pod。此处调用了`HandlePodCleanups`的函数。

```go
case <-housekeepingCh:
	if !kl.sourcesReady.AllReady() {
		// If the sources aren't ready or volume manager has not yet synced the states,
		// skip housekeeping, as we may accidentally delete pods from unready sources.
		glog.V(4).Infof("SyncLoop (housekeeping, skipped): sources aren't ready yet.")
	} else {
		glog.V(4).Infof("SyncLoop (housekeeping)")
		if err := handler.HandlePodCleanups(); err != nil {
			glog.Errorf("Failed cleaning pods: %v", err)
		}
	}
```

# 4. 总结

## 4.1. NewMainKubelet

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

## 4.2. Kubelet.Run

1. kubelet.Run部分主要执行kubelet包含的各种manager的运行，大部分以常驻goroutine的方式运行。
2. Run函数还执行了`syncLoop`函数，对pod的生命周期进行管理，其中`syncLoop`调用了`syncLoopIteration`函数，该函数根据podUpdate的信息，针对不同的操作，由`SyncHandler`来执行pod的增删改查等生命周期的管理，其中的`syncHandler`包括`HandlePodSyncs`和`HandlePodCleanups`等。
3. `syncLoopIteration`实际执行了pod的操作，此部分设置了几种不同的channel:
   - `configCh`：将配置更改的pod分派给事件类型的相应处理程序回调。
   - `plegCh`：更新runtime缓存，同步pod。
   - `syncCh`：同步所有等待同步的pod。
   - `houseKeepingCh`：触发清理pod。
   - `livenessManager.Updates()`：对失败的pod或者liveness检查失败的pod进行sync操作。



参考文章：

- https://github.com/kubernetes/kubernetes/tree/v1.12.0
- https://github.com/kubernetes/kubernetes/tree/v1.12.0/pkg/kubelet
