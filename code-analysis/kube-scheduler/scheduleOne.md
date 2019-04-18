# kube-scheduler源码分析（三）之 scheduleOne

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析`/pkg/scheduler/`中调度的基本流程。具体的`预选调度逻辑`、`优选调度逻辑`、`节点抢占逻辑`待后续再独立分析。

scheduler的`pkg`代码目录结构如下：

```bash
scheduler
├── algorithm         # 主要包含调度的算法
│   ├── predicates    # 预选的策略
│   ├── priorities    # 优选的策略
│   ├── scheduler_interface.go    # ScheduleAlgorithm、SchedulerExtender接口定义
│   ├── types.go      # 使用到的type的定义
├── algorithmprovider
│   ├── defaults
│   │   ├── defaults.go    # 默认算法的初始化操作，包括预选和优选策略
├── cache      # scheduler调度使用到的cache
│   ├── cache.go    # schedulerCache
│   ├── interface.go
│   ├── node_info.go
│   ├── node_tree.go
├── core       # 调度逻辑的核心代码
│   ├── equivalence
│   │   ├── eqivalence.go       # 存储相同pod的调度结果缓存，主要给预选策略使用
│   ├── extender.go
│   ├── generic_scheduler.go    # genericScheduler,主要包含默认调度器的调度逻辑
│   ├── scheduling_queue.go     # 调度使用到的队列，主要用来存储需要被调度的pod
├── factory
│   ├── factory.go   # 主要包括NewConfigFactory、NewPodInformer，监听pod事件来更新调度队列
├── metrics
│   └── metrics.go   # 主要给prometheus使用
├── scheduler.go # pkg部分的Run入口(核心代码)，主要包含Run、scheduleOne、schedule、preempt等函数
└── volumebinder
    └── volume_binder.go   # volume bind
```

# 1. [Scheduler.Run](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/scheduler.go#L181)

> 此部分代码位于pkg/scheduler/scheduler.go

此处为具体调度逻辑的入口。

```go
// Run begins watching and scheduling. It waits for cache to be synced, then starts a goroutine and returns immediately.
func (sched *Scheduler) Run() {
	if !sched.config.WaitForCacheSync() {
		return
	}

	go wait.Until(sched.scheduleOne, 0, sched.config.StopEverything)
}
```

# 2. [Scheduler.scheduleOne](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/scheduler.go#L395)

> 此部分代码位于pkg/scheduler/scheduler.go

`scheduleOne`主要为单个pod选择一个适合的节点，为调度逻辑的核心函数。

**对单个pod进行调度的基本流程如下：**

1. 通过podQueue的待调度队列中弹出需要调度的pod。
2. 通过具体的调度算法为该pod选出合适的节点，其中调度算法就包括预选和优选两步策略。
3. 如果上述调度失败，则会尝试抢占机制，将优先级低的pod剔除，让优先级高的pod调度成功。
4. 将该pod和选定的节点进行假性绑定，存入scheduler cache中，方便具体绑定操作可以异步进行。
5. 实际执行绑定操作，将node的名字添加到pod的节点相关属性中。



完整代码如下：

