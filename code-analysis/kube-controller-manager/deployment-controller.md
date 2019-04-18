# kube-controller-manager源码分析（二）之 DeploymentController

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要以`deployment controller`为例，分析该类controller的运行逻辑。此部分代码主要为位于`pkg/controller/deployment`。`pkg/controller`部分的代码包括了各种类型的controller的具体实现。

`controller manager`的`pkg`部分代码目录结构如下：

```bash
controller  # 主要包含各种controller的具体实现
├── apis
├── bootstrap
├── certificates
├── client_builder.go
├── cloud
├── clusterroleaggregation
├── controller_ref_manager.go
├── controller_utils.go  # WaitForCacheSync
├── cronjob
├── daemon
├── deployment   # deployment controller
│   ├── deployment_controller.go # NewDeploymentController、Run、syncDeployment
│   ├── progress.go   # syncRolloutStatus
│   ├── recreate.go   # rolloutRecreate
│   ├── rollback.go   # rollback
│   ├── rolling.go    # rolloutRolling
│   ├── sync.go
├── disruption  # disruption controller
├── endpoint
├── garbagecollector
├── history
├── job
├── lookup_cache.go
├── namespace   # namespace controller
├── nodeipam
├── nodelifecycle
├── podautoscaler
├── podgc
├── replicaset   # replicaset controller
├── replication  # replication controller
├── resourcequota
├── route
├── service   # service controller
├── serviceaccount
├── statefulset   # statefulset controller
└── volume  # PersistentVolumeController、AttachDetachController、PVCProtectionController
```

# 1. [startDeploymentController](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/apps.go#L82)

```go
func startDeploymentController(ctx ControllerContext) (http.Handler, bool, error) {
	if !ctx.AvailableResources[schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "deployments"}] {
		return nil, false, nil
	}
	dc, err := deployment.NewDeploymentController(
		ctx.InformerFactory.Apps().V1().Deployments(),
		ctx.InformerFactory.Apps().V1().ReplicaSets(),
		ctx.InformerFactory.Core().V1().Pods(),
		ctx.ClientBuilder.ClientOrDie("deployment-controller"),
	)
	if err != nil {
		return nil, true, fmt.Errorf("error creating Deployment controller: %v", err)
	}
	go dc.Run(int(ctx.ComponentConfig.DeploymentController.ConcurrentDeploymentSyncs), ctx.Stop)
	return nil, true, nil
}
```

`startDeploymentController`主要调用的函数为`NewDeploymentController`和对应的`Run`函数。该部分逻辑在`kubernetes/pkg/controller`中。

# 2. NewDeploymentController

`NewDeploymentController`主要构建`DeploymentController`结构体。

该部分主要处理了以下逻辑：

- 构建并运行事件处理器`eventBroadcaster`。
- 初始化赋值`rsControl`、`clientset`、`workqueue`。
- 添加`dInformer`、`rsInformer`、`podInformer`的`ResourceEventHandlerFuncs`，其中主要为`AddFunc`、`UpdateFunc`、`DeleteFunc`三类方法。
- 构造deployment、rs、pod的Informer的Lister函数和HasSynced函数。
- 调用`syncHandler`，来实现`syncDeployment`。

## 2.1. eventBroadcaster

调用事件处理器来记录deployment相关的事件。

```go
eventBroadcaster := record.NewBroadcaster()
eventBroadcaster.StartLogging(glog.Infof)
// TODO: remove the wrapper when every clients have moved to use the clientset.
eventBroadcaster.StartRecordingToSink(&v1core.EventSinkImpl{Interface: v1core.New(client.CoreV1().RESTClient()).Events("")})
```

## 2.2. rsControl

构造`DeploymentController`，包括`clientset`、`workqueue`和`rsControl`。其中`rsControl`是具体实现rs逻辑的controller。

