> 以下代码分析基于 `kubernetes v1.12.0` 版本。
>
> 本文主要分析<https://github.com/kubernetes/kubernetes/tree/v1.12.0/pkg/kubelet> 部分的代码。

# 1. [syncLoopIteration](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1870)

`syncLoopIteration`主要通过几种`channel`来对不同类型的事件进行监听并处理。其中包括：`configCh`、`plegCh`、`syncCh`、`houseKeepingCh`、`livenessManager.Updates()`。

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

		if u.Op != kubetypes.RESTORE {
			// If the update type is RESTORE, it means that the update is from
			// the pod checkpoints and may be incomplete. Do not mark the
			// source as ready.

			// Mark the source ready after receiving at least one update from the
			// source. Once all the sources are marked ready, various cleanup
			// routines will start reclaiming resources. It is important that this
			// takes place only after kubelet calls the update handler to process
			// the update to ensure the internal pod cache is up-to-date.
			kl.sourcesReady.AddSource(u.Source)
		}
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
	case <-syncCh:
		// Sync pods waiting for sync
		podsToSync := kl.getPodsToSync()
		if len(podsToSync) == 0 {
			break
		}
		glog.V(4).Infof("SyncLoop (SYNC): %d pods; %s", len(podsToSync), format.Pods(podsToSync))
		handler.HandlePodSyncs(podsToSync)
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
	}
	return true
}
```

# 2. [SyncHandler](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L177)

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

## 2.1. [HandlePodAdditions](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2021)

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

## 2.2. [HandlePodUpdates](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2063)

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

## 2.3. [HandlePodRemoves](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2084)

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

## 2.4. [HandlePodReconcile](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2103)

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

## 2.5. [HandlePodSyncs](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L2127)

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

## 2.6. [HandlePodCleanups](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet_pods.go#L979)

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

## 2.7. 总结

- syncHandler的各种handler是在[syncLoopIteration](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1870)中调用。
- 其中`HandlePodAdditions`、`HandlePodUpdates`、`HandlePodReconcile`、`HandlePodSyncs`都调用到了`dispatchWork`来执行pod的相关操作。
- `HandlePodCleanups`的pod清理任务，通过channel的方式加需要清理的pod给`podKiller`来清理。
- syncHandler中使用到`pod manager`、`probe manager`、`pod worker`、`podKiller`来执行相关操作。
- syncHandler中的各种handler是根据`podUpdate`中不同的操作类型（增删改查等）来执行具体的handler。具体可参考[syncloopiteration](https://www.huweihuang.com/kubernetes-notes/code-analysis/kubelet/kubelet-run.html#3-syncloopiteration)。

# 3. [dispatchWork](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1981)

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

# 4. [PodWorkers.UpdatePod](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/pod_workers.go#L195)

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

# 5. [managePodLoop](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/pod_workers.go#L153)

`managePodLoop`通过读取`podUpdates`channel的信息，执行`syncPodFn`函数，而`syncPodFn`函数在`newPodWorkers`的时候赋值了，即`kubelet.syncPod`。

```go
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
		syncPodFn:                 syncPodFn,
		recorder:                  recorder,
		workQueue:                 workQueue,
		resyncInterval:            resyncInterval,
		backOffPeriod:             backOffPeriod,
		podCache:                  podCache,
	}
}
```

`managePodLoop`函数参考：

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

# 6. [syncPod](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1465)

`syncPod`可以理解为是一个单个pod进行同步任务的事务脚本。其中入参是`syncPodOptions`，`syncPodOptions`记录了需要同步的pod的相关信息。具体定义如下：

```go
// syncPodOptions provides the arguments to a SyncPod operation.
type syncPodOptions struct {
	// the mirror pod for the pod to sync, if it is a static pod
	mirrorPod *v1.Pod
	// pod to sync
	pod *v1.Pod
	// the type of update (create, update, sync)
	updateType kubetypes.SyncPodType
	// the current status
	podStatus *kubecontainer.PodStatus
	// if update type is kill, use the specified options to kill the pod.
	killPodOptions *KillPodOptions
}
```

`syncPod`主要执行以下的工作流：

- 如果是正在创建的pod，则记录pod worker的启动`latency`。
- 调用`generateAPIPodStatus`为pod提供`v1.PodStatus`信息。
- 如果pod是第一次运行，记录pod的启动`latency`。
- 更新`status manager`中的pod状态。
- 如果pod不应该被运行则杀死pod。
- 如果pod是一个`static pod`，并且没有对应的`mirror pod`，则创建一个`mirror pod`。
- 如果没有pod的数据目录则给pod创建对应的数据目录。
- 等待volume被attach或mount。
- 获取pod的secret数据。
- 调用`container runtime`的`SyncPod`函数，执行相关pod操作。
- 更新pod的`ingress`和`egress`的`traffic limit`。

当以上任务流中有任何的error，则return error。在下一次执行`syncPod`的任务流会被再次执行。对于错误信息会被记录到event中，方便debug。

以下对`syncPod`的执行过程进行分析。

## 6.1. SyncPodKill

首先，获取`syncPodOptions`的pod信息。

```go
func (kl *Kubelet) syncPod(o syncPodOptions) error {
	// pull out the required options
	pod := o.pod
	mirrorPod := o.mirrorPod
	podStatus := o.podStatus
	updateType := o.updateType
    ...
}    
```

如果pod是需要被杀死的，则执行`killPod`，会在指定的宽限期内杀死pod。

```go
// if we want to kill a pod, do it now!
if updateType == kubetypes.SyncPodKill {
	killPodOptions := o.killPodOptions
	if killPodOptions == nil || killPodOptions.PodStatusFunc == nil {
		return fmt.Errorf("kill pod options are required if update type is kill")
	}
	apiPodStatus := killPodOptions.PodStatusFunc(pod, podStatus)
	kl.statusManager.SetPodStatus(pod, apiPodStatus)
	// we kill the pod with the specified grace period since this is a termination
	if err := kl.killPod(pod, nil, podStatus, killPodOptions.PodTerminationGracePeriodSecondsOverride); err != nil {
		kl.recorder.Eventf(pod, v1.EventTypeWarning, events.FailedToKillPod, "error killing pod: %v", err)
		// there was an error killing the pod, so we return that error directly
		utilruntime.HandleError(err)
		return err
	}
	return nil
}
```

## 6.2. SyncPodCreate

如果pod是需要被创建的，则记录pod的启动`latency`，`latency`与pod在apiserver中第一次被记录相关。

```go
// Latency measurements for the main workflow are relative to the
// first time the pod was seen by the API server.
var firstSeenTime time.Time
if firstSeenTimeStr, ok := pod.Annotations[kubetypes.ConfigFirstSeenAnnotationKey]; ok {
	firstSeenTime = kubetypes.ConvertToTimestamp(firstSeenTimeStr).Get()
}

