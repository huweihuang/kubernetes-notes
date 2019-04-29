# kubelet源码分析（四）之 syncLoopIteration

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析kubelet中`syncLoopIteration`部分。`syncLoopIteration`通过几种`channel`来对不同类型的事件进行监听并做增删改查的处理。

# 1. syncLoop

`syncLoop`是处理变更的循环。 它监听来自三种channel（file，apiserver和http）的更改。 对于看到的任何新更改，将针对所需状态和运行状态运行同步。 如果没有看到配置的变化，将在每个同步频率秒同步最后已知的所需状态。

> 此部分代码位于pkg/kubelet/kubelet.go

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

`syncLoopIteration`实际执行了pod的操作，此部分设置了几种不同的channel:

- `configCh`：将配置更改的pod分派给事件类型的相应处理程序回调。
- `plegCh`：更新runtime缓存，同步pod。
- `syncCh`：同步所有等待同步的pod。
- `houseKeepingCh`：触发清理pod。
- `livenessManager.Updates()`：对失败的pod或者liveness检查失败的pod进行sync操作。

> syncLoopIteration部分代码位于pkg/kubelet/kubelet.go

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

# 3. [SyncHandler](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L177)

`SyncHandler`是一个定义Pod的不同Handler的接口，具体是实现者是`kubelet`，该接口的方法主要在[syncLoopIteration](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1870)中调用，接口定义如下：

```go
// SyncHandler is an interface implemented by Kubelet, for testability
type SyncHandler interface {
	HandlePodAdditions(pods []*v1.Pod)
	HandlePodUpdates(pods []*v1.Pod)
	HandlePodRemoves(pods []*v1.Pod)
	HandlePodReconcile(pods []*v1.Pod)
	HandlePodSyncs(pods []*v1.Pod)
	HandlePodCleanups() error
}
```

> SyncHandler部分代码位于pkg/kubelet/kubelet.go

## 3.1. [HandlePodAdditions](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2021)

`HandlePodAdditions`先根据pod创建时间对pod进行排序，然后遍历pod列表，来执行pod的相关操作。

```go
// HandlePodAdditions is the callback in SyncHandler for pods being added from
// a config source.
func (kl *Kubelet) HandlePodAdditions(pods []*v1.Pod) {
	start := kl.clock.Now()
	sort.Sort(sliceutils.PodsByCreationTime(pods))
	for _, pod := range pods {
    ...
    }
}    
```

将pod添加到pod manager中。

```go
for _, pod := range pods {
	// Responsible for checking limits in resolv.conf
	if kl.dnsConfigurer != nil && kl.dnsConfigurer.ResolverConfig != "" {
		kl.dnsConfigurer.CheckLimitsForResolvConf()
	}
	existingPods := kl.podManager.GetPods()
	// Always add the pod to the pod manager. Kubelet relies on the pod
	// manager as the source of truth for the desired state. If a pod does
	// not exist in the pod manager, it means that it has been deleted in
	// the apiserver and no action (other than cleanup) is required.
	kl.podManager.AddPod(pod)
    ...
}    
```

如果是mirror pod，则对mirror pod进行处理。

```go
if kubepod.IsMirrorPod(pod) {
	kl.handleMirrorPod(pod, start)
	continue
}
```

如果当前pod的状态不是`Terminated`状态，则判断是否接受该pod，如果不接受则将pod状态改为`Failed`。

```go
if !kl.podIsTerminated(pod) {
	// Only go through the admission process if the pod is not
	// terminated.

	// We failed pods that we rejected, so activePods include all admitted
	// pods that are alive.
	activePods := kl.filterOutTerminatedPods(existingPods)

	// Check if we can admit the pod; if not, reject it.
	if ok, reason, message := kl.canAdmitPod(activePods, pod); !ok {
		kl.rejectPod(pod, reason, message)
		continue
	}
}
```

执行`dispatchWork`函数，该函数是syncHandler中调用到的核心函数，该函数在pod worker中启动一个异步循环，来分派pod的相关操作。该函数的具体操作待后续分析。