```go
// scheduleOne does the entire scheduling workflow for a single pod.  It is serialized on the scheduling algorithm's host fitting.
func (sched *Scheduler) scheduleOne() {
	pod := sched.config.NextPod()
	if pod.DeletionTimestamp != nil {
		sched.config.Recorder.Eventf(pod, v1.EventTypeWarning, "FailedScheduling", "skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
		glog.V(3).Infof("Skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
		return
	}

	glog.V(3).Infof("Attempting to schedule pod: %v/%v", pod.Namespace, pod.Name)

	// Synchronously attempt to find a fit for the pod.
	start := time.Now()
	suggestedHost, err := sched.schedule(pod)
	if err != nil {
		// schedule() may have failed because the pod would not fit on any host, so we try to
		// preempt, with the expectation that the next time the pod is tried for scheduling it
		// will fit due to the preemption. It is also possible that a different pod will schedule
		// into the resources that were preempted, but this is harmless.
		if fitError, ok := err.(*core.FitError); ok {
			preemptionStartTime := time.Now()
			sched.preempt(pod, fitError)
			metrics.PreemptionAttempts.Inc()
			metrics.SchedulingAlgorithmPremptionEvaluationDuration.Observe(metrics.SinceInMicroseconds(preemptionStartTime))
			metrics.SchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
		}
		return
	}
	metrics.SchedulingAlgorithmLatency.Observe(metrics.SinceInMicroseconds(start))
	// Tell the cache to assume that a pod now is running on a given node, even though it hasn't been bound yet.
	// This allows us to keep scheduling without waiting on binding to occur.
	assumedPod := pod.DeepCopy()

	// Assume volumes first before assuming the pod.
	//
	// If all volumes are completely bound, then allBound is true and binding will be skipped.
	//
	// Otherwise, binding of volumes is started after the pod is assumed, but before pod binding.
	//
	// This function modifies 'assumedPod' if volume binding is required.
	allBound, err := sched.assumeVolumes(assumedPod, suggestedHost)
	if err != nil {
		return
	}

	// assume modifies `assumedPod` by setting NodeName=suggestedHost
	err = sched.assume(assumedPod, suggestedHost)
	if err != nil {
		return
	}
	// bind the pod to its host asynchronously (we can do this b/c of the assumption step above).
	go func() {
		// Bind volumes first before Pod
		if !allBound {
			err = sched.bindVolumes(assumedPod)
			if err != nil {
				return
			}
		}

		err := sched.bind(assumedPod, &v1.Binding{
			ObjectMeta: metav1.ObjectMeta{Namespace: assumedPod.Namespace, Name: assumedPod.Name, UID: assumedPod.UID},
			Target: v1.ObjectReference{
				Kind: "Node",
				Name: suggestedHost,
			},
		})
		metrics.E2eSchedulingLatency.Observe(metrics.SinceInMicroseconds(start))
		if err != nil {
			glog.Errorf("Internal error binding pod: (%v)", err)
		}
	}()
}
```

以下对重要代码分别进行分析。

# 3. config.NextPod

通过`podQueue`的方式存储待调度的pod队列，`NextPod`拿出下一个需要被调度的pod。

```go
pod := sched.config.NextPod()
if pod.DeletionTimestamp != nil {
	sched.config.Recorder.Eventf(pod, v1.EventTypeWarning, "FailedScheduling", "skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
	glog.V(3).Infof("Skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
	return
}

glog.V(3).Infof("Attempting to schedule pod: %v/%v", pod.Namespace, pod.Name)
```

`NextPod`的具体函数在factory.go的CreateFromKey函数中定义，如下：

```go
func (c *configFactory) CreateFromKeys(predicateKeys, priorityKeys sets.String, extenders []algorithm.SchedulerExtender) (*scheduler.Config, error) {
...
  	return &scheduler.Config{
    ...
		NextPod: func() *v1.Pod {
			return c.getNextPod()
		}
    ...
}      
```

## 3.1. getNextPod

通过一个podQueue来存储需要调度的pod的队列，通过队列Pop的方式弹出需要被调度的pod。

```go
func (c *configFactory) getNextPod() *v1.Pod {
	pod, err := c.podQueue.Pop()
	if err == nil {
		glog.V(4).Infof("About to try and schedule pod %v/%v", pod.Namespace, pod.Name)
		return pod
	}
	glog.Errorf("Error while retrieving next pod from scheduling queue: %v", err)
	return nil
}

```

# 4. Scheduler.schedule

> 此部分代码位于pkg/scheduler/scheduler.go

此部分为调度逻辑的核心，通过不同的算法为具体的pod选择一个最合适的节点。

```go
// Synchronously attempt to find a fit for the pod.
start := time.Now()
suggestedHost, err := sched.schedule(pod)
if err != nil {
	// schedule() may have failed because the pod would not fit on any host, so we try to
	// preempt, with the expectation that the next time the pod is tried for scheduling it
	// will fit due to the preemption. It is also possible that a different pod will schedule
	// into the resources that were preempted, but this is harmless.
	if fitError, ok := err.(*core.FitError); ok {
		preemptionStartTime := time.Now()
		sched.preempt(pod, fitError)
		metrics.PreemptionAttempts.Inc()
		metrics.SchedulingAlgorithmPremptionEvaluationDuration.Observe(metrics.SinceInMicroseconds(preemptionStartTime))
		metrics.SchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
	}
	return
}
```

`schedule`通过调度算法返回一个最优的节点。

