# kube-scheduler源码分析（六）之 preempt

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析调度中的抢占逻辑，当pod不适合任何节点的时候，可能pod会调度失败，这时候可能会发生抢占。抢占逻辑的具体实现函数为`Scheduler.preempt`。

# 1. 调用入口

当pod不适合任何节点的时候，可能pod会调度失败。这时候可能会发生抢占。

`scheduleOne`函数中关于抢占调用的逻辑如下：

> 此部分的代码位于/pkg/scheduler/scheduler.go

```go
// scheduleOne does the entire scheduling workflow for a single pod.  It is serialized on the scheduling algorithm's host fitting.
func (sched *Scheduler) scheduleOne() {
	...
	suggestedHost, err := sched.schedule(pod)
	if err != nil {
		// schedule() may have failed because the pod would not fit on any host, so we try to
		// preempt, with the expectation that the next time the pod is tried for scheduling it
		// will fit due to the preemption. It is also possible that a different pod will schedule
		// into the resources that were preempted, but this is harmless.
		if fitError, ok := err.(*core.FitError); ok {
			preemptionStartTime := time.Now()
      // 执行抢占逻辑
			sched.preempt(pod, fitError)
			metrics.PreemptionAttempts.Inc()
			metrics.SchedulingAlgorithmPremptionEvaluationDuration.Observe(metrics.SinceInMicroseconds(preemptionStartTime))
			metrics.SchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
		}
		return
	}
  ...
}  
```

其中核心代码为：

```go
// 基于sched.schedule(pod)返回的err和当前待调度的pod执行抢占策略
sched.preempt(pod, fitError)
```

# 2. Scheduler.preempt

当pod调度失败的时候，会抢占低优先级pod的空间来给高优先级的pod。其中入参为调度失败的pod对象和调度失败的err。

**抢占的基本流程如下：**

1. 判断是否有关闭抢占机制，如果关闭抢占机制则直接返回。
2. 获取调度失败pod的最新对象数据。
3. 执行抢占算法`Algorithm.Preempt`，返回预调度节点和需要被剔除的pod列表。
4. 将抢占算法返回的node添加到pod的`Status.NominatedNodeName`中，并删除需要被剔除的pod。
5. 当抢占算法返回的node是nil的时候，清除pod的`Status.NominatedNodeName`信息。

整个抢占流程的最终结果实际上是更新`Pod.Status.NominatedNodeName`属性的信息。如果抢占算法返回的节点不为空，则将该node更新到`Pod.Status.NominatedNodeName`中，否则就将`Pod.Status.NominatedNodeName`设置为空。

## 2.1. preempt

preempt的具体实现函数：

> 此部分的代码位于/pkg/scheduler/scheduler.go

```go
// preempt tries to create room for a pod that has failed to schedule, by preempting lower priority pods if possible.
// If it succeeds, it adds the name of the node where preemption has happened to the pod annotations.
// It returns the node name and an error if any.
func (sched *Scheduler) preempt(preemptor *v1.Pod, scheduleErr error) (string, error) {
	if !util.PodPriorityEnabled() || sched.config.DisablePreemption {
		glog.V(3).Infof("Pod priority feature is not enabled or preemption is disabled by scheduler configuration." +
			" No preemption is performed.")
		return "", nil
	}
	preemptor, err := sched.config.PodPreemptor.GetUpdatedPod(preemptor)
	if err != nil {
		glog.Errorf("Error getting the updated preemptor pod object: %v", err)
		return "", err
	}

	node, victims, nominatedPodsToClear, err := sched.config.Algorithm.Preempt(preemptor, sched.config.NodeLister, scheduleErr)
	metrics.PreemptionVictims.Set(float64(len(victims)))
	if err != nil {
		glog.Errorf("Error preempting victims to make room for %v/%v.", preemptor.Namespace, preemptor.Name)
		return "", err
	}
	var nodeName = ""
	if node != nil {
		nodeName = node.Name
		err = sched.config.PodPreemptor.SetNominatedNodeName(preemptor, nodeName)
		if err != nil {
			glog.Errorf("Error in preemption process. Cannot update pod %v/%v annotations: %v", preemptor.Namespace, preemptor.Name, err)
			return "", err
		}
		for _, victim := range victims {
			if err := sched.config.PodPreemptor.DeletePod(victim); err != nil {
				glog.Errorf("Error preempting pod %v/%v: %v", victim.Namespace, victim.Name, err)
				return "", err
			}
			sched.config.Recorder.Eventf(victim, v1.EventTypeNormal, "Preempted", "by %v/%v on node %v", preemptor.Namespace, preemptor.Name, nodeName)
		}
	}
	// Clearing nominated pods should happen outside of "if node != nil". Node could
	// be nil when a pod with nominated node name is eligible to preempt again,
	// but preemption logic does not find any node for it. In that case Preempt()
	// function of generic_scheduler.go returns the pod itself for removal of the annotation.
	for _, p := range nominatedPodsToClear {
		rErr := sched.config.PodPreemptor.RemoveNominatedNodeName(p)
		if rErr != nil {
			glog.Errorf("Cannot remove nominated node annotation of pod: %v", rErr)
			// We do not return as this error is not critical.
		}
	}
	return nodeName, err
}
```