```go
mirrorPod, _ := kl.podManager.GetMirrorPodByPod(pod)
kl.dispatchWork(pod, kubetypes.SyncPodCreate, mirrorPod, start)
```

最后加pod添加到probe manager中。

```go
kl.probeManager.AddPod(pod)
```

## 3.2. [HandlePodUpdates](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2063)

`HandlePodUpdates`同样遍历pod列表，执行相应的操作。

```go
// HandlePodUpdates is the callback in the SyncHandler interface for pods
// being updated from a config source.
func (kl *Kubelet) HandlePodUpdates(pods []*v1.Pod) {
	start := kl.clock.Now()
	for _, pod := range pods {
	...
	}
}
```

将pod更新到pod manager中。

```go
for _, pod := range pods {
	// Responsible for checking limits in resolv.conf
	if kl.dnsConfigurer != nil && kl.dnsConfigurer.ResolverConfig != "" {
		kl.dnsConfigurer.CheckLimitsForResolvConf()
	}
	kl.podManager.UpdatePod(pod)
    ...
}    
```

如果是mirror pod，则对mirror pod进行处理。

```go
if kubepod.IsMirrorPod(pod) {
	kl.handleMirrorPod(pod, start)
	continue
}
```

执行`dispatchWork`函数。

```go
// TODO: Evaluate if we need to validate and reject updates.

mirrorPod, _ := kl.podManager.GetMirrorPodByPod(pod)
kl.dispatchWork(pod, kubetypes.SyncPodUpdate, mirrorPod, start)
```

## 3.3. [HandlePodRemoves](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2084)

`HandlePodRemoves`遍历pod列表。

```go
// HandlePodRemoves is the callback in the SyncHandler interface for pods
// being removed from a config source.
func (kl *Kubelet) HandlePodRemoves(pods []*v1.Pod) {
	start := kl.clock.Now()
	for _, pod := range pods {
    ...
    }
}    
```

从pod manager中删除pod。

```go
for _, pod := range pods {
	kl.podManager.DeletePod(pod)
    ...
}    
```

如果是mirror pod，则对mirror pod进行处理。

```go
if kubepod.IsMirrorPod(pod) {
	kl.handleMirrorPod(pod, start)
	continue
}
```

调用kubelet的`deletePod`函数来删除pod。

```go
// Deletion is allowed to fail because the periodic cleanup routine
// will trigger deletion again.
if err := kl.deletePod(pod); err != nil {
	glog.V(2).Infof("Failed to delete pod %q, err: %v", format.Pod(pod), err)
}
```

`deletePod` 函数将需要删除的pod加入`podKillingCh`的channel中，有`podKiller`监听这个channel去执行删除任务，实现如下：

```go
// deletePod deletes the pod from the internal state of the kubelet by:
// 1.  stopping the associated pod worker asynchronously
// 2.  signaling to kill the pod by sending on the podKillingCh channel
//
// deletePod returns an error if not all sources are ready or the pod is not
// found in the runtime cache.
func (kl *Kubelet) deletePod(pod *v1.Pod) error {
	if pod == nil {
		return fmt.Errorf("deletePod does not allow nil pod")
	}
	if !kl.sourcesReady.AllReady() {
		// If the sources aren't ready, skip deletion, as we may accidentally delete pods
		// for sources that haven't reported yet.
		return fmt.Errorf("skipping delete because sources aren't ready yet")
	}
	kl.podWorkers.ForgetWorker(pod.UID)

	// Runtime cache may not have been updated to with the pod, but it's okay
	// because the periodic cleanup routine will attempt to delete again later.
	runningPods, err := kl.runtimeCache.GetPods()
	if err != nil {
		return fmt.Errorf("error listing containers: %v", err)
	}
	runningPod := kubecontainer.Pods(runningPods).FindPod("", pod.UID)
	if runningPod.IsEmpty() {
		return fmt.Errorf("pod not found")
	}
	podPair := kubecontainer.PodPair{APIPod: pod, RunningPod: &runningPod}

	kl.podKillingCh <- &podPair
	// TODO: delete the mirror pod here?

	// We leave the volume/directory cleanup to the periodic cleanup routine.
	return nil
}
```