```go
dc := &DeploymentController{
	client:        client,
	eventRecorder: eventBroadcaster.NewRecorder(scheme.Scheme, v1.EventSource{Component: "deployment-controller"}),
	queue:         workqueue.NewNamedRateLimitingQueue(workqueue.DefaultControllerRateLimiter(), "deployment"),
}
dc.rsControl = controller.RealRSControl{
	KubeClient: client,
	Recorder:   dc.eventRecorder,
}
```

## 2.3. Informer().AddEventHandler

添加`dInformer`、`rsInformer`、`podInformer`的`ResourceEventHandlerFuncs`，其中主要为`AddFunc`、`UpdateFunc`、`DeleteFunc`三类方法。

```go
dInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
	AddFunc:    dc.addDeployment,
	UpdateFunc: dc.updateDeployment,
	// This will enter the sync loop and no-op, because the deployment has been deleted from the store.
	DeleteFunc: dc.deleteDeployment,
})
rsInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
	AddFunc:    dc.addReplicaSet,
	UpdateFunc: dc.updateReplicaSet,
	DeleteFunc: dc.deleteReplicaSet,
})
podInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
	DeleteFunc: dc.deletePod,
})
```

## 2.4. Informer.Lister()

调用`dInformer`、`rsInformer`和`podInformer`的`Lister()`方法。

```go
dc.dLister = dInformer.Lister()
dc.rsLister = rsInformer.Lister()
dc.podLister = podInformer.Lister()
```

## 2.5. Informer().HasSynced

调用`Informer().HasSynced`，判断是否缓存完成；

```go
dc.dListerSynced = dInformer.Informer().HasSynced
dc.rsListerSynced = rsInformer.Informer().HasSynced
dc.podListerSynced = podInformer.Informer().HasSynced
```

## 2.6. syncHandler

`syncHandler`具体为`syncDeployment`，syncHandler负责deployment的同步实现。

```go
dc.syncHandler = dc.syncDeployment
dc.enqueueDeployment = dc.enqueue
```

完整代码如下：

```go
// NewDeploymentController creates a new DeploymentController.
func NewDeploymentController(dInformer extensionsinformers.DeploymentInformer, rsInformer extensionsinformers.ReplicaSetInformer, podInformer coreinformers.PodInformer, client clientset.Interface) (*DeploymentController, error) {
	eventBroadcaster := record.NewBroadcaster()
	eventBroadcaster.StartLogging(glog.Infof)
	// TODO: remove the wrapper when every clients have moved to use the clientset.
	eventBroadcaster.StartRecordingToSink(&v1core.EventSinkImpl{Interface: v1core.New(client.CoreV1().RESTClient()).Events("")})

	if client != nil && client.CoreV1().RESTClient().GetRateLimiter() != nil {
		if err := metrics.RegisterMetricAndTrackRateLimiterUsage("deployment_controller", client.CoreV1().RESTClient().GetRateLimiter()); err != nil {
			return nil, err
		}
	}
	dc := &DeploymentController{
		client:        client,
		eventRecorder: eventBroadcaster.NewRecorder(scheme.Scheme, v1.EventSource{Component: "deployment-controller"}),
		queue:         workqueue.NewNamedRateLimitingQueue(workqueue.DefaultControllerRateLimiter(), "deployment"),
	}
	dc.rsControl = controller.RealRSControl{
		KubeClient: client,
		Recorder:   dc.eventRecorder,
	}

	dInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc:    dc.addDeployment,
		UpdateFunc: dc.updateDeployment,
		// This will enter the sync loop and no-op, because the deployment has been deleted from the store.
		DeleteFunc: dc.deleteDeployment,
	})
	rsInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc:    dc.addReplicaSet,
		UpdateFunc: dc.updateReplicaSet,
		DeleteFunc: dc.deleteReplicaSet,
	})
	podInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		DeleteFunc: dc.deletePod,
	})

	dc.syncHandler = dc.syncDeployment
	dc.enqueueDeployment = dc.enqueue

	dc.dLister = dInformer.Lister()
	dc.rsLister = rsInformer.Lister()
	dc.podLister = podInformer.Lister()
	dc.dListerSynced = dInformer.Informer().HasSynced
	dc.rsListerSynced = rsInformer.Informer().HasSynced
	dc.podListerSynced = podInformer.Informer().HasSynced
	return dc, nil
}
```