```go
// schedule implements the scheduling algorithm and returns the suggested host.
func (sched *Scheduler) schedule(pod *v1.Pod) (string, error) {
	host, err := sched.config.Algorithm.Schedule(pod, sched.config.NodeLister)
	if err != nil {
		pod = pod.DeepCopy()
		sched.config.Error(pod, err)
		sched.config.Recorder.Eventf(pod, v1.EventTypeWarning, "FailedScheduling", "%v", err)
		sched.config.PodConditionUpdater.Update(pod, &v1.PodCondition{
			Type:    v1.PodScheduled,
			Status:  v1.ConditionFalse,
			Reason:  v1.PodReasonUnschedulable,
			Message: err.Error(),
		})
		return "", err
	}
	return host, err
}
```

## 4.1. ScheduleAlgorithm

`ScheduleAlgorithm`是一个调度算法的接口，主要的实现体是`genericScheduler`，后续分析`genericScheduler.Schedule`。

`ScheduleAlgorithm`接口定义如下：

```go
// ScheduleAlgorithm is an interface implemented by things that know how to schedule pods
// onto machines.
type ScheduleAlgorithm interface {
	Schedule(*v1.Pod, NodeLister) (selectedMachine string, err error)
	// Preempt receives scheduling errors for a pod and tries to create room for
	// the pod by preempting lower priority pods if possible.
	// It returns the node where preemption happened, a list of preempted pods, a
	// list of pods whose nominated node name should be removed, and error if any.
	Preempt(*v1.Pod, NodeLister, error) (selectedNode *v1.Node, preemptedPods []*v1.Pod, cleanupNominatedPods []*v1.Pod, err error)
	// Predicates() returns a pointer to a map of predicate functions. This is
	// exposed for testing.
	Predicates() map[string]FitPredicate
	// Prioritizers returns a slice of priority config. This is exposed for
	// testing.
	Prioritizers() []PriorityConfig
}
```

# 5. [genericScheduler.Schedule](<https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go#L117>)

> 此部分代码位于/pkg/scheduler/core/generic_scheduler.go

`genericScheduler.Schedule`实现了基本的调度逻辑，基于给定需要调度的pod和node列表，如果执行成功返回调度的节点的名字，如果执行失败，则返回错误和原因。主要通过预选和优选两步操作完成调度的逻辑。

**基本流程如下：**

1. 对pod做基本性检查，目前主要是对pvc的检查。
2. 通过`findNodesThatFit`预选策略选出满足调度条件的node列表。
3. 通过`PrioritizeNodes`优选策略给预选的node列表中的node进行打分。
4. 在打分的node列表中选择一个分数最高的node作为调度的节点。



完整代码如下：

```go
// Schedule tries to schedule the given pod to one of the nodes in the node list.
// If it succeeds, it will return the name of the node.
// If it fails, it will return a FitError error with reasons.
func (g *genericScheduler) Schedule(pod *v1.Pod, nodeLister algorithm.NodeLister) (string, error) {
	trace := utiltrace.New(fmt.Sprintf("Scheduling %s/%s", pod.Namespace, pod.Name))
	defer trace.LogIfLong(100 * time.Millisecond)

	if err := podPassesBasicChecks(pod, g.pvcLister); err != nil {
		return "", err
	}

	nodes, err := nodeLister.List()
	if err != nil {
		return "", err
	}
	if len(nodes) == 0 {
		return "", ErrNoNodesAvailable
	}

	// Used for all fit and priority funcs.
	err = g.cache.UpdateNodeNameToInfoMap(g.cachedNodeInfoMap)
	if err != nil {
		return "", err
	}

	trace.Step("Computing predicates")
	startPredicateEvalTime := time.Now()
	filteredNodes, failedPredicateMap, err := g.findNodesThatFit(pod, nodes)
	if err != nil {
		return "", err
	}

	if len(filteredNodes) == 0 {
		return "", &FitError{
			Pod:              pod,
			NumAllNodes:      len(nodes),
			FailedPredicates: failedPredicateMap,
		}
	}
	metrics.SchedulingAlgorithmPredicateEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPredicateEvalTime))
	metrics.SchedulingLatency.WithLabelValues(metrics.PredicateEvaluation).Observe(metrics.SinceInSeconds(startPredicateEvalTime))

	trace.Step("Prioritizing")
	startPriorityEvalTime := time.Now()
	// When only one node after predicate, just use it.
	if len(filteredNodes) == 1 {
		metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
		return filteredNodes[0].Name, nil
	}

	metaPrioritiesInterface := g.priorityMetaProducer(pod, g.cachedNodeInfoMap)
	priorityList, err := PrioritizeNodes(pod, g.cachedNodeInfoMap, metaPrioritiesInterface, g.prioritizers, filteredNodes, g.extenders)
	if err != nil {
		return "", err
	}
	metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
	metrics.SchedulingLatency.WithLabelValues(metrics.PriorityEvaluation).Observe(metrics.SinceInSeconds(startPriorityEvalTime))

	trace.Step("Selecting host")
	return g.selectHost(priorityList)
}
```