从probe manager中移除pod。

```go
kl.probeManager.RemovePod(pod)
```

## 3.4. [HandlePodReconcile](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2103)

遍历pod列表。

```go
// HandlePodReconcile is the callback in the SyncHandler interface for pods
// that should be reconciled.
func (kl *Kubelet) HandlePodReconcile(pods []*v1.Pod) {
	start := kl.clock.Now()
	for _, pod := range pods {
        ...
    }
}   
```

将pod更新到pod manager中。

```go
for _, pod := range pods {
	// Update the pod in pod manager, status manager will do periodically reconcile according
	// to the pod manager.
	kl.podManager.UpdatePod(pod)
    ...
}    
```

必要时调整pod的`Ready`状态，执行`dispatchWork`函数。

```go
// Reconcile Pod "Ready" condition if necessary. Trigger sync pod for reconciliation.
if status.NeedToReconcilePodReadiness(pod) {
	mirrorPod, _ := kl.podManager.GetMirrorPodByPod(pod)
	kl.dispatchWork(pod, kubetypes.SyncPodSync, mirrorPod, start)
}
```

如果pod被设定为需要被驱逐的，则删除pod中的容器。

```go
// After an evicted pod is synced, all dead containers in the pod can be removed.
if eviction.PodIsEvicted(pod.Status) {
	if podStatus, err := kl.podCache.Get(pod.UID); err == nil {
		kl.containerDeletor.deleteContainersInPod("", podStatus, true)
	}
}
```

## 3.5. [HandlePodSyncs](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2127)

`HandlePodSyncs`是`syncHandler`接口回调函数，调用`dispatchWork`，通过pod worker来执行任务。

```go
// HandlePodSyncs is the callback in the syncHandler interface for pods
// that should be dispatched to pod workers for sync.
func (kl *Kubelet) HandlePodSyncs(pods []*v1.Pod) {
	start := kl.clock.Now()
	for _, pod := range pods {
		mirrorPod, _ := kl.podManager.GetMirrorPodByPod(pod)
		kl.dispatchWork(pod, kubetypes.SyncPodSync, mirrorPod, start)
	}
}
```

## 3.6. [HandlePodCleanups](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet_pods.go#L979)

`HandlePodCleanups`主要用来执行pod的清理任务，其中包括`terminating`的pod，`orphaned`的pod等。

首先查看pod使用到的cgroup。

```go
// HandlePodCleanups performs a series of cleanup work, including terminating
// pod workers, killing unwanted pods, and removing orphaned volumes/pod
// directories.
// NOTE: This function is executed by the main sync loop, so it
// should not contain any blocking calls.
func (kl *Kubelet) HandlePodCleanups() error {
	// The kubelet lacks checkpointing, so we need to introspect the set of pods
	// in the cgroup tree prior to inspecting the set of pods in our pod manager.
	// this ensures our view of the cgroup tree does not mistakenly observe pods
	// that are added after the fact...
	var (
		cgroupPods map[types.UID]cm.CgroupName
		err        error
	)
	if kl.cgroupsPerQOS {
		pcm := kl.containerManager.NewPodContainerManager()
		cgroupPods, err = pcm.GetAllPodsFromCgroups()
		if err != nil {
			return fmt.Errorf("failed to get list of pods that still exist on cgroup mounts: %v", err)
		}
	}
    ...
}
```

列出所有pod包括mirror pod。

```go
allPods, mirrorPods := kl.podManager.GetPodsAndMirrorPods()
// Pod phase progresses monotonically. Once a pod has reached a final state,
// it should never leave regardless of the restart policy. The statuses
// of such pods should not be changed, and there is no need to sync them.
// TODO: the logic here does not handle two cases:
//   1. If the containers were removed immediately after they died, kubelet
//      may fail to generate correct statuses, let alone filtering correctly.
//   2. If kubelet restarted before writing the terminated status for a pod
//      to the apiserver, it could still restart the terminated pod (even
//      though the pod was not considered terminated by the apiserver).
// These two conditions could be alleviated by checkpointing kubelet.
activePods := kl.filterOutTerminatedPods(allPods)

desiredPods := make(map[types.UID]empty)
for _, pod := range activePods {
	desiredPods[pod.UID] = empty{}
}
```