# 3. DeploymentController.Run

Run执行watch和sync的操作。

```go
// Run begins watching and syncing.
func (dc *DeploymentController) Run(workers int, stopCh <-chan struct{}) {
	defer utilruntime.HandleCrash()
	defer dc.queue.ShutDown()

	glog.Infof("Starting deployment controller")
	defer glog.Infof("Shutting down deployment controller")

	if !controller.WaitForCacheSync("deployment", stopCh, dc.dListerSynced, dc.rsListerSynced, dc.podListerSynced) {
		return
	}

	for i := 0; i < workers; i++ {
		go wait.Until(dc.worker, time.Second, stopCh)
	}

	<-stopCh
}
```

## 3.1. WaitForCacheSync

`WaitForCacheSync`主要是用来在`List-Watch`机制中可以保持当前cache的数据与etcd的数据一致。

```go
// WaitForCacheSync is a wrapper around cache.WaitForCacheSync that generates log messages
// indicating that the controller identified by controllerName is waiting for syncs, followed by
// either a successful or failed sync.
func WaitForCacheSync(controllerName string, stopCh <-chan struct{}, cacheSyncs ...cache.InformerSynced) bool {
	glog.Infof("Waiting for caches to sync for %s controller", controllerName)

	if !cache.WaitForCacheSync(stopCh, cacheSyncs...) {
		utilruntime.HandleError(fmt.Errorf("Unable to sync caches for %s controller", controllerName))
		return false
	}

	glog.Infof("Caches are synced for %s controller", controllerName)
	return true
}
```

## 3.2. dc.worker

`worker`调用了`processNextWorkItem`，`processNextWorkItem`最终调用了`syncHandler`，而`syncHandler`在`NewDeploymentController`中赋值的具体函数为`syncDeployment`。

```go
// worker runs a worker thread that just dequeues items, processes them, and marks them done.
// It enforces that the syncHandler is never invoked concurrently with the same key.
func (dc *DeploymentController) worker() {
	for dc.processNextWorkItem() {
	}
}

func (dc *DeploymentController) processNextWorkItem() bool {
	key, quit := dc.queue.Get()
	if quit {
		return false
	}
	defer dc.queue.Done(key)

	err := dc.syncHandler(key.(string))
	dc.handleErr(err, key)

	return true
}
```

`NewDeploymentController`中的`syncHandler`赋值：

```go
func NewDeploymentController(dInformer appsinformers.DeploymentInformer, rsInformer appsinformers.ReplicaSetInformer, podInformer coreinformers.PodInformer, client clientset.Interface) (*DeploymentController, error) {
	...
  dc.syncHandler = dc.syncDeployment
  ...
}  
```

# 4. syncDeployment

`syncDeployment`基于给定的key执行sync deployment的操作。

主要流程如下：

1. 通过`SplitMetaNamespaceKey`获取namespace和deployment对象的name。
2. 调用Lister的接口获取的deployment的对象。
3. `getReplicaSetsForDeployment`获取deployment管理的ReplicaSet对象。
4. `getPodMapForDeployment`获取deployment管理的pod，基于ReplicaSet来分组。
5. `checkPausedConditions`检查deployment是否是`pause`状态并添加合适的`condition`。
6. `isScalingEvent`检查deployment的更新是否来自于一个scale的事件，如果是则执行scale的操作。
7. 根据`DeploymentStrategyType`类型执行`rolloutRecreate`或`rolloutRolling`。

完整代码如下：