以下对`preempt`的实现分段分析。

如果设置关闭抢占机制，则直接返回。

```go
if !util.PodPriorityEnabled() || sched.config.DisablePreemption {
	glog.V(3).Infof("Pod priority feature is not enabled or preemption is disabled by scheduler configuration." +
		" No preemption is performed.")
	return "", nil
}
```

获取当前pod的最新状态。

```go
preemptor, err := sched.config.PodPreemptor.GetUpdatedPod(preemptor)
if err != nil {
	glog.Errorf("Error getting the updated preemptor pod object: %v", err)
	return "", err
}
```

`GetUpdatedPod`的实现就是去拿pod的对象。

```go
func (p *podPreemptor) GetUpdatedPod(pod *v1.Pod) (*v1.Pod, error) {
	return p.Client.CoreV1().Pods(pod.Namespace).Get(pod.Name, metav1.GetOptions{})
}
```

接着执行抢占的算法。抢占的算法返回预调度节点的信息和因抢占被剔除的pod的信息。具体的抢占算法逻辑下文分析。

```go
node, victims, nominatedPodsToClear, err := sched.config.Algorithm.Preempt(preemptor, sched.config.NodeLister, scheduleErr)
```

将预调度节点的信息更新到pod的`Status.NominatedNodeName`属性中。

```go
err = sched.config.PodPreemptor.SetNominatedNodeName(preemptor, nodeName)
```

`SetNominatedNodeName`的具体实现为：

```go
func (p *podPreemptor) SetNominatedNodeName(pod *v1.Pod, nominatedNodeName string) error {
	podCopy := pod.DeepCopy()
	podCopy.Status.NominatedNodeName = nominatedNodeName
	_, err := p.Client.CoreV1().Pods(pod.Namespace).UpdateStatus(podCopy)
	return err
}
```

接着删除因抢占而需要被剔除的pod。

```go
err := sched.config.PodPreemptor.DeletePod(victim)
```

`PodPreemptor.DeletePod`的具体实现就是删除具体的pod。

```go
func (p *podPreemptor) DeletePod(pod *v1.Pod) error {
	return p.Client.CoreV1().Pods(pod.Namespace).Delete(pod.Name, &metav1.DeleteOptions{})
}
```

如果抢占算法得出的node对象为nil，则将pod的`Status.NominatedNodeName`属性设置为空。

```go
// Clearing nominated pods should happen outside of "if node != nil". Node could
// be nil when a pod with nominated node name is eligible to preempt again,
// but preemption logic does not find any node for it. In that case Preempt()
// function of generic_scheduler.go returns the pod itself for removal of the annotation.
for _, p := range nominatedPodsToClear {
	rErr := sched.config.PodPreemptor.RemoveNominatedNodeName(p)
	if rErr != nil {
		glog.Errorf("Cannot remove nominated node annotation of pod: %v", rErr)
		// We do not return as this error is not critical.
	}
}
```

