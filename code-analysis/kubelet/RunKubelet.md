# kubelet源码分析（三）之 RunKubelet

> 以下代码分析基于 `kubernetes v1.12.0` 版本。
>
> 本文主要分析 https://github.com/kubernetes/kubernetes/tree/v1.12.0/pkg/kubelet 部分的代码。

本文主要分析`kubelet.Run`的主要部分，对于kubelet所包含的各种manager的执行逻辑和pod的生命周期管理逻辑待后续文章分析。


# 1. [Kubelet.Run](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1382)

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

## 1.1. initializeModules

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

## 1.2. 运行各种manager

### 1.2.1. volumeManager

`volumeManager`主要运行一组异步循环，根据在此节点上安排的pod调整哪些volume需要`attached/detached/mounted/unmounted`。

```go
// Start volume manager
go kl.volumeManager.Run(kl.sourcesReady, wait.NeverStop)
```

### 1.2.2. syncNodeStatus

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

### 1.2.3. updateRuntimeUp

`updateRuntimeUp`调用容器运行时状态回调，在容器运行时首次启动时初始化运行时相关模块，如果状态检查失败则返回错误。 如果状态检查正常，在kubelet runtimeState中更新容器运行时的正常运行时间。

```go
go wait.Until(kl.updateRuntimeUp, 5*time.Second, wait.NeverStop)
```

### 1.2.4. syncNetworkUtil

通过循环的方式同步iptables的规则，不过当前代码并没有执行任何操作。

```go
// Start loop to sync iptables util rules
if kl.makeIPTablesUtilChains {
	go wait.Until(kl.syncNetworkUtil, 1*time.Minute, wait.NeverStop)
}
```

### 1.2.5. podKiller

但pod没有被podworker正确处理的时候，启动一个goroutine负责杀死pod。

```go
// Start a goroutine responsible for killing pods (that are not properly
// handled by pod workers).
go wait.Until(kl.podKiller, 1*time.Second, wait.NeverStop)
```

### 1.2.6. statusManager

使用apiserver同步pods状态; 也用作状态缓存。

```go
// Start component sync loops.
kl.statusManager.Start()
```

### 1.2.7. probeManager

处理容器探针

```go
kl.probeManager.Start()
```

### 1.2.8. runtimeClassManager

```go
// Start syncing RuntimeClasses if enabled.
if kl.runtimeClassManager != nil {
	go kl.runtimeClassManager.Run(wait.NeverStop)
}
```

## 1.3. syncLoop

### 1.3.1. PodLifecycleEventGenerator

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

### 1.3.2. syncLoop

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

# 2. [syncLoopIteration](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1870)

`syncLoopIteration`主要通过几种`channel`来对不同类型的事件进行监听并处理。其中包括：`configCh`、`plegCh`、`syncCh`、`houseKeepingCh`、`livenessManager.Updates()`。

## 2.1. configCh

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

## 2.2. plegCh

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

## 2.3. syncCh

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

## 2.4. livenessManager.Update

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

## 2.5. housekeepingCh

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

# 3. 总结

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