```go
// syncDeployment will sync the deployment with the given key.
// This function is not meant to be invoked concurrently with the same key.
func (dc *DeploymentController) syncDeployment(key string) error {
	startTime := time.Now()
	glog.V(4).Infof("Started syncing deployment %q (%v)", key, startTime)
	defer func() {
		glog.V(4).Infof("Finished syncing deployment %q (%v)", key, time.Since(startTime))
	}()

	namespace, name, err := cache.SplitMetaNamespaceKey(key)
	if err != nil {
		return err
	}
	deployment, err := dc.dLister.Deployments(namespace).Get(name)
	if errors.IsNotFound(err) {
		glog.V(2).Infof("Deployment %v has been deleted", key)
		return nil
	}
	if err != nil {
		return err
	}

	// Deep-copy otherwise we are mutating our cache.
	// TODO: Deep-copy only when needed.
	d := deployment.DeepCopy()

	everything := metav1.LabelSelector{}
	if reflect.DeepEqual(d.Spec.Selector, &everything) {
		dc.eventRecorder.Eventf(d, v1.EventTypeWarning, "SelectingAll", "This deployment is selecting all pods. A non-empty selector is required.")
		if d.Status.ObservedGeneration < d.Generation {
			d.Status.ObservedGeneration = d.Generation
			dc.client.ExtensionsV1beta1().Deployments(d.Namespace).UpdateStatus(d)
		}
		return nil
	}

	// List ReplicaSets owned by this Deployment, while reconciling ControllerRef
	// through adoption/orphaning.
	rsList, err := dc.getReplicaSetsForDeployment(d)
	if err != nil {
		return err
	}
	// List all Pods owned by this Deployment, grouped by their ReplicaSet.
	// Current uses of the podMap are:
	//
	// * check if a Pod is labeled correctly with the pod-template-hash label.
	// * check that no old Pods are running in the middle of Recreate Deployments.
	podMap, err := dc.getPodMapForDeployment(d, rsList)
	if err != nil {
		return err
	}

	if d.DeletionTimestamp != nil {
		return dc.syncStatusOnly(d, rsList, podMap)
	}

	// Update deployment conditions with an Unknown condition when pausing/resuming
	// a deployment. In this way, we can be sure that we won't timeout when a user
	// resumes a Deployment with a set progressDeadlineSeconds.
	if err = dc.checkPausedConditions(d); err != nil {
		return err
	}

	if d.Spec.Paused {
		return dc.sync(d, rsList, podMap)
	}

	// rollback is not re-entrant in case the underlying replica sets are updated with a new
	// revision so we should ensure that we won't proceed to update replica sets until we
	// make sure that the deployment has cleaned up its rollback spec in subsequent enqueues.
	if d.Spec.RollbackTo != nil {
		return dc.rollback(d, rsList, podMap)
	}

	scalingEvent, err := dc.isScalingEvent(d, rsList, podMap)
	if err != nil {
		return err
	}
	if scalingEvent {
		return dc.sync(d, rsList, podMap)
	}

	switch d.Spec.Strategy.Type {
	case extensions.RecreateDeploymentStrategyType:
		return dc.rolloutRecreate(d, rsList, podMap)
	case extensions.RollingUpdateDeploymentStrategyType:
		return dc.rolloutRolling(d, rsList, podMap)
	}
	return fmt.Errorf("unexpected deployment strategy type: %s", d.Spec.Strategy.Type)
}
```

## 4.1. Get deployment

```go
// get namespace and deployment name
namespace, name, err := cache.SplitMetaNamespaceKey(key)
// get deployment by name
deployment, err := dc.dLister.Deployments(namespace).Get(name)
```

## 4.2. getReplicaSetsForDeployment

```go
// List ReplicaSets owned by this Deployment, while reconciling ControllerRef
// through adoption/orphaning.
rsList, err := dc.getReplicaSetsForDeployment(d)
```

**getReplicaSetsForDeployment具体代码:**