`RemoveNominatedNodeName`的具体实现如下：

```go
func (p *podPreemptor) RemoveNominatedNodeName(pod *v1.Pod) error {
	if len(pod.Status.NominatedNodeName) == 0 {
		return nil
	}
	return p.SetNominatedNodeName(pod, "")
}
```

## 2.2. NominatedNodeName

`Pod.Status.NominatedNodeName`的说明：

`nominatedNodeName`是调度失败的pod抢占别的pod的时候，被抢占pod的运行节点。但在剔除被抢占pod之前该调度失败的pod不会被调度。同时也不保证最终该pod一定会调度到`nominatedNodeName`的机器上，也可能因为之后资源充足等原因调度到其他节点上。最终该pod会被加到调度的队列中。

其中加入到调度队列的具体过程如下：

```go
func NewConfigFactory(args *ConfigFactoryArgs) scheduler.Configurator {
  ...
  	// unscheduled pod queue
	args.PodInformer.Informer().AddEventHandler(
			...
			Handler: cache.ResourceEventHandlerFuncs{
				AddFunc:    c.addPodToSchedulingQueue,
				UpdateFunc: c.updatePodInSchedulingQueue,
				DeleteFunc: c.deletePodFromSchedulingQueue,
			},
		},
	)
  ...
}  
```

**addPodToSchedulingQueue:**

```go
func (c *configFactory) addPodToSchedulingQueue(obj interface{}) {
	if err := c.podQueue.Add(obj.(*v1.Pod)); err != nil {
		runtime.HandleError(fmt.Errorf("unable to queue %T: %v", obj, err))
	}
}
```

**PriorityQueue.Add:**

```go
// Add adds a pod to the active queue. It should be called only when a new pod
// is added so there is no chance the pod is already in either queue.
func (p *PriorityQueue) Add(pod *v1.Pod) error {
	p.lock.Lock()
	defer p.lock.Unlock()
	err := p.activeQ.Add(pod)
	if err != nil {
		glog.Errorf("Error adding pod %v/%v to the scheduling queue: %v", pod.Namespace, pod.Name, err)
	} else {
		if p.unschedulableQ.get(pod) != nil {
			glog.Errorf("Error: pod %v/%v is already in the unschedulable queue.", pod.Namespace, pod.Name)
			p.deleteNominatedPodIfExists(pod)
			p.unschedulableQ.delete(pod)
		}
		p.addNominatedPodIfNeeded(pod)
		p.cond.Broadcast()
	}
	return err
}
```

**addNominatedPodIfNeeded:**

```go
// addNominatedPodIfNeeded adds a pod to nominatedPods if it has a NominatedNodeName and it does not
// already exist in the map. Adding an existing pod is not going to update the pod.
func (p *PriorityQueue) addNominatedPodIfNeeded(pod *v1.Pod) {
	nnn := NominatedNodeName(pod)
	if len(nnn) > 0 {
		for _, np := range p.nominatedPods[nnn] {
			if np.UID == pod.UID {
				glog.Errorf("Pod %v/%v already exists in the nominated map!", pod.Namespace, pod.Name)
				return
			}
		}
		p.nominatedPods[nnn] = append(p.nominatedPods[nnn], pod)
	}
}
```

**NominatedNodeName:**

```go
// NominatedNodeName returns nominated node name of a Pod.
func NominatedNodeName(pod *v1.Pod) string {
	return pod.Status.NominatedNodeName
}
```

# 3. genericScheduler.Preempt

抢占算法依然是在`ScheduleAlgorithm`接口中定义。

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

`Preempt`的具体实现为`genericScheduler`结构体。

`Preempt`的主要实现是找到可以调度的节点和上面因抢占而需要被剔除的pod。

**基本流程如下：**

1. 根据调度失败的原因对所有节点先进行一批筛选，筛选出潜在的被调度节点列表。
2. 通过`selectNodesForPreemption`筛选出需要牺牲的pod和其节点。
3. 基于拓展抢占逻辑再次对上述筛选出来的牺牲者做过滤。
4. 基于上述的过滤结果，选择一个最终可能因抢占被调度的节点。
5. 基于上述的候选节点，找出该节点上优先级低于当前被调度pod的牺牲者pod列表。