pod worker停止不再存在的pod的任务，并从probe manager中清除pod。

```go
// Stop the workers for no-longer existing pods.
// TODO: is here the best place to forget pod workers?
kl.podWorkers.ForgetNonExistingPodWorkers(desiredPods)
kl.probeManager.CleanupPods(activePods)
```

将需要杀死的pod加入到`podKillingCh`的channel中，`podKiller`的任务会监听该channel并获取需要杀死的pod列表来执行杀死pod的操作。

```go
runningPods, err := kl.runtimeCache.GetPods()
if err != nil {
	glog.Errorf("Error listing containers: %#v", err)
	return err
}
for _, pod := range runningPods {
	if _, found := desiredPods[pod.ID]; !found {
		kl.podKillingCh <- &kubecontainer.PodPair{APIPod: nil, RunningPod: pod}
	}
}
```

当pod不再被绑定到该节点，移除`podStatus`，其中`removeOrphanedPodStatuses`最后调用的函数是`statusManager`的`RemoveOrphanedStatuses`方法。

```go
kl.removeOrphanedPodStatuses(allPods, mirrorPods)
```

移除所有的orphaned volume。

```go
// Remove any orphaned volumes.
// Note that we pass all pods (including terminated pods) to the function,
// so that we don't remove volumes associated with terminated but not yet
// deleted pods.
err = kl.cleanupOrphanedPodDirs(allPods, runningPods)
if err != nil {
	// We want all cleanup tasks to be run even if one of them failed. So
	// we just log an error here and continue other cleanup tasks.
	// This also applies to the other clean up tasks.
	glog.Errorf("Failed cleaning up orphaned pod directories: %v", err)
}
```

移除mirror pod。

```go
// Remove any orphaned mirror pods.
kl.podManager.DeleteOrphanedMirrorPods()
```

删除不再运行的pod的cgroup。

```go
// Remove any cgroups in the hierarchy for pods that are no longer running.
if kl.cgroupsPerQOS {
	kl.cleanupOrphanedPodCgroups(cgroupPods, activePods)
}
```

执行垃圾回收（GC）操作。

```go
kl.backOff.GC()
```

# 4. [dispatchWork](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1981)

`dispatchWork`通过pod worker启动一个异步的循环。

完整代码如下：

```go
// dispatchWork starts the asynchronous sync of the pod in a pod worker.
// If the pod is terminated, dispatchWork
func (kl *Kubelet) dispatchWork(pod *v1.Pod, syncType kubetypes.SyncPodType, mirrorPod *v1.Pod, start time.Time) {
	if kl.podIsTerminated(pod) {
		if pod.DeletionTimestamp != nil {
			// If the pod is in a terminated state, there is no pod worker to
			// handle the work item. Check if the DeletionTimestamp has been
			// set, and force a status update to trigger a pod deletion request
			// to the apiserver.
			kl.statusManager.TerminatePod(pod)
		}
		return
	}
	// Run the sync in an async worker.
	kl.podWorkers.UpdatePod(&UpdatePodOptions{
		Pod:        pod,
		MirrorPod:  mirrorPod,
		UpdateType: syncType,
		OnCompleteFunc: func(err error) {
			if err != nil {
				metrics.PodWorkerLatency.WithLabelValues(syncType.String()).Observe(metrics.SinceInMicroseconds(start))
			}
		},
	})
	// Note the number of containers for new pods.
	if syncType == kubetypes.SyncPodCreate {
		metrics.ContainersPerPodCount.Observe(float64(len(pod.Spec.Containers)))
	}
}
```

以下分段进行分析：

如果pod的状态是处于`Terminated`状态，则执行`statusManager`的`TerminatePod`操作。