```go
// getReplicaSetsForDeployment uses ControllerRefManager to reconcile
// ControllerRef by adopting and orphaning.
// It returns the list of ReplicaSets that this Deployment should manage.
func (dc *DeploymentController) getReplicaSetsForDeployment(d *apps.Deployment) ([]*apps.ReplicaSet, error) {
	// List all ReplicaSets to find those we own but that no longer match our
	// selector. They will be orphaned by ClaimReplicaSets().
	rsList, err := dc.rsLister.ReplicaSets(d.Namespace).List(labels.Everything())
	if err != nil {
		return nil, err
	}
	deploymentSelector, err := metav1.LabelSelectorAsSelector(d.Spec.Selector)
	if err != nil {
		return nil, fmt.Errorf("deployment %s/%s has invalid label selector: %v", d.Namespace, d.Name, err)
	}
	// If any adoptions are attempted, we should first recheck for deletion with
	// an uncached quorum read sometime after listing ReplicaSets (see #42639).
	canAdoptFunc := controller.RecheckDeletionTimestamp(func() (metav1.Object, error) {
		fresh, err := dc.client.AppsV1().Deployments(d.Namespace).Get(d.Name, metav1.GetOptions{})
		if err != nil {
			return nil, err
		}
		if fresh.UID != d.UID {
			return nil, fmt.Errorf("original Deployment %v/%v is gone: got uid %v, wanted %v", d.Namespace, d.Name, fresh.UID, d.UID)
		}
		return fresh, nil
	})
	cm := controller.NewReplicaSetControllerRefManager(dc.rsControl, d, deploymentSelector, controllerKind, canAdoptFunc)
	return cm.ClaimReplicaSets(rsList)
}
```

## 4.3. getPodMapForDeployment

```go
// List all Pods owned by this Deployment, grouped by their ReplicaSet.
// Current uses of the podMap are:
//
// * check if a Pod is labeled correctly with the pod-template-hash label.
// * check that no old Pods are running in the middle of Recreate Deployments.
podMap, err := dc.getPodMapForDeployment(d, rsList)
```

**getPodMapForDeployment具体代码：**

```go
// getPodMapForDeployment returns the Pods managed by a Deployment.
//
// It returns a map from ReplicaSet UID to a list of Pods controlled by that RS,
// according to the Pod's ControllerRef.
func (dc *DeploymentController) getPodMapForDeployment(d *apps.Deployment, rsList []*apps.ReplicaSet) (map[types.UID]*v1.PodList, error) {
	// Get all Pods that potentially belong to this Deployment.
	selector, err := metav1.LabelSelectorAsSelector(d.Spec.Selector)
	if err != nil {
		return nil, err
	}
	pods, err := dc.podLister.Pods(d.Namespace).List(selector)
	if err != nil {
		return nil, err
	}
	// Group Pods by their controller (if it's in rsList).
	podMap := make(map[types.UID]*v1.PodList, len(rsList))
	for _, rs := range rsList {
		podMap[rs.UID] = &v1.PodList{}
	}
	for _, pod := range pods {
		// Do not ignore inactive Pods because Recreate Deployments need to verify that no
		// Pods from older versions are running before spinning up new Pods.
		controllerRef := metav1.GetControllerOf(pod)
		if controllerRef == nil {
			continue
		}
		// Only append if we care about this UID.
		if podList, ok := podMap[controllerRef.UID]; ok {
			podList.Items = append(podList.Items, *pod)
		}
	}
	return podMap, nil
}
```

## 4.4. checkPausedConditions

```go
// Update deployment conditions with an Unknown condition when pausing/resuming
// a deployment. In this way, we can be sure that we won't timeout when a user
// resumes a Deployment with a set progressDeadlineSeconds.
if err = dc.checkPausedConditions(d); err != nil {
	return err
}

if d.Spec.Paused {
	return dc.sync(d, rsList)
}
```

**checkPausedConditions具体代码:**