完整代码如下：

> 此部分代码位于pkg/scheduler/core/generic_scheduler.go

```go
// preempt finds nodes with pods that can be preempted to make room for "pod" to
// schedule. It chooses one of the nodes and preempts the pods on the node and
// returns 1) the node, 2) the list of preempted pods if such a node is found,
// 3) A list of pods whose nominated node name should be cleared, and 4) any
// possible error.
func (g *genericScheduler) Preempt(pod *v1.Pod, nodeLister algorithm.NodeLister, scheduleErr error) (*v1.Node, []*v1.Pod, []*v1.Pod, error) {
	// Scheduler may return various types of errors. Consider preemption only if
	// the error is of type FitError.
	fitError, ok := scheduleErr.(*FitError)
	if !ok || fitError == nil {
		return nil, nil, nil, nil
	}
	err := g.cache.UpdateNodeNameToInfoMap(g.cachedNodeInfoMap)
	if err != nil {
		return nil, nil, nil, err
	}
	if !podEligibleToPreemptOthers(pod, g.cachedNodeInfoMap) {
		glog.V(5).Infof("Pod %v/%v is not eligible for more preemption.", pod.Namespace, pod.Name)
		return nil, nil, nil, nil
	}
	allNodes, err := nodeLister.List()
	if err != nil {
		return nil, nil, nil, err
	}
	if len(allNodes) == 0 {
		return nil, nil, nil, ErrNoNodesAvailable
	}
	potentialNodes := nodesWherePreemptionMightHelp(allNodes, fitError.FailedPredicates)
	if len(potentialNodes) == 0 {
		glog.V(3).Infof("Preemption will not help schedule pod %v/%v on any node.", pod.Namespace, pod.Name)
		// In this case, we should clean-up any existing nominated node name of the pod.
		return nil, nil, []*v1.Pod{pod}, nil
	}
	pdbs, err := g.cache.ListPDBs(labels.Everything())
	if err != nil {
		return nil, nil, nil, err
	}
  // 找出可能被抢占的节点
	nodeToVictims, err := selectNodesForPreemption(pod, g.cachedNodeInfoMap, potentialNodes, g.predicates,
		g.predicateMetaProducer, g.schedulingQueue, pdbs)
	if err != nil {
		return nil, nil, nil, err
	}

	// We will only check nodeToVictims with extenders that support preemption.
	// Extenders which do not support preemption may later prevent preemptor from being scheduled on the nominated
	// node. In that case, scheduler will find a different host for the preemptor in subsequent scheduling cycles.
	nodeToVictims, err = g.processPreemptionWithExtenders(pod, nodeToVictims)
	if err != nil {
		return nil, nil, nil, err
	}
	// 选出最终被抢占的节点
	candidateNode := pickOneNodeForPreemption(nodeToVictims)
	if candidateNode == nil {
		return nil, nil, nil, err
	}

	// Lower priority pods nominated to run on this node, may no longer fit on
	// this node. So, we should remove their nomination. Removing their
	// nomination updates these pods and moves them to the active queue. It
	// lets scheduler find another place for them.
  // 找出被强占节点上牺牲者pod列表
	nominatedPods := g.getLowerPriorityNominatedPods(pod, candidateNode.Name)
	if nodeInfo, ok := g.cachedNodeInfoMap[candidateNode.Name]; ok {
		return nodeInfo.Node(), nodeToVictims[candidateNode].Pods, nominatedPods, err
	}

	return nil, nil, nil, fmt.Errorf(
		"preemption failed: the target node %s has been deleted from scheduler cache",
		candidateNode.Name)
}
```

---

以下对`genericScheduler.Preempt`分段进行分析。

## 3.1. selectNodesForPreemption

`selectNodesForPreemption`并行地所有节点中找可能被抢占的节点。

```go
nodeToVictims, err := selectNodesForPreemption(pod, g.cachedNodeInfoMap, potentialNodes, g.predicates,g.predicateMetaProducer, g.schedulingQueue, pdbs)
```

