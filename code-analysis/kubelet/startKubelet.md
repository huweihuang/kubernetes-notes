# kubelet源码分析（三）之 startKubelet

> 以下代码分析基于 `kubernetes v1.12.0` 版本。
>

本文主要分析`startKubelet`，其中主要是`kubelet.Run`部分，该部分的内容主要是初始化并运行一些manager。对于kubelet所包含的各种manager的执行逻辑和pod的生命周期管理逻辑待后续文章分析。

后续的文章主要会分类分析`pkg/kubelet`部分的代码实现。

`kubelet`的`pkg`代码目录结构：

```bash
kubelet
├── apis  # 定义一些相关接口
├── cadvisor # cadvisor
├── cm # ContainerManager、cpu manger、cgroup manager 
├── config
├── configmap # configmap manager
├── container  # Runtime、ImageService
├── dockershim  # docker的相关调用
├── eviction # eviction manager
├── images  # image manager
├── kubeletconfig  
├── kuberuntime # 核心：kubeGenericRuntimeManager、runtime容器的相关操作
├── lifecycle
├── mountpod
├── network  # pod dns
├── nodelease
├── nodestatus  # MachineInfo、节点相关信息
├── pleg  # PodLifecycleEventGenerator
├── pod  # 核心：pod manager、mirror pod
├── preemption
├── qos  # 资源服务质量，不过暂时内容很少
├── remote # RemoteRuntimeService
├── server
├── stats # StatsProvider
├── status # status manager
├── types  # PodUpdate、PodOperation
├── volumemanager # VolumeManager
├── kubelet.go  # 核心: SyncHandler、kubelet的大部分操作
├── kubelet_getters.go # 各种get操作，例如获取相关目录：getRootDir、getPodsDir、getPluginsDir
├── kubelet_network.go # 
├── kubelet_network_linux.go
├── kubelet_node_status.go # registerWithAPIServer、initialNode、syncNodeStatus
├── kubelet_pods.go # 核心：pod的增删改查等相关操作、podKiller、
├── kubelet_resources.go
├── kubelet_volumes.go # ListVolumesForPod、cleanupOrphanedPodDirs
├── oom_watcher.go  # OOMWatcher
├── pod_container_deletor.go
├── pod_workers.go # 核心：PodWorkers、UpdatePodOptions、syncPodOptions、managePodLoop
├── runonce.go  # RunOnce
├── runtime.go
...
```

# 1. [startKubelet](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/app/server.go#L1018)

`startKubelet`的函数位于`cmd/kubelet/app/server.go`，启动并运行一个kubelet，运行kubelet的逻辑代码位于`pkg/kubelet/kubelet.go`。

**主要内容如下：**

1. 运行一个kubelet，执行kubelet中各种manager的相关逻辑。
2. 运行kubelet server启动监听服务。

> 此部分代码位于cmd/kubelet/app/server.go

```go
func startKubelet(k kubelet.Bootstrap, podCfg *config.PodConfig, kubeCfg *kubeletconfiginternal.KubeletConfiguration, kubeDeps *kubelet.Dependencies, enableServer bool) {
	// start the kubelet
	go wait.Until(func() {
		k.Run(podCfg.Updates())
	}, 0, wait.NeverStop)

	// start the kubelet server
	if enableServer {
		go k.ListenAndServe(net.ParseIP(kubeCfg.Address), uint(kubeCfg.Port), kubeDeps.TLSOptions, kubeDeps.Auth, kubeCfg.EnableDebuggingHandlers, kubeCfg.EnableContentionProfiling)

	}
	if kubeCfg.ReadOnlyPort > 0 {
		go k.ListenAndServeReadOnly(net.ParseIP(kubeCfg.Address), uint(kubeCfg.ReadOnlyPort))
	}
}
```

# 2. [Kubelet.Run](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1382)

`Kubelet.Run`方法主要将`NewMainKubelet`构造的各种manager运行起来，让各种manager执行相应的功能，大部分manager为常驻进程的方式运行。

Kubelet.Run完整代码如下：

> 此部分代码位于pkg/kubelet/kubelet.go