```go
// dispatchWork starts the asynchronous sync of the pod in a pod worker.
// If the pod is terminated, dispatchWork
func (kl *Kubelet) dispatchWork(pod *v1.Pod, syncType kubetypes.SyncPodType, mirrorPod *v1.Pod, start time.Time) {
	if kl.podIsTerminated(pod) {
		if pod.DeletionTimestamp != nil {
			// If the pod is in a terminated state, there is no pod worker to
			// handle the work item. Check if the DeletionTimestamp has been
			// set, and force a status update to trigger a pod deletion request
			// to the apiserver.
			kl.statusManager.TerminatePod(pod)
		}
		return
	}
    ...
}    
```

执行pod worker的`UpdatePod`函数，该函数是pod worker的核心函数，来执行pod相关操作。具体逻辑待下文分析。

```go
// Run the sync in an async worker.
kl.podWorkers.UpdatePod(&UpdatePodOptions{
	Pod:        pod,
	MirrorPod:  mirrorPod,
	UpdateType: syncType,
	OnCompleteFunc: func(err error) {
		if err != nil {
			metrics.PodWorkerLatency.WithLabelValues(syncType.String()).Observe(metrics.SinceInMicroseconds(start))
		}
	},
})
```

当创建类型是`SyncPodCreate`（即创建pod的时候），统计新pod中容器的数目。

```go
// Note the number of containers for new pods.
if syncType == kubetypes.SyncPodCreate {
	metrics.ContainersPerPodCount.Observe(float64(len(pod.Spec.Containers)))
}
```

# 5. [PodWorkers.UpdatePod](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/pod_workers.go#L195)

PodWorkers是一个接口类型：

```go
// PodWorkers is an abstract interface for testability.
type PodWorkers interface {
	UpdatePod(options *UpdatePodOptions)
	ForgetNonExistingPodWorkers(desiredPods map[types.UID]empty)
	ForgetWorker(uid types.UID)
}
```

其中`UpdatePod`是一个核心方法，通过`podUpdates`的channel来传递需要处理的pod信息，对于新创建的pod每个pod都会由一个goroutine来执行`managePodLoop`。

> 此部分代码位于pkg/kubelet/pod_workers.go

```go
// Apply the new setting to the specified pod.
// If the options provide an OnCompleteFunc, the function is invoked if the update is accepted.
// Update requests are ignored if a kill pod request is pending.
func (p *podWorkers) UpdatePod(options *UpdatePodOptions) {
	pod := options.Pod
	uid := pod.UID
	var podUpdates chan UpdatePodOptions
	var exists bool

	p.podLock.Lock()
	defer p.podLock.Unlock()
	if podUpdates, exists = p.podUpdates[uid]; !exists {
		// We need to have a buffer here, because checkForUpdates() method that
		// puts an update into channel is called from the same goroutine where
		// the channel is consumed. However, it is guaranteed that in such case
		// the channel is empty, so buffer of size 1 is enough.
		podUpdates = make(chan UpdatePodOptions, 1)
		p.podUpdates[uid] = podUpdates

		// Creating a new pod worker either means this is a new pod, or that the
		// kubelet just restarted. In either case the kubelet is willing to believe
		// the status of the pod for the first pod worker sync. See corresponding
		// comment in syncPod.
		go func() {
			defer runtime.HandleCrash()
			p.managePodLoop(podUpdates)
		}()
	}
	if !p.isWorking[pod.UID] {
		p.isWorking[pod.UID] = true
		podUpdates <- *options
	} else {
		// if a request to kill a pod is pending, we do not let anything overwrite that request.
		update, found := p.lastUndeliveredWorkUpdate[pod.UID]
		if !found || update.UpdateType != kubetypes.SyncPodKill {
			p.lastUndeliveredWorkUpdate[pod.UID] = *options
		}
	}
}
```

# 6. [managePodLoop](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/pod_workers.go#L153)

`managePodLoop`通过读取`podUpdates`channel的信息，执行`syncPodFn`函数，而`syncPodFn`函数在`newPodWorkers`的时候赋值了，即`kubelet.syncPod`。`kubelet.syncPod`具体代码逻辑待后续文章单独分析。