```go
// checkPausedConditions checks if the given deployment is paused or not and adds an appropriate condition.
// These conditions are needed so that we won't accidentally report lack of progress for resumed deployments
// that were paused for longer than progressDeadlineSeconds.
func (dc *DeploymentController) checkPausedConditions(d *apps.Deployment) error {
	if !deploymentutil.HasProgressDeadline(d) {
		return nil
	}
	cond := deploymentutil.GetDeploymentCondition(d.Status, apps.DeploymentProgressing)
	if cond != nil && cond.Reason == deploymentutil.TimedOutReason {
		// If we have reported lack of progress, do not overwrite it with a paused condition.
		return nil
	}
	pausedCondExists := cond != nil && cond.Reason == deploymentutil.PausedDeployReason

	needsUpdate := false
	if d.Spec.Paused && !pausedCondExists {
		condition := deploymentutil.NewDeploymentCondition(apps.DeploymentProgressing, v1.ConditionUnknown, deploymentutil.PausedDeployReason, "Deployment is paused")
		deploymentutil.SetDeploymentCondition(&d.Status, *condition)
		needsUpdate = true
	} else if !d.Spec.Paused && pausedCondExists {
		condition := deploymentutil.NewDeploymentCondition(apps.DeploymentProgressing, v1.ConditionUnknown, deploymentutil.ResumedDeployReason, "Deployment is resumed")
		deploymentutil.SetDeploymentCondition(&d.Status, *condition)
		needsUpdate = true
	}

	if !needsUpdate {
		return nil
	}

	var err error
	d, err = dc.client.AppsV1().Deployments(d.Namespace).UpdateStatus(d)
	return err
}
```

## 4.5. isScalingEvent

```go
scalingEvent, err := dc.isScalingEvent(d, rsList)
if err != nil {
	return err
}
if scalingEvent {
	return dc.sync(d, rsList)
}
```

**isScalingEvent具体代码:**

```go
// isScalingEvent checks whether the provided deployment has been updated with a scaling event
// by looking at the desired-replicas annotation in the active replica sets of the deployment.
//
// rsList should come from getReplicaSetsForDeployment(d).
// podMap should come from getPodMapForDeployment(d, rsList).
func (dc *DeploymentController) isScalingEvent(d *apps.Deployment, rsList []*apps.ReplicaSet) (bool, error) {
	newRS, oldRSs, err := dc.getAllReplicaSetsAndSyncRevision(d, rsList, false)
	if err != nil {
		return false, err
	}
	allRSs := append(oldRSs, newRS)
	for _, rs := range controller.FilterActiveReplicaSets(allRSs) {
		desired, ok := deploymentutil.GetDesiredReplicasAnnotation(rs)
		if !ok {
			continue
		}
		if desired != *(d.Spec.Replicas) {
			return true, nil
		}
	}
	return false, nil
}
```

## 4.6. rolloutRecreate

```go
switch d.Spec.Strategy.Type {
case apps.RecreateDeploymentStrategyType:
	return dc.rolloutRecreate(d, rsList, podMap)
```

**rolloutRecreate具体代码:**

```go
// rolloutRecreate implements the logic for recreating a replica set.
func (dc *DeploymentController) rolloutRecreate(d *apps.Deployment, rsList []*apps.ReplicaSet, podMap map[types.UID]*v1.PodList) error {
	// Don't create a new RS if not already existed, so that we avoid scaling up before scaling down.
	newRS, oldRSs, err := dc.getAllReplicaSetsAndSyncRevision(d, rsList, false)
	if err != nil {
		return err
	}
	allRSs := append(oldRSs, newRS)
	activeOldRSs := controller.FilterActiveReplicaSets(oldRSs)

	// scale down old replica sets.
	scaledDown, err := dc.scaleDownOldReplicaSetsForRecreate(activeOldRSs, d)
	if err != nil {
		return err
	}
	if scaledDown {
		// Update DeploymentStatus.
		return dc.syncRolloutStatus(allRSs, newRS, d)
	}

	// Do not process a deployment when it has old pods running.
	if oldPodsRunning(newRS, oldRSs, podMap) {
		return dc.syncRolloutStatus(allRSs, newRS, d)
	}

	// If we need to create a new RS, create it now.
	if newRS == nil {
		newRS, oldRSs, err = dc.getAllReplicaSetsAndSyncRevision(d, rsList, true)
		if err != nil {
			return err
		}
		allRSs = append(oldRSs, newRS)
	}

	// scale up new replica set.
	if _, err := dc.scaleUpNewReplicaSetForRecreate(newRS, d); err != nil {
		return err
	}

	if util.DeploymentComplete(d, &d.Status) {
		if err := dc.cleanupDeployment(oldRSs, d); err != nil {
			return err
		}
	}

	// Sync deployment status.
	return dc.syncRolloutStatus(allRSs, newRS, d)
}
```