```go
// Run starts the kubelet reacting to config updates
func (kl *Kubelet) Run(updates <-chan kubetypes.PodUpdate) {
	if kl.logServer == nil {
		kl.logServer = http.StripPrefix("/logs/", http.FileServer(http.Dir("/var/log/")))
	}
	if kl.kubeClient == nil {
		glog.Warning("No api server defined - no node status update will be sent.")
	}

	// Start the cloud provider sync manager
	if kl.cloudResourceSyncManager != nil {
		go kl.cloudResourceSyncManager.Run(wait.NeverStop)
	}

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

---

以下对`Kubelet.Run`分段进行分析。

# 3. initializeModules

`initializeModules`包含了`imageManager`、`serverCertificateManager`、`oomWatcher`和`resourceAnalyzer`。

**主要流程如下：**

1. 创建文件系统目录，包括kubelet的root目录、pods的目录、plugins的目录和容器日志目录。
2. 启动imageManager、serverCertificateManager、oomWatcher、resourceAnalyzer。

**各种manager的说明如下：**

- `imageManager`：负责镜像垃圾回收。
- `serverCertificateManager`：负责处理证书。
- `oomWatcher`：监控内存使用，是否发生内存耗尽。
- `resourceAnalyzer`：监控资源使用情况。

完整代码如下：

> 此部分代码位于pkg/kubelet/kubelet.go

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

## 3.1. setupDataDirs

`initializeModules`先创建相关目录。

具体目录如下：

- `ContainerLogsDir`：目录为/var/log/containers。
- `rootDirectory`：由参数传入，一般为`/var/lib/kubelet`。
- `PodsDir`：目录为{rootDirectory}/pods。
- `PluginsDir`：目录为{rootDirectory}/plugins。

**initializeModules中setupDataDirs的相关代码如下：**

```go
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
```

**setupDataDirs代码如下**

```go
// setupDataDirs creates:
// 1.  the root directory
// 2.  the pods directory
// 3.  the plugins directory
func (kl *Kubelet) setupDataDirs() error {
	kl.rootDirectory = path.Clean(kl.rootDirectory)
	if err := os.MkdirAll(kl.getRootDir(), 0750); err != nil {
		return fmt.Errorf("error creating root directory: %v", err)
	}
	if err := kl.mounter.MakeRShared(kl.getRootDir()); err != nil {
		return fmt.Errorf("error configuring root directory: %v", err)
	}
	if err := os.MkdirAll(kl.getPodsDir(), 0750); err != nil {
		return fmt.Errorf("error creating pods directory: %v", err)
	}
	if err := os.MkdirAll(kl.getPluginsDir(), 0750); err != nil {
		return fmt.Errorf("error creating plugins directory: %v", err)
	}
	return nil
}
```

## 3.2. manager

**initializeModules中的manager如下：**

```go
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
```

# 4. 运行各种manager

## 4.1. volumeManager

`volumeManager`主要运行一组异步循环，根据在此节点上安排的pod调整哪些volume需要`attached/detached/mounted/unmounted`。

```go
// Start volume manager
go kl.volumeManager.Run(kl.sourcesReady, wait.NeverStop)
```

`volumeManager.Run`实现代码如下：

```go
func (vm *volumeManager) Run(sourcesReady config.SourcesReady, stopCh <-chan struct{}) {
	defer runtime.HandleCrash()

	go vm.desiredStateOfWorldPopulator.Run(sourcesReady, stopCh)
	glog.V(2).Infof("The desired_state_of_world populator starts")

	glog.Infof("Starting Kubelet Volume Manager")
	go vm.reconciler.Run(stopCh)

	metrics.Register(vm.actualStateOfWorld, vm.desiredStateOfWorld, vm.volumePluginMgr)

	<-stopCh
	glog.Infof("Shutting down Kubelet Volume Manager")
}
```

## 4.2. syncNodeStatus

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

## 4.3. updateRuntimeUp

`updateRuntimeUp`调用容器运行时状态回调，在容器运行时首次启动时初始化运行时相关模块，如果状态检查失败则返回错误。 如果状态检查正常，在kubelet runtimeState中更新容器运行时的正常运行时间。

```go
go wait.Until(kl.updateRuntimeUp, 5*time.Second, wait.NeverStop)
```

## 4.4. syncNetworkUtil

通过循环的方式同步iptables的规则，不过当前代码并没有执行任何操作。

```go
// Start loop to sync iptables util rules
if kl.makeIPTablesUtilChains {
	go wait.Until(kl.syncNetworkUtil, 1*time.Minute, wait.NeverStop)
}
```

## 4.5. podKiller

但pod没有被podworker正确处理的时候，启动一个goroutine负责杀死pod。

```go
// Start a goroutine responsible for killing pods (that are not properly
// handled by pod workers).
go wait.Until(kl.podKiller, 1*time.Second, wait.NeverStop)
```

`podKiller`代码如下：

> 此部分代码位于pkg/kubelet/kubelet_pods.go

```go
// podKiller launches a goroutine to kill a pod received from the channel if
// another goroutine isn't already in action.
func (kl *Kubelet) podKiller() {
	killing := sets.NewString()
	// guard for the killing set
	lock := sync.Mutex{}
	for podPair := range kl.podKillingCh {
		runningPod := podPair.RunningPod
		apiPod := podPair.APIPod

		lock.Lock()
		exists := killing.Has(string(runningPod.ID))
		if !exists {
			killing.Insert(string(runningPod.ID))
		}
		lock.Unlock()

		if !exists {
			go func(apiPod *v1.Pod, runningPod *kubecontainer.Pod) {
				glog.V(2).Infof("Killing unwanted pod %q", runningPod.Name)
				err := kl.killPod(apiPod, runningPod, nil, nil)
				if err != nil {
					glog.Errorf("Failed killing the pod %q: %v", runningPod.Name, err)
				}
				lock.Lock()
				killing.Delete(string(runningPod.ID))
				lock.Unlock()
			}(apiPod, runningPod)
		}
	}
}
```

## 4.6. statusManager

使用apiserver同步pods状态; 也用作状态缓存。

```go
// Start component sync loops.
kl.statusManager.Start()
```

`statusManager.Start`的实现代码如下：

```go
func (m *manager) Start() {
	// Don't start the status manager if we don't have a client. This will happen
	// on the master, where the kubelet is responsible for bootstrapping the pods
	// of the master components.
	if m.kubeClient == nil {
		glog.Infof("Kubernetes client is nil, not starting status manager.")
		return
	}

	glog.Info("Starting to sync pod status with apiserver")
	syncTicker := time.Tick(syncPeriod)
	// syncPod and syncBatch share the same go routine to avoid sync races.
	go wait.Forever(func() {
		select {
		case syncRequest := <-m.podStatusChannel:
			glog.V(5).Infof("Status Manager: syncing pod: %q, with status: (%d, %v) from podStatusChannel",
				syncRequest.podUID, syncRequest.status.version, syncRequest.status.status)
			m.syncPod(syncRequest.podUID, syncRequest.status)
		case <-syncTicker:
			m.syncBatch()
		}
	}, 0)
}
```

## 4.7. probeManager

处理容器探针

```go
kl.probeManager.Start()
```

## 4.8. runtimeClassManager

```go
// Start syncing RuntimeClasses if enabled.
if kl.runtimeClassManager != nil {
	go kl.runtimeClassManager.Run(wait.NeverStop)
}
```

## 4.9. PodLifecycleEventGenerator

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

## 4.10. syncLoop

最后调用`syncLoop`来执行同步变化变更的循环。

```go
kl.syncLoop(updates, kl)
```

# 5. syncLoop

`syncLoop`是处理变化的循环。 它监听来自三种channel（file，apiserver和http）的更改。 对于看到的任何新更改，将针对所需状态和运行状态运行同步。 如果没有看到配置的变化，将在每个同步频率秒同步最后已知的所需状态。

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

其中调用了`syncLoopIteration`的函数来执行更具体的监控pod变化的循环。`syncLoopIteration`代码逻辑待后续单独分析。

# 6. 总结

## 6.1. 基本流程

`Kubelet.Run`主要流程如下：

1. 初始化模块，其实就是运行`imageManager`、`serverCertificateManager`、`oomWatcher`、`resourceAnalyzer`。
2. 运行各种manager，大部分以常驻goroutine的方式运行，其中包括`volumeManager`、`statusManager`等。
3. 执行处理变更的循环函数`syncLoop`，对pod的生命周期进行管理。

**syncLoop：**

`syncLoop`函数，对pod的生命周期进行管理，其中`syncLoop`调用了`syncLoopIteration`函数，该函数根据`podUpdate`的信息，针对不同的操作，由`SyncHandler`来执行pod的增删改查等生命周期的管理，其中的`syncHandler`包括`HandlePodSyncs`和`HandlePodCleanups`等。该部分逻辑待后续文章具体分析。

## 6.2. Manager

以下介绍kubelet运行时涉及到的manager的内容。

| manager                  | 说明                                               |
| ------------------------ | -------------------------------------------------- |
| imageManager             | 负责镜像垃圾回收                                   |
| serverCertificateManager | 负责处理证书                                       |
| oomWatcher               | 监控内存使用，是否发生内存耗尽即OOM                |
| resourceAnalyzer         | 监控资源使用情况                                   |
| volumeManager            | 对pod执行`attached/detached/mounted/unmounted`操作 |
| statusManager            | 使用apiserver同步pods状态; 也用作状态缓存          |
| probeManager             | 处理容器探针                                       |
| runtimeClassManager      | 同步RuntimeClasses                                 |
| podKiller                | 负责杀死pod                                        |





参考文章：

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/app/server.go>

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go>