`selectNodesForPreemption`主要基于`selectVictimsOnNode`构造一个checkNode的函数，然后并发执行该函数。

`selectNodesForPreemption`具体实现如下：

```go
// selectNodesForPreemption finds all the nodes with possible victims for
// preemption in parallel.
func selectNodesForPreemption(pod *v1.Pod,
	nodeNameToInfo map[string]*schedulercache.NodeInfo,
	potentialNodes []*v1.Node,
	predicates map[string]algorithm.FitPredicate,
	metadataProducer algorithm.PredicateMetadataProducer,
	queue SchedulingQueue,
	pdbs []*policy.PodDisruptionBudget,
) (map[*v1.Node]*schedulerapi.Victims, error) {

	nodeToVictims := map[*v1.Node]*schedulerapi.Victims{}
	var resultLock sync.Mutex

	// We can use the same metadata producer for all nodes.
	meta := metadataProducer(pod, nodeNameToInfo)
	checkNode := func(i int) {
		nodeName := potentialNodes[i].Name
		var metaCopy algorithm.PredicateMetadata
		if meta != nil {
			metaCopy = meta.ShallowCopy()
		}
		pods, numPDBViolations, fits := selectVictimsOnNode(pod, metaCopy, nodeNameToInfo[nodeName], predicates, queue, pdbs)
		if fits {
			resultLock.Lock()
			victims := schedulerapi.Victims{
				Pods:             pods,
				NumPDBViolations: numPDBViolations,
			}
			nodeToVictims[potentialNodes[i]] = &victims
			resultLock.Unlock()
		}
	}
	workqueue.Parallelize(16, len(potentialNodes), checkNode)
	return nodeToVictims, nil
}
```

### 3.1.1. selectVictimsOnNode

`selectVictimsOnNode`找到应该被抢占的给定节点上的最小pod集合，以便给调度失败的pod安排足够的空间。该函数最终返回的是一个pod的数组。当有更低优先级的pod可能被选择的时候，较高优先级的pod不会被选入该待剔除的pod集合。

**基本流程如下：**

1. 先检查当该节点上所有低于预被调度pod优先级的pod移除后，该pod能否被调度到当前节点上。
2. 如果上述检查可以，则将该节点的所有低优先级pod按照优先级来排序。