## 5.1. podPassesBasicChecks

podPassesBasicChecks主要做一下基本性检查，目前主要是对pvc的检查。

```GO
if err := podPassesBasicChecks(pod, g.pvcLister); err != nil {
	return "", err
}
```

podPassesBasicChecks具体实现如下：

```go
// podPassesBasicChecks makes sanity checks on the pod if it can be scheduled.
func podPassesBasicChecks(pod *v1.Pod, pvcLister corelisters.PersistentVolumeClaimLister) error {
	// Check PVCs used by the pod
	namespace := pod.Namespace
	manifest := &(pod.Spec)
	for i := range manifest.Volumes {
		volume := &manifest.Volumes[i]
		if volume.PersistentVolumeClaim == nil {
			// Volume is not a PVC, ignore
			continue
		}
		pvcName := volume.PersistentVolumeClaim.ClaimName
		pvc, err := pvcLister.PersistentVolumeClaims(namespace).Get(pvcName)
		if err != nil {
			// The error has already enough context ("persistentvolumeclaim "myclaim" not found")
			return err
		}

		if pvc.DeletionTimestamp != nil {
			return fmt.Errorf("persistentvolumeclaim %q is being deleted", pvc.Name)
		}
	}

	return nil
}
```

## 5.2. findNodesThatFit

预选，通过预选函数来判断每个节点是否适合被该Pod调度。

> 具体的`findNodesThatFit`代码实现细节待后续文章独立分析。

`genericScheduler.Schedule`中对`findNodesThatFit`的调用过程如下：

```go
trace.Step("Computing predicates")
startPredicateEvalTime := time.Now()
filteredNodes, failedPredicateMap, err := g.findNodesThatFit(pod, nodes)
if err != nil {
	return "", err
}

if len(filteredNodes) == 0 {
	return "", &FitError{
		Pod:              pod,
		NumAllNodes:      len(nodes),
		FailedPredicates: failedPredicateMap,
	}
}
metrics.SchedulingAlgorithmPredicateEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPredicateEvalTime))
	metrics.SchedulingLatency.WithLabelValues(metrics.PredicateEvaluation).Observe(metrics.SinceInSeconds(startPredicateEvalTime))
```

## 5.3. PrioritizeNodes

优选，从满足的节点中选择出最优的节点。

具体操作如下：

- PrioritizeNodes通过并行运行各个优先级函数来对节点进行优先级排序。
- 每个优先级函数会给节点打分，打分范围为0-10分。
- 0 表示优先级最低的节点，10表示优先级最高的节点。
- 每个优先级函数也有各自的权重。
- 优先级函数返回的节点分数乘以权重以获得加权分数。
- 最后组合（添加）所有分数以获得所有节点的总加权分数。

> 具体`PrioritizeNodes`的实现逻辑待后续文章独立分析。

`genericScheduler.Schedule`中对`PrioritizeNodes`的调用过程如下：

```go
trace.Step("Prioritizing")
startPriorityEvalTime := time.Now()
// When only one node after predicate, just use it.
if len(filteredNodes) == 1 {
	metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
	return filteredNodes[0].Name, nil
}
metaPrioritiesInterface := g.priorityMetaProducer(pod, g.cachedNodeInfoMap)
priorityList, err := PrioritizeNodes(pod, g.cachedNodeInfoMap, metaPrioritiesInterface, g.prioritizers, filteredNodes, g.extenders)
if err != nil {
	return "", err
}
	metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
	metrics.SchedulingLatency.WithLabelValues(metrics.PriorityEvaluation).Observe(metrics.SinceInSeconds(startPriorityEvalTime))
```

## 5.4. selectHost

`scheduler`在最后会从`priorityList`中选择分数最高的一个节点。

```go
trace.Step("Selecting host")
return g.selectHost(priorityList)
```

`selectHost`获取优先级的节点列表，然后从分数最高的节点以循环方式选择一个节点。

具体代码如下：