```go
// newPodWorkers传入syncPod函数
klet.podWorkers = newPodWorkers(klet.syncPod, kubeDeps.Recorder, klet.workQueue, klet.resyncInterval, backOffPeriod, klet.podCache)
```

`newPodWorkers`函数参考：

```go
func newPodWorkers(syncPodFn syncPodFnType, recorder record.EventRecorder, workQueue queue.WorkQueue,
	resyncInterval, backOffPeriod time.Duration, podCache kubecontainer.Cache) *podWorkers {
	return &podWorkers{
		podUpdates:                map[types.UID]chan UpdatePodOptions{},
		isWorking:                 map[types.UID]bool{},
		lastUndeliveredWorkUpdate: map[types.UID]UpdatePodOptions{},
		syncPodFn:                 syncPodFn,  // 构造传入klet.syncPod函数
		recorder:                  recorder,
		workQueue:                 workQueue,
		resyncInterval:            resyncInterval,
		backOffPeriod:             backOffPeriod,
		podCache:                  podCache,
	}
}
```

`managePodLoop`函数参考：

> 此部分代码位于pkg/kubelet/pod_workers.go

```go
func (p *podWorkers) managePodLoop(podUpdates <-chan UpdatePodOptions) {
	var lastSyncTime time.Time
	for update := range podUpdates {
		err := func() error {
			podUID := update.Pod.UID
			// This is a blocking call that would return only if the cache
			// has an entry for the pod that is newer than minRuntimeCache
			// Time. This ensures the worker doesn't start syncing until
			// after the cache is at least newer than the finished time of
			// the previous sync.
			status, err := p.podCache.GetNewerThan(podUID, lastSyncTime)
			if err != nil {
				// This is the legacy event thrown by manage pod loop
				// all other events are now dispatched from syncPodFn
				p.recorder.Eventf(update.Pod, v1.EventTypeWarning, events.FailedSync, "error determining status: %v", err)
				return err
			}
			err = p.syncPodFn(syncPodOptions{
				mirrorPod:      update.MirrorPod,
				pod:            update.Pod,
				podStatus:      status,
				killPodOptions: update.KillPodOptions,
				updateType:     update.UpdateType,
			})
			lastSyncTime = time.Now()
			return err
		}()
		// notify the call-back function if the operation succeeded or not
		if update.OnCompleteFunc != nil {
			update.OnCompleteFunc(err)
		}
		if err != nil {
			// IMPORTANT: we do not log errors here, the syncPodFn is responsible for logging errors
			glog.Errorf("Error syncing pod %s (%q), skipping: %v", update.Pod.UID, format.Pod(update.Pod), err)
		}
		p.wrapUp(update.Pod.UID, err)
	}
}
```

# 7. 总结

`syncLoopIteration`基本流程如下：

1. 通过几种`channel`来对不同类型的事件进行监听并处理。其中channel包括：`configCh`、`plegCh`、`syncCh`、`houseKeepingCh`、`livenessManager.Updates()`。
2. 不同的SyncHandler执行不同的增删改查操作。
3. 其中`HandlePodAdditions`、`HandlePodUpdates`、`HandlePodReconcile`、`HandlePodSyncs`都调用到了`dispatchWork`来执行pod的相关操作。`HandlePodCleanups`的pod清理任务，通过channel的方式加需要清理的pod给`podKiller`来清理。
4. `dispatchWork`调用`podWorkers.UpdatePod`执行异步操作。
5. `podWorkers.UpdatePod`中调用`managePodLoop`来执行pod相关操作循环。



**channel类型及作用：**

- `configCh`：将配置更改的pod分派给事件类型的相应处理程序回调。
- `plegCh`：更新runtime缓存，同步pod。
- `syncCh`：同步所有等待同步的pod。
- `houseKeepingCh`：触发清理pod。
- `livenessManager.Updates()`：对失败的pod或者liveness检查失败的pod进行sync操作。





参考：

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/pod_workers.go>