// Record pod worker start latency if being created
// TODO: make pod workers record their own latencies
if updateType == kubetypes.SyncPodCreate {
	if !firstSeenTime.IsZero() {
		// This is the first time we are syncing the pod. Record the latency
		// since kubelet first saw the pod if firstSeenTime is set.
		metrics.PodWorkerStartLatency.Observe(metrics.SinceInMicroseconds(firstSeenTime))
	} else {
		glog.V(3).Infof("First seen time not recorded for pod %q", pod.UID)
	}
}
```

通过pod和pod status生成最终的api pod status并设置pod的IP。

```go
// Generate final API pod status with pod and status manager status
apiPodStatus := kl.generateAPIPodStatus(pod, podStatus)
// The pod IP may be changed in generateAPIPodStatus if the pod is using host network. (See #24576)
// TODO(random-liu): After writing pod spec into container labels, check whether pod is using host network, and
// set pod IP to hostIP directly in runtime.GetPodStatus
podStatus.IP = apiPodStatus.PodIP
```

记录pod到running状态的时间。

```go
// Record the time it takes for the pod to become running.
existingStatus, ok := kl.statusManager.GetPodStatus(pod.UID)
if !ok || existingStatus.Phase == v1.PodPending && apiPodStatus.Phase == v1.PodRunning &&
	!firstSeenTime.IsZero() {
	metrics.PodStartLatency.Observe(metrics.SinceInMicroseconds(firstSeenTime))
}
```

如果pod是不可运行的，则更新pod和container的状态和相应的原因。

```go
runnable := kl.canRunPod(pod)
if !runnable.Admit {
	// Pod is not runnable; update the Pod and Container statuses to why.
	apiPodStatus.Reason = runnable.Reason
	apiPodStatus.Message = runnable.Message
	// Waiting containers are not creating.
	const waitingReason = "Blocked"
	for _, cs := range apiPodStatus.InitContainerStatuses {
		if cs.State.Waiting != nil {
			cs.State.Waiting.Reason = waitingReason
		}
	}
	for _, cs := range apiPodStatus.ContainerStatuses {
		if cs.State.Waiting != nil {
			cs.State.Waiting.Reason = waitingReason
		}
	}
}
```

并更新status manager中的状态信息，杀死不可运行的pod。

```go
// Update status in the status manager
kl.statusManager.SetPodStatus(pod, apiPodStatus)

