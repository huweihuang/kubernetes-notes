# kubelet源码分析（五）之 syncPod

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析`kubelet`中`syncPod`的部分。

# 1. [managePodLoop](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/pod_workers.go#L153)

`managePodLoop`通过读取`podUpdates`channel的信息，执行`syncPodFn`函数，而`syncPodFn`函数在`newPodWorkers`的时候赋值了，即`kubelet.syncPod`。

managePodLoop完整代码如下：

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
      // 该部分的syncPodFn实际上的实现函数是kubelet.syncPod
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

以下分析`syncPod`相关逻辑。

# 2. [syncPod](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1465)

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

> syncPod的代码位于pkg/kubelet/kubelet.go

## 2.1. SyncPodKill

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

## 2.2. SyncPodCreate

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

## 2.3. Cgroups

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

## 2.4. Mirror Pod

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

## 2.5. makePodDataDirs

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

## 2.6. mount volumes

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

## 2.7. PullSecretsForPod

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

## 2.8. containerRuntime.SyncPod

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

# 3. [Runtime.SyncPod](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kuberuntime/kuberuntime_manager.go#L578)

`SyncPod`主要执行sync操作使得运行的pod达到期望状态的pod。主要执行以下操作：

- 计算`sandbox`和`container`的变化。
- 必要的时候杀死pod。
- 杀死所有不需要运行的`container`。
- 必要时创建`sandbox`。
- 创建`init container`。
- 创建正常的`container`。

> Runtime.SyncPod部分代码位于pkg/kubelet/kuberuntime/kuberuntime_manager.go

## 3.1. computePodActions

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

## 3.2. killPodWithSyncResult

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

## 3.3. killContainer

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

## 3.4. createPodSandbox

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

## 3.5. start init container

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

## 3.6. start containers

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
  // 通过startContainer来运行容器
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

# 4. [startContainer](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kuberuntime/kuberuntime_container.go#L89)

`startContainer`启动一个容器并返回是否成功。

主要包括以下几个步骤：

1. 拉取镜像
2. 创建容器
3. 启动容器
4. 运行post start lifecycle hooks(如果有设置此项)

`startContainer`完整代码如下：

> startContainer部分代码位于pkg/kubelet/kuberuntime/kuberuntime_container.go

```go
// startContainer starts a container and returns a message indicates why it is failed on error.
// It starts the container through the following steps:
// * pull the image
// * create the container
// * start the container
// * run the post start lifecycle hooks (if applicable)
func (m *kubeGenericRuntimeManager) startContainer(podSandboxID string, podSandboxConfig *runtimeapi.PodSandboxConfig, container *v1.Container, pod *v1.Pod, podStatus *kubecontainer.PodStatus, pullSecrets []v1.Secret, podIP string, containerType kubecontainer.ContainerType) (string, error) {
	// Step 1: pull the image.
	imageRef, msg, err := m.imagePuller.EnsureImageExists(pod, container, pullSecrets)
	if err != nil {
		m.recordContainerEvent(pod, container, "", v1.EventTypeWarning, events.FailedToCreateContainer, "Error: %v", grpc.ErrorDesc(err))
		return msg, err
	}

	// Step 2: create the container.
	ref, err := kubecontainer.GenerateContainerRef(pod, container)
	if err != nil {
		glog.Errorf("Can't make a ref to pod %q, container %v: %v", format.Pod(pod), container.Name, err)
	}
	glog.V(4).Infof("Generating ref for container %s: %#v", container.Name, ref)

	// For a new container, the RestartCount should be 0
	restartCount := 0
	containerStatus := podStatus.FindContainerStatusByName(container.Name)
	if containerStatus != nil {
		restartCount = containerStatus.RestartCount + 1
	}

	containerConfig, cleanupAction, err := m.generateContainerConfig(container, pod, restartCount, podIP, imageRef, containerType)
	if cleanupAction != nil {
		defer cleanupAction()
	}
	if err != nil {
		m.recordContainerEvent(pod, container, "", v1.EventTypeWarning, events.FailedToCreateContainer, "Error: %v", grpc.ErrorDesc(err))
		return grpc.ErrorDesc(err), ErrCreateContainerConfig
	}

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

	return "", nil
}
```

以下对`startContainer`分段分析：

## 4.1. pull image

通过`EnsureImageExists`方法拉取拉取指定pod容器的镜像，并返回镜像信息和错误。

```go
// Step 1: pull the image.
imageRef, msg, err := m.imagePuller.EnsureImageExists(pod, container, pullSecrets)
if err != nil {
	m.recordContainerEvent(pod, container, "", v1.EventTypeWarning, events.FailedToCreateContainer, "Error: %v", grpc.ErrorDesc(err))
	return msg, err
}
```

## 4.2. CreateContainer

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

## 4.3. StartContainer

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

## 4.4. execute post start hook

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

# 5. 总结

kubelet的工作是管理pod在Node上的生命周期（包括增删改查），kubelet通过各种类型的manager异步工作各自执行各自的任务，其中使用到了多种的channel来控制状态信号变化的传递，例如比较重要的channel有`podUpdates <-chan UpdatePodOptions`，来传递pod的变化情况。

**创建pod的调用逻辑**

`syncLoopIteration-->kubetypes.ADD-->HandlePodAdditions(u.Pods)-->dispatchWork(pod, kubetypes.SyncPodCreate, mirrorPod, start)-->podWorkers.UpdatePod-->managePodLoop(podUpdates)-->syncPod(o syncPodOptions)-->containerRuntime.SyncPod-->startContainer`





参考：

- https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/pod_workers.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kuberuntime/kuberuntime_container.go>