## 4.7. rolloutRolling

```go
switch d.Spec.Strategy.Type {
case apps.RecreateDeploymentStrategyType:
	return dc.rolloutRecreate(d, rsList, podMap)
case apps.RollingUpdateDeploymentStrategyType:
	return dc.rolloutRolling(d, rsList)
}
```

**rolloutRolling具体代码:**

```go
// rolloutRolling implements the logic for rolling a new replica set.
func (dc *DeploymentController) rolloutRolling(d *apps.Deployment, rsList []*apps.ReplicaSet) error {
	newRS, oldRSs, err := dc.getAllReplicaSetsAndSyncRevision(d, rsList, true)
	if err != nil {
		return err
	}
	allRSs := append(oldRSs, newRS)

	// Scale up, if we can.
	scaledUp, err := dc.reconcileNewReplicaSet(allRSs, newRS, d)
	if err != nil {
		return err
	}
	if scaledUp {
		// Update DeploymentStatus
		return dc.syncRolloutStatus(allRSs, newRS, d)
	}

	// Scale down, if we can.
	scaledDown, err := dc.reconcileOldReplicaSets(allRSs, controller.FilterActiveReplicaSets(oldRSs), newRS, d)
	if err != nil {
		return err
	}
	if scaledDown {
		// Update DeploymentStatus
		return dc.syncRolloutStatus(allRSs, newRS, d)
	}

	if deploymentutil.DeploymentComplete(d, &d.Status) {
		if err := dc.cleanupDeployment(oldRSs, d); err != nil {
			return err
		}
	}

	// Sync deployment status
	return dc.syncRolloutStatus(allRSs, newRS, d)
}
```

# 5. 总结

`startDeploymentController`主要包括`NewDeploymentController`和`DeploymentController.Run`两部分。

`NewDeploymentController`主要构建`DeploymentController`结构体。

该部分主要处理了以下逻辑：

1. 构建并运行事件处理器`eventBroadcaster`。
2. 初始化赋值`rsControl`、`clientset`、`workqueue`。
3. 添加`dInformer`、`rsInformer`、`podInformer`的`ResourceEventHandlerFuncs`，其中主要为`AddFunc`、`UpdateFunc`、`DeleteFunc`三类方法。
4. 构造deployment、rs、pod的Informer的Lister函数和HasSynced函数。
5. 赋值`syncHandler`，来实现`syncDeployment`。



`DeploymentController.Run`主要包含`WaitForCacheSync`和`syncDeployment`两部分。

`syncDeployment`基于给定的key执行sync deployment的操作。

主要流程如下：

1. 通过`SplitMetaNamespaceKey`获取namespace和deployment对象的name。
2. 调用Lister的接口获取的deployment的对象。
3. `getReplicaSetsForDeployment`获取deployment管理的ReplicaSet对象。
4. `getPodMapForDeployment`获取deployment管理的pod，基于ReplicaSet来分组。
5. `checkPausedConditions`检查deployment是否是`pause`状态并添加合适的`condition`。
6. `isScalingEvent`检查deployment的更新是否来自于一个scale的事件，如果是则执行scale的操作。
7. 根据`DeploymentStrategyType`类型执行`rolloutRecreate`或`rolloutRolling`。



参考：

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/controller/deployment/deployment_controller.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/controller/deployment/rolling.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/apps.go>