```go
// selectVictimsOnNode finds minimum set of pods on the given node that should
// be preempted in order to make enough room for "pod" to be scheduled. The
// minimum set selected is subject to the constraint that a higher-priority pod
// is never preempted when a lower-priority pod could be (higher/lower relative
// to one another, not relative to the preemptor "pod").
// The algorithm first checks if the pod can be scheduled on the node when all the
// lower priority pods are gone. If so, it sorts all the lower priority pods by
// their priority and then puts them into two groups of those whose PodDisruptionBudget
// will be violated if preempted and other non-violating pods. Both groups are
// sorted by priority. It first tries to reprieve as many PDB violating pods as
// possible and then does them same for non-PDB-violating pods while checking
// that the "pod" can still fit on the node.
// NOTE: This function assumes that it is never called if "pod" cannot be scheduled
// due to pod affinity, node affinity, or node anti-affinity reasons. None of
// these predicates can be satisfied by removing more pods from the node.
func selectVictimsOnNode(
	pod *v1.Pod,
	meta algorithm.PredicateMetadata,
	nodeInfo *schedulercache.NodeInfo,
	fitPredicates map[string]algorithm.FitPredicate,
	queue SchedulingQueue,
	pdbs []*policy.PodDisruptionBudget,
) ([]*v1.Pod, int, bool) {
	potentialVictims := util.SortableList{CompFunc: util.HigherPriorityPod}
	nodeInfoCopy := nodeInfo.Clone()

	removePod := func(rp *v1.Pod) {
		nodeInfoCopy.RemovePod(rp)
		if meta != nil {
			meta.RemovePod(rp)
		}
	}
	addPod := func(ap *v1.Pod) {
		nodeInfoCopy.AddPod(ap)
		if meta != nil {
			meta.AddPod(ap, nodeInfoCopy)
		}
	}
	// As the first step, remove all the lower priority pods from the node and
	// check if the given pod can be scheduled.
	podPriority := util.GetPodPriority(pod)
	for _, p := range nodeInfoCopy.Pods() {
		if util.GetPodPriority(p) < podPriority {
			potentialVictims.Items = append(potentialVictims.Items, p)
			removePod(p)
		}
	}
	potentialVictims.Sort()
	// If the new pod does not fit after removing all the lower priority pods,
	// we are almost done and this node is not suitable for preemption. The only condition
	// that we should check is if the "pod" is failing to schedule due to pod affinity
	// failure.
	// TODO(bsalamat): Consider checking affinity to lower priority pods if feasible with reasonable performance.
	if fits, _, err := podFitsOnNode(pod, meta, nodeInfoCopy, fitPredicates, nil, nil, queue, false, nil); !fits {
		if err != nil {
			glog.Warningf("Encountered error while selecting victims on node %v: %v", nodeInfo.Node().Name, err)
		}
		return nil, 0, false
	}
	var victims []*v1.Pod
	numViolatingVictim := 0
	// Try to reprieve as many pods as possible. We first try to reprieve the PDB
	// violating victims and then other non-violating ones. In both cases, we start
	// from the highest priority victims.
	violatingVictims, nonViolatingVictims := filterPodsWithPDBViolation(potentialVictims.Items, pdbs)
	reprievePod := func(p *v1.Pod) bool {
		addPod(p)
		fits, _, _ := podFitsOnNode(pod, meta, nodeInfoCopy, fitPredicates, nil, nil, queue, false, nil)
		if !fits {
			removePod(p)
			victims = append(victims, p)
			glog.V(5).Infof("Pod %v is a potential preemption victim on node %v.", p.Name, nodeInfo.Node().Name)
		}
		return fits
	}
	for _, p := range violatingVictims {
		if !reprievePod(p) {
			numViolatingVictim++
		}
	}
	// Now we try to reprieve non-violating victims.
	for _, p := range nonViolatingVictims {
		reprievePod(p)
	}
	return victims, numViolatingVictim, true
}
```

## 3.2. processPreemptionWithExtenders

`processPreemptionWithExtenders`基于`selectNodesForPreemption`选出的牺牲者进行扩展的抢占逻辑继续筛选牺牲者。

```go
// We will only check nodeToVictims with extenders that support preemption.
// Extenders which do not support preemption may later prevent preemptor from being scheduled on the nominated
// node. In that case, scheduler will find a different host for the preemptor in subsequent scheduling cycles.
nodeToVictims, err = g.processPreemptionWithExtenders(pod, nodeToVictims)
if err != nil {
	return nil, nil, nil, err
}
```

`processPreemptionWithExtenders`完整代码如下：

```go
// processPreemptionWithExtenders processes preemption with extenders
func (g *genericScheduler) processPreemptionWithExtenders(
	pod *v1.Pod,
	nodeToVictims map[*v1.Node]*schedulerapi.Victims,
) (map[*v1.Node]*schedulerapi.Victims, error) {
	if len(nodeToVictims) > 0 {
		for _, extender := range g.extenders {
			if extender.SupportsPreemption() && extender.IsInterested(pod) {
				newNodeToVictims, err := extender.ProcessPreemption(
					pod,
					nodeToVictims,
					g.cachedNodeInfoMap,
				)
				if err != nil {
					if extender.IsIgnorable() {
						glog.Warningf("Skipping extender %v as it returned error %v and has ignorable flag set",
							extender, err)
						continue
					}
					return nil, err
				}

				// Replace nodeToVictims with new result after preemption. So the
				// rest of extenders can continue use it as parameter.
				nodeToVictims = newNodeToVictims

				// If node list becomes empty, no preemption can happen regardless of other extenders.
				if len(nodeToVictims) == 0 {
					break
				}
			}
		}
	}

	return nodeToVictims, nil
}
```

## 3.3. pickOneNodeForPreemption

`pickOneNodeForPreemption`从筛选出的node中再挑选一个节点作为最终调度节点。