// Kill pod if it should not be running
if !runnable.Admit || pod.DeletionTimestamp != nil || apiPodStatus.Phase == v1.PodFailed {
	var syncErr error
	if err := kl.killPod(pod, nil, podStatus, nil); err != nil {
		kl.recorder.Eventf(pod, v1.EventTypeWarning, events.FailedToKillPod, "error killing pod: %v", err)
		syncErr = fmt.Errorf("error killing pod: %v", err)
		utilruntime.HandleError(syncErr)
	} else {
		if !runnable.Admit {
			// There was no error killing the pod, but the pod cannot be run.
			// Return an error to signal that the sync loop should back off.
			syncErr = fmt.Errorf("pod cannot be run: %s", runnable.Message)
		}
	}
	return syncErr
}
```

如果网络插件还没到`Ready`状态，则只有在使用`host`网络模式的情况下才启动pod。

```go
// If the network plugin is not ready, only start the pod if it uses the host network
if rs := kl.runtimeState.networkErrors(); len(rs) != 0 && !kubecontainer.IsHostNetworkPod(pod) {
	kl.recorder.Eventf(pod, v1.EventTypeWarning, events.NetworkNotReady, "%s: %v", NetworkNotReadyErrorMsg, rs)
	return fmt.Errorf("%s: %v", NetworkNotReadyErrorMsg, rs)
}
```

## 6.3. Cgroups

给pod创建`Cgroups`，如果`cgroups-per-qos`参数开启，则申请相应的资源。对于`terminated`的pod不需要创建或更新pod的`Cgroups`。

当重新启动`kubelet`并且启用`cgroups-per-qos`时，应该间歇性地终止所有pod的运行容器并在`qos cgroup hierarchy`下重新启动。

如果pod的cgroup已经存在或者pod第一次运行，不杀死pod中容器。

```go
// Create Cgroups for the pod and apply resource parameters
// to them if cgroups-per-qos flag is enabled.
pcm := kl.containerManager.NewPodContainerManager()
// If pod has already been terminated then we need not create
// or update the pod's cgroup
if !kl.podIsTerminated(pod) {
	// When the kubelet is restarted with the cgroups-per-qos
	// flag enabled, all the pod's running containers
	// should be killed intermittently and brought back up
	// under the qos cgroup hierarchy.
	// Check if this is the pod's first sync
	firstSync := true
	for _, containerStatus := range apiPodStatus.ContainerStatuses {
		if containerStatus.State.Running != nil {
			firstSync = false
			break
		}
	}
	// Don't kill containers in pod if pod's cgroups already
	// exists or the pod is running for the first time
	podKilled := false
	if !pcm.Exists(pod) && !firstSync {
		if err := kl.killPod(pod, nil, podStatus, nil); err == nil {
			podKilled = true
		}
	}
    ...
```

如果pod被杀死并且重启策略是`Never`，则不创建或更新对应的`Cgroups`，否则创建和更新pod的`Cgroups`。

```go
// Create and Update pod's Cgroups
// Don't create cgroups for run once pod if it was killed above
// The current policy is not to restart the run once pods when
// the kubelet is restarted with the new flag as run once pods are
// expected to run only once and if the kubelet is restarted then
// they are not expected to run again.
// We don't create and apply updates to cgroup if its a run once pod and was killed above
if !(podKilled && pod.Spec.RestartPolicy == v1.RestartPolicyNever) {
	if !pcm.Exists(pod) {
		if err := kl.containerManager.UpdateQOSCgroups(); err != nil {
			glog.V(2).Infof("Failed to update QoS cgroups while syncing pod: %v", err)
		}
		if err := pcm.EnsureExists(pod); err != nil {
			kl.recorder.Eventf(pod, v1.EventTypeWarning, events.FailedToCreatePodContainer, "unable to ensure pod container exists: %v", err)
			return fmt.Errorf("failed to ensure that the pod: %v cgroups exist and are correctly applied: %v", pod.UID, err)
		}
	}
}
```

其中创建`Cgroups`是通过`containerManager`的`UpdateQOSCgroups`来执行。

```go
if err := kl.containerManager.UpdateQOSCgroups(); err != nil {
	glog.V(2).Infof("Failed to update QoS cgroups while syncing pod: %v", err)
}
```

## 6.4. Mirror Pod

如果pod是一个`static pod`，没有对应的`mirror pod`，则创建一个`mirror pod`；如果存在`mirror pod`则删除再重建一个`mirror pod`。

```go
// Create Mirror Pod for Static Pod if it doesn't already exist
if kubepod.IsStaticPod(pod) {
	podFullName := kubecontainer.GetPodFullName(pod)
	deleted := false
	if mirrorPod != nil {
		if mirrorPod.DeletionTimestamp != nil || !kl.podManager.IsMirrorPodOf(mirrorPod, pod) {
			// The mirror pod is semantically different from the static pod. Remove
			// it. The mirror pod will get recreated later.
			glog.Warningf("Deleting mirror pod %q because it is outdated", format.Pod(mirrorPod))
			if err := kl.podManager.DeleteMirrorPod(podFullName); err != nil {
				glog.Errorf("Failed deleting mirror pod %q: %v", format.Pod(mirrorPod), err)
			} else {
				deleted = true
			}
		}
	}
	if mirrorPod == nil || deleted {
		node, err := kl.GetNode()
		if err != nil || node.DeletionTimestamp != nil {
			glog.V(4).Infof("No need to create a mirror pod, since node %q has been removed from the cluster", kl.nodeName)
		} else {
			glog.V(4).Infof("Creating a mirror pod for static pod %q", format.Pod(pod))
			if err := kl.podManager.CreateMirrorPod(pod); err != nil {
				glog.Errorf("Failed creating a mirror pod for %q: %v", format.Pod(pod), err)
			}
		}
	}
}
```

## 6.5. makePodDataDirs

给pod创建数据目录。

```go
// Make data directories for the pod
if err := kl.makePodDataDirs(pod); err != nil {
	kl.recorder.Eventf(pod, v1.EventTypeWarning, events.FailedToMakePodDataDirectories, "error making pod data directories: %v", err)
	glog.Errorf("Unable to make pod data directories for pod %q: %v", format.Pod(pod), err)
	return err
}
```

其中数据目录包括

- `PodDir`：{kubelet.rootDirectory}/pods/podUID
- `PodVolumesDir`：{PodDir}/volumes
- `PodPluginsDir`：{PodDir}/plugins

```go
// makePodDataDirs creates the dirs for the pod datas.
func (kl *Kubelet) makePodDataDirs(pod *v1.Pod) error {
	uid := pod.UID
	if err := os.MkdirAll(kl.getPodDir(uid), 0750); err != nil && !os.IsExist(err) {
		return err
	}
	if err := os.MkdirAll(kl.getPodVolumesDir(uid), 0750); err != nil && !os.IsExist(err) {
		return err
	}
	if err := os.MkdirAll(kl.getPodPluginsDir(uid), 0750); err != nil && !os.IsExist(err) {
		return err
	}
	return nil
}
```

## 6.6. mount volumes

对非`terminated`状态的pod挂载`volume`。

```go
// Volume manager will not mount volumes for terminated pods
if !kl.podIsTerminated(pod) {
	// Wait for volumes to attach/mount
	if err := kl.volumeManager.WaitForAttachAndMount(pod); err != nil {
		kl.recorder.Eventf(pod, v1.EventTypeWarning, events.FailedMountVolume, "Unable to mount volumes for pod %q: %v", format.Pod(pod), err)
		glog.Errorf("Unable to mount volumes for pod %q: %v; skipping pod", format.Pod(pod), err)
		return err
	}
}
```

## 6.7. PullSecretsForPod

获取pod的secret数据。

```go
// Fetch the pull secrets for the pod
pullSecrets := kl.getPullSecretsForPod(pod)
```

`getPullSecretsForPod`具体实现函数如下：

```go
// getPullSecretsForPod inspects the Pod and retrieves the referenced pull
// secrets.
func (kl *Kubelet) getPullSecretsForPod(pod *v1.Pod) []v1.Secret {
	pullSecrets := []v1.Secret{}

	for _, secretRef := range pod.Spec.ImagePullSecrets {
		secret, err := kl.secretManager.GetSecret(pod.Namespace, secretRef.Name)
		if err != nil {
			glog.Warningf("Unable to retrieve pull secret %s/%s for %s/%s due to %v.  The image pull may not succeed.", pod.Namespace, secretRef.Name, pod.Namespace, pod.Name, err)
			continue
		}

		pullSecrets = append(pullSecrets, *secret)
	}

	return pullSecrets
}
```

## 6.8. containerRuntime.SyncPod

调用`container runtime`的`SyncPod`函数，执行相关pod操作，由此`kubelet.syncPod`的操作逻辑转入`containerRuntime.SyncPod`函数中。

```go
// Call the container runtime's SyncPod callback
result := kl.containerRuntime.SyncPod(pod, apiPodStatus, podStatus, pullSecrets, kl.backOff)
kl.reasonCache.Update(pod.UID, result)
if err := result.Error(); err != nil {
	// Do not return error if the only failures were pods in backoff
	for _, r := range result.SyncResults {
		if r.Error != kubecontainer.ErrCrashLoopBackOff && r.Error != images.ErrImagePullBackOff {
			// Do not record an event here, as we keep all event logging for sync pod failures
			// local to container runtime so we get better errors
			return err
		}
	}

	return nil
}
```

# 7. [Runtime.SyncPod](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kuberuntime/kuberuntime_manager.go#L578)

`SyncPod`主要执行sync操作使得运行的pod达到期望状态的pod。主要执行以下操作：

- 计算`sandbox`和`container`的变化。
- 必要的时候杀死pod。
- 杀死所有不需要运行的`container`。
- 必要时创建`sandbox`。
- 创建`init container`。
- 创建正常的`container`。

## 7.1. computePodActions

计算`sandbox`和`container`的变化。

```go
// Step 1: Compute sandbox and container changes.
podContainerChanges := m.computePodActions(pod, podStatus)
glog.V(3).Infof("computePodActions got %+v for pod %q", podContainerChanges, format.Pod(pod))
if podContainerChanges.CreateSandbox {
	ref, err := ref.GetReference(legacyscheme.Scheme, pod)
	if err != nil {
		glog.Errorf("Couldn't make a ref to pod %q: '%v'", format.Pod(pod), err)
	}
	if podContainerChanges.SandboxID != "" {
		m.recorder.Eventf(ref, v1.EventTypeNormal, events.SandboxChanged, "Pod sandbox changed, it will be killed and re-created.")
	} else {
		glog.V(4).Infof("SyncPod received new pod %q, will create a sandbox for it", format.Pod(pod))
	}
}
```

## 7.2. killPodWithSyncResult

必要的时候杀死pod。

```go
// Step 2: Kill the pod if the sandbox has changed.
if podContainerChanges.KillPod {
	if !podContainerChanges.CreateSandbox {
		glog.V(4).Infof("Stopping PodSandbox for %q because all other containers are dead.", format.Pod(pod))
	} else {
		glog.V(4).Infof("Stopping PodSandbox for %q, will start new one", format.Pod(pod))
	}

	killResult := m.killPodWithSyncResult(pod, kubecontainer.ConvertPodStatusToRunningPod(m.runtimeName, podStatus), nil)
	result.AddPodSyncResult(killResult)
	if killResult.Error() != nil {
		glog.Errorf("killPodWithSyncResult failed: %v", killResult.Error())
		return
	}

	if podContainerChanges.CreateSandbox {
		m.purgeInitContainers(pod, podStatus)
	}
}
```

## 7.3. killContainer

杀死所有不需要运行的`container`。

```go
// Step 3: kill any running containers in this pod which are not to keep.
for containerID, containerInfo := range podContainerChanges.ContainersToKill {
	glog.V(3).Infof("Killing unwanted container %q(id=%q) for pod %q", containerInfo.name, containerID, format.Pod(pod))
	killContainerResult := kubecontainer.NewSyncResult(kubecontainer.KillContainer, containerInfo.name)
	result.AddSyncResult(killContainerResult)
	if err := m.killContainer(pod, containerID, containerInfo.name, containerInfo.message, nil); err != nil {
		killContainerResult.Fail(kubecontainer.ErrKillContainer, err.Error())
		glog.Errorf("killContainer %q(id=%q) for pod %q failed: %v", containerInfo.name, containerID, format.Pod(pod), err)
		return
	}
}
```

## 7.4. createPodSandbox

必要时创建`sandbox`。

```go
// Step 4: Create a sandbox for the pod if necessary.
...
glog.V(4).Infof("Creating sandbox for pod %q", format.Pod(pod))
createSandboxResult := kubecontainer.NewSyncResult(kubecontainer.CreatePodSandbox, format.Pod(pod))
result.AddSyncResult(createSandboxResult)
podSandboxID, msg, err = m.createPodSandbox(pod, podContainerChanges.Attempt)
if err != nil {
	createSandboxResult.Fail(kubecontainer.ErrCreatePodSandbox, msg)
	glog.Errorf("createPodSandbox for pod %q failed: %v", format.Pod(pod), err)
	ref, referr := ref.GetReference(legacyscheme.Scheme, pod)
	if referr != nil {
		glog.Errorf("Couldn't make a ref to pod %q: '%v'", format.Pod(pod), referr)
	}
	m.recorder.Eventf(ref, v1.EventTypeWarning, events.FailedCreatePodSandBox, "Failed create pod sandbox: %v", err)
	return
}
glog.V(4).Infof("Created PodSandbox %q for pod %q", podSandboxID, format.Pod(pod))
```

## 7.5. start init container

创建`init container`。

```go
// Step 5: start the init container.
if container := podContainerChanges.NextInitContainerToStart; container != nil {
	// Start the next init container.
	startContainerResult := kubecontainer.NewSyncResult(kubecontainer.StartContainer, container.Name)
	result.AddSyncResult(startContainerResult)
	isInBackOff, msg, err := m.doBackOff(pod, container, podStatus, backOff)
	if isInBackOff {
		startContainerResult.Fail(err, msg)
		glog.V(4).Infof("Backing Off restarting init container %+v in pod %v", container, format.Pod(pod))
		return
	}

	glog.V(4).Infof("Creating init container %+v in pod %v", container, format.Pod(pod))
	if msg, err := m.startContainer(podSandboxID, podSandboxConfig, container, pod, podStatus, pullSecrets, podIP, kubecontainer.ContainerTypeInit); err != nil {
		startContainerResult.Fail(err, msg)
		utilruntime.HandleError(fmt.Errorf("init container start failed: %v: %s", err, msg))
		return
	}

	// Successfully started the container; clear the entry in the failure
	glog.V(4).Infof("Completed init container %q for pod %q", container.Name, format.Pod(pod))
}
```

## 7.6. start containers

创建正常的`container`。

```go
// Step 6: start containers in podContainerChanges.ContainersToStart.
for _, idx := range podContainerChanges.ContainersToStart {
	container := &pod.Spec.Containers[idx]
	startContainerResult := kubecontainer.NewSyncResult(kubecontainer.StartContainer, container.Name)
	result.AddSyncResult(startContainerResult)

	isInBackOff, msg, err := m.doBackOff(pod, container, podStatus, backOff)
	if isInBackOff {
		startContainerResult.Fail(err, msg)
		glog.V(4).Infof("Backing Off restarting container %+v in pod %v", container, format.Pod(pod))
		continue
	}

	glog.V(4).Infof("Creating container %+v in pod %v", container, format.Pod(pod))
	if msg, err := m.startContainer(podSandboxID, podSandboxConfig, container, pod, podStatus, pullSecrets, podIP, kubecontainer.ContainerTypeRegular); err != nil {
		startContainerResult.Fail(err, msg)
		// known errors that are logged in other places are logged at higher levels here to avoid
		// repetitive log spam
		switch {
		case err == images.ErrImagePullBackOff:
			glog.V(3).Infof("container start failed: %v: %s", err, msg)
		default:
			utilruntime.HandleError(fmt.Errorf("container start failed: %v: %s", err, msg))
		}
		continue
	}
}
```

# 8. [startContainer](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kuberuntime/kuberuntime_container.go#L89)

`startContainer`用来启动一个容器，如果失败则返回报错信息。主要包含以下操作：

1. 拉取容器镜像
2. 创建container
3. 启动container
4. 执行post start hook

```go
// startContainer starts a container and returns a message indicates why it is failed on error.
// It starts the container through the following steps:
// * pull the image
// * create the container
// * start the container
// * run the post start lifecycle hooks (if applicable)
func (m *kubeGenericRuntimeManager) startContainer(podSandboxID string, podSandboxConfig *runtimeapi.PodSandboxConfig, container *v1.Container, pod *v1.Pod, podStatus *kubecontainer.PodStatus, pullSecrets []v1.Secret, podIP string, containerType kubecontainer.ContainerType) (string, error) {
...
}
```

## 8.1. pull image

通过`EnsureImageExists`方法拉取拉取指定pod容器的镜像，并返回镜像信息和错误。

```go
// Step 1: pull the image.
imageRef, msg, err := m.imagePuller.EnsureImageExists(pod, container, pullSecrets)
if err != nil {
	m.recordContainerEvent(pod, container, "", v1.EventTypeWarning, events.FailedToCreateContainer, "Error: %v", grpc.ErrorDesc(err))
	return msg, err
}
```

## 8.2. CreateContainer

首先生成container的`*v1.ObjectReference`对象，该对象包括container的相关信息。

```go
// Step 2: create the container.
ref, err := kubecontainer.GenerateContainerRef(pod, container)
if err != nil {
	glog.Errorf("Can't make a ref to pod %q, container %v: %v", format.Pod(pod), container.Name, err)
}
glog.V(4).Infof("Generating ref for container %s: %#v", container.Name, ref)
```
统计container的重启次数，新的容器默认重启次数为0。
```go
// For a new container, the RestartCount should be 0
restartCount := 0
containerStatus := podStatus.FindContainerStatusByName(container.Name)
if containerStatus != nil {
	restartCount = containerStatus.RestartCount + 1
}
```
生成container的配置。
```go
containerConfig, cleanupAction, err := m.generateContainerConfig(container, pod, restartCount, podIP, imageRef, containerType)
if cleanupAction != nil {
	defer cleanupAction()
}
if err != nil {
	m.recordContainerEvent(pod, container, "", v1.EventTypeWarning, events.FailedToCreateContainer, "Error: %v", grpc.ErrorDesc(err))
	return grpc.ErrorDesc(err), ErrCreateContainerConfig
}
```
调用`runtimeService`，执行`CreateContainer`的操作。
```go
containerID, err := m.runtimeService.CreateContainer(podSandboxID, containerConfig, podSandboxConfig)
if err != nil {
	m.recordContainerEvent(pod, container, containerID, v1.EventTypeWarning, events.FailedToCreateContainer, "Error: %v", grpc.ErrorDesc(err))
	return grpc.ErrorDesc(err), ErrCreateContainer
}
err = m.internalLifecycle.PreStartContainer(pod, container, containerID)
if err != nil {
	m.recordContainerEvent(pod, container, containerID, v1.EventTypeWarning, events.FailedToStartContainer, "Internal PreStartContainer hook failed: %v", grpc.ErrorDesc(err))
	return grpc.ErrorDesc(err), ErrPreStartHook
}
m.recordContainerEvent(pod, container, containerID, v1.EventTypeNormal, events.CreatedContainer, "Created container")

if ref != nil {
	m.containerRefManager.SetRef(kubecontainer.ContainerID{
		Type: m.runtimeName,
		ID:   containerID,
	}, ref)
}
```

## 8.3. StartContainer

执行`runtimeService`的`StartContainer`方法，来启动容器。

```go
// Step 3: start the container.
err = m.runtimeService.StartContainer(containerID)
if err != nil {
	m.recordContainerEvent(pod, container, containerID, v1.EventTypeWarning, events.FailedToStartContainer, "Error: %v", grpc.ErrorDesc(err))
	return grpc.ErrorDesc(err), kubecontainer.ErrRunContainer
}
m.recordContainerEvent(pod, container, containerID, v1.EventTypeNormal, events.StartedContainer, "Started container")

// Symlink container logs to the legacy container log location for cluster logging
// support.
// TODO(random-liu): Remove this after cluster logging supports CRI container log path.
containerMeta := containerConfig.GetMetadata()
sandboxMeta := podSandboxConfig.GetMetadata()
legacySymlink := legacyLogSymlink(containerID, containerMeta.Name, sandboxMeta.Name,
	sandboxMeta.Namespace)
containerLog := filepath.Join(podSandboxConfig.LogDirectory, containerConfig.LogPath)
// only create legacy symlink if containerLog path exists (or the error is not IsNotExist).
// Because if containerLog path does not exist, only dandling legacySymlink is created.
// This dangling legacySymlink is later removed by container gc, so it does not make sense
// to create it in the first place. it happens when journald logging driver is used with docker.
if _, err := m.osInterface.Stat(containerLog); !os.IsNotExist(err) {
	if err := m.osInterface.Symlink(containerLog, legacySymlink); err != nil {
		glog.Errorf("Failed to create legacy symbolic link %q to container %q log %q: %v",
			legacySymlink, containerID, containerLog, err)
	}
}
```

## 8.4. execute post start hook

如果有指定`Lifecycle.PostStart`，则执行`PostStart`操作，`PostStart`如果执行失败，则容器会根据重启的规则进行重启。

```go
// Step 4: execute the post start hook.
if container.Lifecycle != nil && container.Lifecycle.PostStart != nil {
	kubeContainerID := kubecontainer.ContainerID{
		Type: m.runtimeName,
		ID:   containerID,
	}
	msg, handlerErr := m.runner.Run(kubeContainerID, pod, container, container.Lifecycle.PostStart)
	if handlerErr != nil {
		m.recordContainerEvent(pod, container, kubeContainerID.ID, v1.EventTypeWarning, events.FailedPostStartHook, msg)
		if err := m.killContainer(pod, kubeContainerID, container.Name, "FailedPostStartHook", nil); err != nil {
			glog.Errorf("Failed to kill container %q(id=%q) in pod %q: %v, %v",
				container.Name, kubeContainerID.String(), format.Pod(pod), ErrPostStartHook, err)
		}
		return msg, fmt.Errorf("%s: %v", ErrPostStartHook, handlerErr)
	}
}
```

# 9. 总结

kubelet的工作是管理pod在Node上的生命周期（包括增删改查），kubelet通过各种类型的manager异步工作各自执行各自的任务，其中使用到了多种的channel来控制状态信号变化的传递，例如比较重要的channel有`podUpdates <-chan UpdatePodOptions`，来传递pod的变化情况。

## 9.1. 创建pod的调用逻辑

`syncLoopIteration-->kubetypes.ADD-->HandlePodAdditions(u.Pods)-->dispatchWork(pod, kubetypes.SyncPodCreate, mirrorPod, start)-->podWorkers.UpdatePod-->managePodLoop(podUpdates)-->syncPod(o syncPodOptions)-->containerRuntime.SyncPod-->startContainer`

## 9.2. 各种manager

- `podManager`
- `probeManager`
- `statusManager`
- `podWorkers`
- `containerManager`
- `containerRuntime`
- `runtimeService`

## 9.3. 各种channel

- `configCh <-chan kubetypes.PodUpdate`
- `syncCh <-chan time.Time`
- `housekeepingCh <-chan time.Time`
- `plegCh <-chan *pleg.PodLifecycleEvent`
- `podUpdates <-chan UpdatePodOptions`



参考文章：

- https://github.com/kubernetes/kubernetes/tree/v1.12.0
- https://github.com/kubernetes/kubernetes/tree/v1.12.0/pkg/kubelet