```go
// selectHost takes a prioritized list of nodes and then picks one
// in a round-robin manner from the nodes that had the highest score.
func (g *genericScheduler) selectHost(priorityList schedulerapi.HostPriorityList) (string, error) {
	if len(priorityList) == 0 {
		return "", fmt.Errorf("empty priorityList")
	}

	maxScores := findMaxScores(priorityList)
	ix := int(g.lastNodeIndex % uint64(len(maxScores)))
	g.lastNodeIndex++

	return priorityList[maxScores[ix]].Host, nil
}
```

### 5.4.1. findMaxScores

`findMaxScores`返回`priorityList`中具有最高`Score`的节点的索引。

```go
// findMaxScores returns the indexes of nodes in the "priorityList" that has the highest "Score".
func findMaxScores(priorityList schedulerapi.HostPriorityList) []int {
	maxScoreIndexes := make([]int, 0, len(priorityList)/2)
	maxScore := priorityList[0].Score
	for i, hp := range priorityList {
		if hp.Score > maxScore {
			maxScore = hp.Score
			maxScoreIndexes = maxScoreIndexes[:0]
			maxScoreIndexes = append(maxScoreIndexes, i)
		} else if hp.Score == maxScore {
			maxScoreIndexes = append(maxScoreIndexes, i)
		}
	}
	return maxScoreIndexes
}
```

# 6. Scheduler.preempt

如果pod在预选和优选调度中失败，则执行抢占操作。抢占主要是将低优先级的pod的资源空间腾出给待调度的高优先级的pod。

> 具体`Scheduler.preempt`的实现逻辑待后续文章独立分析。

```go
suggestedHost, err := sched.schedule(pod)
if err != nil {
	// schedule() may have failed because the pod would not fit on any host, so we try to
	// preempt, with the expectation that the next time the pod is tried for scheduling it
	// will fit due to the preemption. It is also possible that a different pod will schedule
	// into the resources that were preempted, but this is harmless.
	if fitError, ok := err.(*core.FitError); ok {
		preemptionStartTime := time.Now()
		sched.preempt(pod, fitError)
		metrics.PreemptionAttempts.Inc()
		metrics.SchedulingAlgorithmPremptionEvaluationDuration.Observe(metrics.SinceInMicroseconds(preemptionStartTime))
		metrics.SchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
	}
	return
}
```

# 7. Scheduler.assume

将该pod和选定的节点进行假性绑定，存入scheduler cache中，方便可以继续执行调度逻辑，而不需要等待绑定操作的发生，具体绑定操作可以异步进行。

```go
// Tell the cache to assume that a pod now is running on a given node, even though it hasn't been bound yet.
// This allows us to keep scheduling without waiting on binding to occur.
assumedPod := pod.DeepCopy()

// Assume volumes first before assuming the pod.
//
// If all volumes are completely bound, then allBound is true and binding will be skipped.
//
// Otherwise, binding of volumes is started after the pod is assumed, but before pod binding.
//
// This function modifies 'assumedPod' if volume binding is required.
allBound, err := sched.assumeVolumes(assumedPod, suggestedHost)
if err != nil {
	return
}

// assume modifies `assumedPod` by setting NodeName=suggestedHost
err = sched.assume(assumedPod, suggestedHost)
if err != nil {
	return
}
```

如果假性绑定成功则发送请求给apiserver，如果失败则scheduler会立即释放已分配给假性绑定的pod的资源。

assume方法的具体实现：

```go
// assume signals to the cache that a pod is already in the cache, so that binding can be asynchronous.
// assume modifies `assumed`.
func (sched *Scheduler) assume(assumed *v1.Pod, host string) error {
	// Optimistically assume that the binding will succeed and send it to apiserver
	// in the background.
	// If the binding fails, scheduler will release resources allocated to assumed pod
	// immediately.
	assumed.Spec.NodeName = host
	// NOTE: Because the scheduler uses snapshots of SchedulerCache and the live
	// version of Ecache, updates must be written to SchedulerCache before
	// invalidating Ecache.
	if err := sched.config.SchedulerCache.AssumePod(assumed); err != nil {
		glog.Errorf("scheduler cache AssumePod failed: %v", err)

		// This is most probably result of a BUG in retrying logic.
		// We report an error here so that pod scheduling can be retried.
		// This relies on the fact that Error will check if the pod has been bound
		// to a node and if so will not add it back to the unscheduled pods queue
		// (otherwise this would cause an infinite loop).
		sched.config.Error(assumed, err)
		sched.config.Recorder.Eventf(assumed, v1.EventTypeWarning, "FailedScheduling", "AssumePod failed: %v", err)
		sched.config.PodConditionUpdater.Update(assumed, &v1.PodCondition{
			Type:    v1.PodScheduled,
			Status:  v1.ConditionFalse,
			Reason:  "SchedulerError",
			Message: err.Error(),
		})
		return err
	}

	// Optimistically assume that the binding will succeed, so we need to invalidate affected
	// predicates in equivalence cache.
	// If the binding fails, these invalidated item will not break anything.
	if sched.config.Ecache != nil {
		sched.config.Ecache.InvalidateCachedPredicateItemForPodAdd(assumed, host)
	}
	return nil
}
```