```go
candidateNode := pickOneNodeForPreemption(nodeToVictims)
if candidateNode == nil {
	return nil, nil, nil, err
}
```

`pickOneNodeForPreemption`完整代码如下：

```go
// pickOneNodeForPreemption chooses one node among the given nodes. It assumes
// pods in each map entry are ordered by decreasing priority.
// It picks a node based on the following criteria:
// 1. A node with minimum number of PDB violations.
// 2. A node with minimum highest priority victim is picked.
// 3. Ties are broken by sum of priorities of all victims.
// 4. If there are still ties, node with the minimum number of victims is picked.
// 5. If there are still ties, the first such node is picked (sort of randomly).
// The 'minNodes1' and 'minNodes2' are being reused here to save the memory
// allocation and garbage collection time.
func pickOneNodeForPreemption(nodesToVictims map[*v1.Node]*schedulerapi.Victims) *v1.Node {
	if len(nodesToVictims) == 0 {
		return nil
	}
	minNumPDBViolatingPods := math.MaxInt32
	var minNodes1 []*v1.Node
	lenNodes1 := 0
	for node, victims := range nodesToVictims {
		if len(victims.Pods) == 0 {
			// We found a node that doesn't need any preemption. Return it!
			// This should happen rarely when one or more pods are terminated between
			// the time that scheduler tries to schedule the pod and the time that
			// preemption logic tries to find nodes for preemption.
			return node
		}
		numPDBViolatingPods := victims.NumPDBViolations
		if numPDBViolatingPods < minNumPDBViolatingPods {
			minNumPDBViolatingPods = numPDBViolatingPods
			minNodes1 = nil
			lenNodes1 = 0
		}
		if numPDBViolatingPods == minNumPDBViolatingPods {
			minNodes1 = append(minNodes1, node)
			lenNodes1++
		}
	}
	if lenNodes1 == 1 {
		return minNodes1[0]
	}

	// There are more than one node with minimum number PDB violating pods. Find
	// the one with minimum highest priority victim.
	minHighestPriority := int32(math.MaxInt32)
	var minNodes2 = make([]*v1.Node, lenNodes1)
	lenNodes2 := 0
	for i := 0; i < lenNodes1; i++ {
		node := minNodes1[i]
		victims := nodesToVictims[node]
		// highestPodPriority is the highest priority among the victims on this node.
		highestPodPriority := util.GetPodPriority(victims.Pods[0])
		if highestPodPriority < minHighestPriority {
			minHighestPriority = highestPodPriority
			lenNodes2 = 0
		}
		if highestPodPriority == minHighestPriority {
			minNodes2[lenNodes2] = node
			lenNodes2++
		}
	}
	if lenNodes2 == 1 {
		return minNodes2[0]
	}

	// There are a few nodes with minimum highest priority victim. Find the
	// smallest sum of priorities.
	minSumPriorities := int64(math.MaxInt64)
	lenNodes1 = 0
	for i := 0; i < lenNodes2; i++ {
		var sumPriorities int64
		node := minNodes2[i]
		for _, pod := range nodesToVictims[node].Pods {
			// We add MaxInt32+1 to all priorities to make all of them >= 0. This is
			// needed so that a node with a few pods with negative priority is not
			// picked over a node with a smaller number of pods with the same negative
			// priority (and similar scenarios).
			sumPriorities += int64(util.GetPodPriority(pod)) + int64(math.MaxInt32+1)
		}
		if sumPriorities < minSumPriorities {
			minSumPriorities = sumPriorities
			lenNodes1 = 0
		}
		if sumPriorities == minSumPriorities {
			minNodes1[lenNodes1] = node
			lenNodes1++
		}
	}
	if lenNodes1 == 1 {
		return minNodes1[0]
	}

	// There are a few nodes with minimum highest priority victim and sum of priorities.
	// Find one with the minimum number of pods.
	minNumPods := math.MaxInt32
	lenNodes2 = 0
	for i := 0; i < lenNodes1; i++ {
		node := minNodes1[i]
		numPods := len(nodesToVictims[node].Pods)
		if numPods < minNumPods {
			minNumPods = numPods
			lenNodes2 = 0
		}
		if numPods == minNumPods {
			minNodes2[lenNodes2] = node
			lenNodes2++
		}
	}
	// At this point, even if there are more than one node with the same score,
	// return the first one.
	if lenNodes2 > 0 {
		return minNodes2[0]
	}
	glog.Errorf("Error in logic of node scoring for preemption. We should never reach here!")
	return nil
}
```

## 3.4. getLowerPriorityNominatedPods

`getLowerPriorityNominatedPods`的基本流程如下：

1. 获取候选节点上的pod列表。
2. 获取待调度pod的优先级值。
3. 遍历该节点的pod列表，如果低于待调度pod的优先级则放入低优先级pod列表中。

genericScheduler.Preempt中相关代码如下：

```go
// Lower priority pods nominated to run on this node, may no longer fit on
// this node. So, we should remove their nomination. Removing their
// nomination updates these pods and moves them to the active queue. It
// lets scheduler find another place for them.
nominatedPods := g.getLowerPriorityNominatedPods(pod, candidateNode.Name)
if nodeInfo, ok := g.cachedNodeInfoMap[candidateNode.Name]; ok {
	return nodeInfo.Node(), nodeToVictims[candidateNode].Pods, nominatedPods, err
}
```

`getLowerPriorityNominatedPods`代码如下：

> 此部分代码位于pkg/scheduler/core/generic_scheduler.go

```go
// getLowerPriorityNominatedPods returns pods whose priority is smaller than the
// priority of the given "pod" and are nominated to run on the given node.
// Note: We could possibly check if the nominated lower priority pods still fit
// and return those that no longer fit, but that would require lots of
// manipulation of NodeInfo and PredicateMeta per nominated pod. It may not be
// worth the complexity, especially because we generally expect to have a very
// small number of nominated pods per node.
func (g *genericScheduler) getLowerPriorityNominatedPods(pod *v1.Pod, nodeName string) []*v1.Pod {
	pods := g.schedulingQueue.WaitingPodsForNode(nodeName)

	if len(pods) == 0 {
		return nil
	}

	var lowerPriorityPods []*v1.Pod
	podPriority := util.GetPodPriority(pod)
	for _, p := range pods {
		if util.GetPodPriority(p) < podPriority {
			lowerPriorityPods = append(lowerPriorityPods, p)
		}
	}
	return lowerPriorityPods
}
```

# 4. 总结

## 4.1. Scheduler.preempt

当pod调度失败的时候，会抢占低优先级pod的空间来给高优先级的pod。其中入参为调度失败的pod对象和调度失败的err。

**抢占的基本流程如下：**

1. 判断是否有关闭抢占机制，如果关闭抢占机制则直接返回。
2. 获取调度失败pod的最新对象数据。
3. 执行抢占算法`Algorithm.Preempt`，返回预调度节点和需要被剔除的pod列表。
4. 将抢占算法返回的node添加到pod的`Status.NominatedNodeName`中，并删除需要被剔除的pod。
5. 当抢占算法返回的node是nil的时候，清除pod的`Status.NominatedNodeName`信息。

整个抢占流程的最终结果实际上是更新`Pod.Status.NominatedNodeName`属性的信息。如果抢占算法返回的节点不为空，则将该node更新到`Pod.Status.NominatedNodeName`中，否则就将`Pod.Status.NominatedNodeName`设置为空。

## 4.2. genericScheduler.Preempt

`Preempt`的主要实现是找到可以调度的节点和上面因抢占而需要被剔除的pod。

**基本流程如下：**

1. 根据调度失败的原因对所有节点先进行一批筛选，筛选出潜在的被调度节点列表。
2. 通过`selectNodesForPreemption`筛选出需要牺牲的pod和其节点。
3. 基于拓展抢占逻辑再次对上述筛选出来的牺牲者做过滤。
4. 基于上述的过滤结果，选择一个最终可能因抢占被调度的节点。
5. 基于上述的候选节点，找出该节点上优先级低于当前被调度pod的牺牲者pod列表。





参考：

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/scheduler.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go>