# 8. Scheduler.bind

异步的方式给pod绑定到具体的调度节点上。

```go
// bind the pod to its host asynchronously (we can do this b/c of the assumption step above).
go func() {
	// Bind volumes first before Pod
	if !allBound {
		err = sched.bindVolumes(assumedPod)
		if err != nil {
			return
		}
	}
	err := sched.bind(assumedPod, &v1.Binding{
		ObjectMeta: metav1.ObjectMeta{Namespace: assumedPod.Namespace, Name: assumedPod.Name, UID: assumedPod.UID},
		Target: v1.ObjectReference{
			Kind: "Node",
			Name: suggestedHost,
		},
	})
	metrics.E2eSchedulingLatency.Observe(metrics.SinceInMicroseconds(start))
	if err != nil {
		glog.Errorf("Internal error binding pod: (%v)", err)
	}
}()
```

bind具体实现如下：

```go
// bind binds a pod to a given node defined in a binding object.  We expect this to run asynchronously, so we
// handle binding metrics internally.
func (sched *Scheduler) bind(assumed *v1.Pod, b *v1.Binding) error {
	bindingStart := time.Now()
	// If binding succeeded then PodScheduled condition will be updated in apiserver so that
	// it's atomic with setting host.
	err := sched.config.GetBinder(assumed).Bind(b)
	if err := sched.config.SchedulerCache.FinishBinding(assumed); err != nil {
		glog.Errorf("scheduler cache FinishBinding failed: %v", err)
	}
	if err != nil {
		glog.V(1).Infof("Failed to bind pod: %v/%v", assumed.Namespace, assumed.Name)
		if err := sched.config.SchedulerCache.ForgetPod(assumed); err != nil {
			glog.Errorf("scheduler cache ForgetPod failed: %v", err)
		}
		sched.config.Error(assumed, err)
		sched.config.Recorder.Eventf(assumed, v1.EventTypeWarning, "FailedScheduling", "Binding rejected: %v", err)
		sched.config.PodConditionUpdater.Update(assumed, &v1.PodCondition{
			Type:   v1.PodScheduled,
			Status: v1.ConditionFalse,
			Reason: "BindingRejected",
		})
		return err
	}

	metrics.BindingLatency.Observe(metrics.SinceInMicroseconds(bindingStart))
	metrics.SchedulingLatency.WithLabelValues(metrics.Binding).Observe(metrics.SinceInSeconds(bindingStart))
	sched.config.Recorder.Eventf(assumed, v1.EventTypeNormal, "Scheduled", "Successfully assigned %v/%v to %v", assumed.Namespace, assumed.Name, b.Target.Name)
	return nil
}
```

# 9. 总结

本文主要分析了单个pod的调度过程。具体流程如下：

1. 通过podQueue的待调度队列中弹出需要调度的pod。
2. 通过具体的调度算法为该pod选出合适的节点，其中调度算法就包括预选和优选两步策略。
3. 如果上述调度失败，则会尝试抢占机制，将优先级低的pod剔除，让优先级高的pod调度成功。
4. 将该pod和选定的节点进行假性绑定，存入scheduler cache中，方便具体绑定操作可以异步进行。
5. 实际执行绑定操作，将node的名字添加到pod的节点相关属性中。



其中核心的部分为通过具体的调度算法选出调度节点的过程，即`genericScheduler.Schedule`的实现部分。该部分包括预选和优选两个部分。

`genericScheduler.Schedule`调度的基本流程如下：

1. 对pod做基本性检查，目前主要是对pvc的检查。
2. 通过`findNodesThatFit`预选策略选出满足调度条件的node列表。
3. 通过`PrioritizeNodes`优选策略给预选的node列表中的node进行打分。
4. 在打分的node列表中选择一个分数最高的node作为调度的节点。



参考：

- https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/scheduler.go
- https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go
