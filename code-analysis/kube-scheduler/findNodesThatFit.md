# kube-scheduler源码分析（四）之 findNodesThatFit

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析调度逻辑中的预选策略，即第一步筛选出符合pod调度条件的节点。

# 1. [调用入口](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go#L117)

预选，通过预选函数来判断每个节点是否适合被该Pod调度。

`genericScheduler.Schedule`中对`findNodesThatFit`的调用过程如下：

> 此部分代码位于pkg/scheduler/core/generic_scheduler.go

```go
func (g *genericScheduler) Schedule(pod *v1.Pod, nodeLister algorithm.NodeLister) (string, error) {
	...
  // 列出所有的节点
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
  // 调用findNodesThatFit过滤出预选节点
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
// metrics
  metrics.SchedulingAlgorithmPredicateEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPredicateEvalTime))
			  metrics.SchedulingLatency.WithLabelValues(metrics.PredicateEvaluation).Observe(metrics.SinceInSeconds(startPredicateEvalTime))
	...
}  
```

核心代码：

```go
// 调用findNodesThatFit过滤出预选节点
filteredNodes, failedPredicateMap, err := g.findNodesThatFit(pod, nodes)
```

# 2. [findNodesThatFit](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go#L365)

`findNodesThatFit`基于给定的预选函数过滤node，每个node传入到预选函数中来确实该节点是否符合要求。

`findNodesThatFit`的入参是被调度的pod和当前的节点列表，返回预选节点列表和错误。

`findNodesThatFit`基本流程如下：

1. 设置可行节点的总数，作为预选节点数组的容量，避免总节点过多需要筛选的节点过多。
2. 通过`NodeTree`不断获取下一个节点来判断该节点是否满足pod的调度条件。
3. 通过之前注册的各种预选函数来判断当前节点是否符合pod的调度条件。
4. 最后返回满足调度条件的node列表，供下一步的优选操作。

`findNodesThatFit`完整代码如下：

> 此部分代码位于pkg/scheduler/core/generic_scheduler.go

```go
// Filters the nodes to find the ones that fit based on the given predicate functions
// Each node is passed through the predicate functions to determine if it is a fit
func (g *genericScheduler) findNodesThatFit(pod *v1.Pod, nodes []*v1.Node) ([]*v1.Node, FailedPredicateMap, error) {
   var filtered []*v1.Node
   failedPredicateMap := FailedPredicateMap{}

   if len(g.predicates) == 0 {
      filtered = nodes
   } else {
      allNodes := int32(g.cache.NodeTree().NumNodes)
      numNodesToFind := g.numFeasibleNodesToFind(allNodes)

      // Create filtered list with enough space to avoid growing it
      // and allow assigning.
      filtered = make([]*v1.Node, numNodesToFind)
      errs := errors.MessageCountMap{}
      var (
         predicateResultLock sync.Mutex
         filteredLen         int32
         equivClass          *equivalence.Class
      )

      ctx, cancel := context.WithCancel(context.Background())

      // We can use the same metadata producer for all nodes.
      meta := g.predicateMetaProducer(pod, g.cachedNodeInfoMap)

      if g.equivalenceCache != nil {
         // getEquivalenceClassInfo will return immediately if no equivalence pod found
         equivClass = equivalence.NewClass(pod)
      }

      checkNode := func(i int) {
         var nodeCache *equivalence.NodeCache
         nodeName := g.cache.NodeTree().Next()
         if g.equivalenceCache != nil {
            nodeCache, _ = g.equivalenceCache.GetNodeCache(nodeName)
         }
         fits, failedPredicates, err := podFitsOnNode(
            pod,
            meta,
            g.cachedNodeInfoMap[nodeName],
            g.predicates,
            g.cache,
            nodeCache,
            g.schedulingQueue,
            g.alwaysCheckAllPredicates,
            equivClass,
         )
         if err != nil {
            predicateResultLock.Lock()
            errs[err.Error()]++
            predicateResultLock.Unlock()
            return
         }
         if fits {
            length := atomic.AddInt32(&filteredLen, 1)
            if length > numNodesToFind {
               cancel()
               atomic.AddInt32(&filteredLen, -1)
            } else {
               filtered[length-1] = g.cachedNodeInfoMap[nodeName].Node()
            }
         } else {
            predicateResultLock.Lock()
            failedPredicateMap[nodeName] = failedPredicates
            predicateResultLock.Unlock()
         }
      }

      // Stops searching for more nodes once the configured number of feasible nodes
      // are found.
      workqueue.ParallelizeUntil(ctx, 16, int(allNodes), checkNode)

      filtered = filtered[:filteredLen]
      if len(errs) > 0 {
         return []*v1.Node{}, FailedPredicateMap{}, errors.CreateAggregateFromMessageCountMap(errs)
      }
   }

   if len(filtered) > 0 && len(g.extenders) != 0 {
      for _, extender := range g.extenders {
         if !extender.IsInterested(pod) {
            continue
         }
         filteredList, failedMap, err := extender.Filter(pod, filtered, g.cachedNodeInfoMap)
         if err != nil {
            if extender.IsIgnorable() {
               glog.Warningf("Skipping extender %v as it returned error %v and has ignorable flag set",
                  extender, err)
               continue
            } else {
               return []*v1.Node{}, FailedPredicateMap{}, err
            }
         }

         for failedNodeName, failedMsg := range failedMap {
            if _, found := failedPredicateMap[failedNodeName]; !found {
               failedPredicateMap[failedNodeName] = []algorithm.PredicateFailureReason{}
            }
            failedPredicateMap[failedNodeName] = append(failedPredicateMap[failedNodeName], predicates.NewFailureReason(failedMsg))
         }
         filtered = filteredList
         if len(filtered) == 0 {
            break
         }
      }
   }
   return filtered, failedPredicateMap, nil
}
```

以下对`findNodesThatFit`分段分析。

# 3. numFeasibleNodesToFind

`findNodesThatFit`先基于所有的节点找出可行的节点是总数。`numFeasibleNodesToFind`的作用主要是避免当节点过多（超过100）影响调度的效率。

```go
allNodes := int32(g.cache.NodeTree().NumNodes)
numNodesToFind := g.numFeasibleNodesToFind(allNodes)

// Create filtered list with enough space to avoid growing it
// and allow assigning.
filtered = make([]*v1.Node, numNodesToFind)
```

`numFeasibleNodesToFind`基本流程如下：

- 如果所有的node节点小于`minFeasibleNodesToFind`(当前默认为100)则返回节点数。
- 如果节点数超100，则取指定计分的百分比的节点数，当该百分比后的数目仍小于`minFeasibleNodesToFind`，则返回`minFeasibleNodesToFind`。
- 如果百分比后的数目大于`minFeasibleNodesToFind`，则返回该百分比。

```go
// numFeasibleNodesToFind returns the number of feasible nodes that once found, the scheduler stops
// its search for more feasible nodes.
func (g *genericScheduler) numFeasibleNodesToFind(numAllNodes int32) int32 {
	if numAllNodes < minFeasibleNodesToFind || g.percentageOfNodesToScore <= 0 ||
		g.percentageOfNodesToScore >= 100 {
		return numAllNodes
	}
	numNodes := numAllNodes * g.percentageOfNodesToScore / 100
	if numNodes < minFeasibleNodesToFind {
		return minFeasibleNodesToFind
	}
	return numNodes
}
```

# 4. checkNode

`checkNode`是一个校验node是否符合要求的函数，其中实际调用到的核心函数是`podFitsOnNode`。再通过`workqueue`并发执行`checkNode`操作。

**`checkNode`主要流程如下：**

1. 通过cache中的nodeTree不断获取下一个node。
2. 将当前node和pod传入`podFitsOnNode`判断当前node是否符合要求。
3. 如果当前node符合要求就将当前node加入预选节点的数组中`filtered`。
4. 如果当前node不满足要求，则加入到失败的数组中，并记录原因。
5. 通过`workqueue.ParallelizeUntil`并发执行`checkNode`函数，一旦找到配置的可行节点数，就停止搜索更多节点。

```go
checkNode := func(i int) {
	var nodeCache *equivalence.NodeCache
	nodeName := g.cache.NodeTree().Next()
	if g.equivalenceCache != nil {
		nodeCache, _ = g.equivalenceCache.GetNodeCache(nodeName)
	}
	fits, failedPredicates, err := podFitsOnNode(
		pod,
		meta,
		g.cachedNodeInfoMap[nodeName],
		g.predicates,
		g.cache,
		nodeCache,
		g.schedulingQueue,
		g.alwaysCheckAllPredicates,
		equivClass,
	)
	if err != nil {
		predicateResultLock.Lock()
		errs[err.Error()]++
		predicateResultLock.Unlock()
		return
	}
	if fits {
		length := atomic.AddInt32(&filteredLen, 1)
		if length > numNodesToFind {
			cancel()
			atomic.AddInt32(&filteredLen, -1)
		} else {
			filtered[length-1] = g.cachedNodeInfoMap[nodeName].Node()
		}
	} else {
		predicateResultLock.Lock()
		failedPredicateMap[nodeName] = failedPredicates
		predicateResultLock.Unlock()
	}
}
```

workqueue的并发操作：

```go
// Stops searching for more nodes once the configured number of feasible nodes
// are found.
workqueue.ParallelizeUntil(ctx, 16, int(allNodes), checkNode)
```

`ParallelizeUntil`具体代码如下：

```go
// ParallelizeUntil is a framework that allows for parallelizing N
// independent pieces of work until done or the context is canceled.
func ParallelizeUntil(ctx context.Context, workers, pieces int, doWorkPiece DoWorkPieceFunc) {
	var stop <-chan struct{}
	if ctx != nil {
		stop = ctx.Done()
	}

	toProcess := make(chan int, pieces)
	for i := 0; i < pieces; i++ {
		toProcess <- i
	}
	close(toProcess)

	if pieces < workers {
		workers = pieces
	}

	wg := sync.WaitGroup{}
	wg.Add(workers)
	for i := 0; i < workers; i++ {
		go func() {
			defer utilruntime.HandleCrash()
			defer wg.Done()
			for piece := range toProcess {
				select {
				case <-stop:
					return
				default:
					doWorkPiece(piece)
				}
			}
		}()
	}
	wg.Wait()
}
```

# 5. podFitsOnNode

`podFitsOnNode`主要内容如下：

- `podFitsOnNode`会检查给定的某个Node是否满足预选的函数。

- 对于给定的pod，`podFitsOnNode`会检查是否有相同的pod存在，尽量复用缓存过的预选结果。

`podFitsOnNode`主要在`Schedule`（调度）和`Preempt`（抢占）的时候被调用。

当在`Schedule`中被调用的时候，主要判断是否可以被调度到当前节点，依据为当前节点上所有已存在的pod及被提名要运行到该节点的具有相等或更高优先级的pod。

当在`Preempt`中被调用的时候，即发生抢占的时候，通过`SelectVictimsOnNode`函数选出需要被移除的pod，移除后然后将预调度的pod调度到该节点上。

**podFitsOnNode基本流程如下：**

1. 遍历之前注册好的预选策略`predicates.Ordering`，并获取预选策略的执行函数。
2. 遍历执行每个预选函数，并返回是否合适，预选失败的原因和错误。
3. 如果预选函数执行的结果不合适，则加入预选失败的数组中。
4. 最后返回预选失败的个数是否为0，和预选失败的原因。

**入参：**

- pod
- PredicateMetadata
- NodeInfo
- predicateFuncs
- schedulercache.Cache
- nodeCache
- SchedulingQueue
- alwaysCheckAllPredicates
- equivClass

**出参：**

- fit
- PredicateFailureReason

完整代码如下：

> 此部分代码位于pkg/scheduler/core/generic_scheduler.go

```go
// podFitsOnNode checks whether a node given by NodeInfo satisfies the given predicate functions.
// For given pod, podFitsOnNode will check if any equivalent pod exists and try to reuse its cached
// predicate results as possible.
// This function is called from two different places: Schedule and Preempt.
// When it is called from Schedule, we want to test whether the pod is schedulable
// on the node with all the existing pods on the node plus higher and equal priority
// pods nominated to run on the node.
// When it is called from Preempt, we should remove the victims of preemption and
// add the nominated pods. Removal of the victims is done by SelectVictimsOnNode().
// It removes victims from meta and NodeInfo before calling this function.
func podFitsOnNode(
	pod *v1.Pod,
	meta algorithm.PredicateMetadata,
	info *schedulercache.NodeInfo,
	predicateFuncs map[string]algorithm.FitPredicate,
	cache schedulercache.Cache,
	nodeCache *equivalence.NodeCache,
	queue SchedulingQueue,
	alwaysCheckAllPredicates bool,
	equivClass *equivalence.Class,
) (bool, []algorithm.PredicateFailureReason, error) {
	var (
		eCacheAvailable  bool
		failedPredicates []algorithm.PredicateFailureReason
	)

	podsAdded := false
	// We run predicates twice in some cases. If the node has greater or equal priority
	// nominated pods, we run them when those pods are added to meta and nodeInfo.
	// If all predicates succeed in this pass, we run them again when these
	// nominated pods are not added. This second pass is necessary because some
	// predicates such as inter-pod affinity may not pass without the nominated pods.
	// If there are no nominated pods for the node or if the first run of the
	// predicates fail, we don't run the second pass.
	// We consider only equal or higher priority pods in the first pass, because
	// those are the current "pod" must yield to them and not take a space opened
	// for running them. It is ok if the current "pod" take resources freed for
	// lower priority pods.
	// Requiring that the new pod is schedulable in both circumstances ensures that
	// we are making a conservative decision: predicates like resources and inter-pod
	// anti-affinity are more likely to fail when the nominated pods are treated
	// as running, while predicates like pod affinity are more likely to fail when
	// the nominated pods are treated as not running. We can't just assume the
	// nominated pods are running because they are not running right now and in fact,
	// they may end up getting scheduled to a different node.
	for i := 0; i < 2; i++ {
		metaToUse := meta
		nodeInfoToUse := info
		if i == 0 {
			podsAdded, metaToUse, nodeInfoToUse = addNominatedPods(util.GetPodPriority(pod), meta, info, queue)
		} else if !podsAdded || len(failedPredicates) != 0 {
			break
		}
		// Bypass eCache if node has any nominated pods.
		// TODO(bsalamat): consider using eCache and adding proper eCache invalidations
		// when pods are nominated or their nominations change.
		eCacheAvailable = equivClass != nil && nodeCache != nil && !podsAdded
		for _, predicateKey := range predicates.Ordering() {
			var (
				fit     bool
				reasons []algorithm.PredicateFailureReason
				err     error
			)
			//TODO (yastij) : compute average predicate restrictiveness to export it as Prometheus metric
			if predicate, exist := predicateFuncs[predicateKey]; exist {
				if eCacheAvailable {
					fit, reasons, err = nodeCache.RunPredicate(predicate, predicateKey, pod, metaToUse, nodeInfoToUse, equivClass, cache)
				} else {
					fit, reasons, err = predicate(pod, metaToUse, nodeInfoToUse)
				}
				if err != nil {
					return false, []algorithm.PredicateFailureReason{}, err
				}

				if !fit {
					// eCache is available and valid, and predicates result is unfit, record the fail reasons
					failedPredicates = append(failedPredicates, reasons...)
					// if alwaysCheckAllPredicates is false, short circuit all predicates when one predicate fails.
					if !alwaysCheckAllPredicates {
						glog.V(5).Infoln("since alwaysCheckAllPredicates has not been set, the predicate " +
							"evaluation is short circuited and there are chances " +
							"of other predicates failing as well.")
						break
					}
				}
			}
		}
	}

	return len(failedPredicates) == 0, failedPredicates, nil
}
```

## 5.1. predicateFuncs

根据之前初注册好的预选策略函数来执行预选，判断节点是否符合调度。

```go
for _, predicateKey := range predicates.Ordering() {
	if predicate, exist := predicateFuncs[predicateKey]; exist {
		if eCacheAvailable {
			fit, reasons, err = nodeCache.RunPredicate(predicate, predicateKey, pod, metaToUse, nodeInfoToUse, equivClass, cache)
		} else {
			fit, reasons, err = predicate(pod, metaToUse, nodeInfoToUse)
		}
```

预选策略如下：

```go
var (
	predicatesOrdering = []string{CheckNodeConditionPred, CheckNodeUnschedulablePred,
		GeneralPred, HostNamePred, PodFitsHostPortsPred,
		MatchNodeSelectorPred, PodFitsResourcesPred, NoDiskConflictPred,
		PodToleratesNodeTaintsPred, PodToleratesNodeNoExecuteTaintsPred, CheckNodeLabelPresencePred,
		CheckServiceAffinityPred, MaxEBSVolumeCountPred, MaxGCEPDVolumeCountPred, MaxCSIVolumeCountPred,
		MaxAzureDiskVolumeCountPred, CheckVolumeBindingPred, NoVolumeZoneConflictPred,
		CheckNodeMemoryPressurePred, CheckNodePIDPressurePred, CheckNodeDiskPressurePred, MatchInterPodAffinityPred}
)
```

# 6. PodFitsResources

以下以`PodFitsResources`这个预选函数为例做分析，其他重要的预选函数待后续单独分析。

`PodFitsResources`用来检查一个节点是否有足够的资源来运行当前的pod，包括CPU、内存、GPU等。

**PodFitsResources基本流程如下：**

1. 判断当前节点上pod总数加上预调度pod个数是否大于node的可分配pod总数，若是则不允许调度。
2. 判断pod的request值是否都为0，若是则允许调度。
3. 判断pod的request值加上当前node上所有pod的request值总和是否大于node的可分配资源，若是则不允许调度。
4. 判断pod的拓展资源request值加上当前node上所有pod对应的request值总和是否大于node对应的可分配资源，若是则不允许调度。

`PodFitsResources`的注册代码如下：

```go
factory.RegisterFitPredicate(predicates.PodFitsResourcesPred, predicates.PodFitsResources)
```

**PodFitsResources入参：**

- pod

- nodeInfo
- PredicateMetadata

**PodFitsResources出参：**

- fit
- PredicateFailureReason

PodFitsResources完整代码：

> 此部分的代码位于pkg/scheduler/algorithm/predicates/predicates.go

```go
// PodFitsResources checks if a node has sufficient resources, such as cpu, memory, gpu, opaque int resources etc to run a pod.
// First return value indicates whether a node has sufficient resources to run a pod while the second return value indicates the
// predicate failure reasons if the node has insufficient resources to run the pod.
func PodFitsResources(pod *v1.Pod, meta algorithm.PredicateMetadata, nodeInfo *schedulercache.NodeInfo) (bool, []algorithm.PredicateFailureReason, error) {
	node := nodeInfo.Node()
	if node == nil {
		return false, nil, fmt.Errorf("node not found")
	}

	var predicateFails []algorithm.PredicateFailureReason
	allowedPodNumber := nodeInfo.AllowedPodNumber()
	if len(nodeInfo.Pods())+1 > allowedPodNumber {
		predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourcePods, 1, int64(len(nodeInfo.Pods())), int64(allowedPodNumber)))
	}

	// No extended resources should be ignored by default.
	ignoredExtendedResources := sets.NewString()

	var podRequest *schedulercache.Resource
	if predicateMeta, ok := meta.(*predicateMetadata); ok {
		podRequest = predicateMeta.podRequest
		if predicateMeta.ignoredExtendedResources != nil {
			ignoredExtendedResources = predicateMeta.ignoredExtendedResources
		}
	} else {
		// We couldn't parse metadata - fallback to computing it.
		podRequest = GetResourceRequest(pod)
	}
	if podRequest.MilliCPU == 0 &&
		podRequest.Memory == 0 &&
		podRequest.EphemeralStorage == 0 &&
		len(podRequest.ScalarResources) == 0 {
		return len(predicateFails) == 0, predicateFails, nil
	}

	allocatable := nodeInfo.AllocatableResource()
	if allocatable.MilliCPU < podRequest.MilliCPU+nodeInfo.RequestedResource().MilliCPU {
		predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourceCPU, podRequest.MilliCPU, nodeInfo.RequestedResource().MilliCPU, allocatable.MilliCPU))
	}
	if allocatable.Memory < podRequest.Memory+nodeInfo.RequestedResource().Memory {
		predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourceMemory, podRequest.Memory, nodeInfo.RequestedResource().Memory, allocatable.Memory))
	}
	if allocatable.EphemeralStorage < podRequest.EphemeralStorage+nodeInfo.RequestedResource().EphemeralStorage {
		predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourceEphemeralStorage, podRequest.EphemeralStorage, nodeInfo.RequestedResource().EphemeralStorage, allocatable.EphemeralStorage))
	}

	for rName, rQuant := range podRequest.ScalarResources {
		if v1helper.IsExtendedResourceName(rName) {
			// If this resource is one of the extended resources that should be
			// ignored, we will skip checking it.
			if ignoredExtendedResources.Has(string(rName)) {
				continue
			}
		}
		if allocatable.ScalarResources[rName] < rQuant+nodeInfo.RequestedResource().ScalarResources[rName] {
			predicateFails = append(predicateFails, NewInsufficientResourceError(rName, podRequest.ScalarResources[rName], nodeInfo.RequestedResource().ScalarResources[rName], allocatable.ScalarResources[rName]))
		}
	}

	if glog.V(10) {
		if len(predicateFails) == 0 {
			// We explicitly don't do glog.V(10).Infof() to avoid computing all the parameters if this is
			// not logged. There is visible performance gain from it.
			glog.Infof("Schedule Pod %+v on Node %+v is allowed, Node is running only %v out of %v Pods.",
				podName(pod), node.Name, len(nodeInfo.Pods()), allowedPodNumber)
		}
	}
	return len(predicateFails) == 0, predicateFails, nil
}
```

## 6.1. NodeInfo

`NodeInfo`是node的聚合信息，主要包括：

- node：k8s node的结构体
- pods：当前node上pod的数量
- requestedResource：当前node上所有pod的request总和
- allocatableResource：node的实际所有的可分配资源(对应于Node.Status.Allocatable.*)，可理解为node的资源总量。

> 此部分代码位于pkg/scheduler/cache/node_info.go

```go
// NodeInfo is node level aggregated information.
type NodeInfo struct {
	// Overall node information.
	node *v1.Node

	pods             []*v1.Pod
	podsWithAffinity []*v1.Pod
	usedPorts        util.HostPortInfo

	// Total requested resource of all pods on this node.
	// It includes assumed pods which scheduler sends binding to apiserver but
	// didn't get it as scheduled yet.
	requestedResource *Resource
	nonzeroRequest    *Resource
	// We store allocatedResources (which is Node.Status.Allocatable.*) explicitly
	// as int64, to avoid conversions and accessing map.
	allocatableResource *Resource

	// Cached taints of the node for faster lookup.
	taints    []v1.Taint
	taintsErr error

	// imageStates holds the entry of an image if and only if this image is on the node. The entry can be used for
	// checking an image's existence and advanced usage (e.g., image locality scheduling policy) based on the image
	// state information.
	imageStates map[string]*ImageStateSummary

	// TransientInfo holds the information pertaining to a scheduling cycle. This will be destructed at the end of
	// scheduling cycle.
	// TODO: @ravig. Remove this once we have a clear approach for message passing across predicates and priorities.
	TransientInfo *transientSchedulerInfo

	// Cached conditions of node for faster lookup.
	memoryPressureCondition v1.ConditionStatus
	diskPressureCondition   v1.ConditionStatus
	pidPressureCondition    v1.ConditionStatus

	// Whenever NodeInfo changes, generation is bumped.
	// This is used to avoid cloning it if the object didn't change.
	generation int64
}
```

## 6.2. Resource

`Resource`是可计算资源的集合体。主要包括：

- MilliCPU
- Memory
- EphemeralStorage
- AllowedPodNumber：允许的pod总数(对应于Node.Status.Allocatable.Pods().Value())，一般为110。
- ScalarResources

```go
// Resource is a collection of compute resource.
type Resource struct {
	MilliCPU         int64
	Memory           int64
	EphemeralStorage int64
	// We store allowedPodNumber (which is Node.Status.Allocatable.Pods().Value())
	// explicitly as int, to avoid conversions and improve performance.
	AllowedPodNumber int
	// ScalarResources
	ScalarResources map[v1.ResourceName]int64
}
```

---

以下分析podFitsOnNode的具体流程。

## 6.3. allowedPodNumber

首先获取节点的信息，先判断如果该节点当前所有的pod的个数加上当前预调度的pod是否会大于该节点允许的pod的总数，一般为110个。如果超过，则`predicateFails`数组增加1，即当前节点不适合该pod。

```go
node := nodeInfo.Node()
if node == nil {
	return false, nil, fmt.Errorf("node not found")
}

var predicateFails []algorithm.PredicateFailureReason
allowedPodNumber := nodeInfo.AllowedPodNumber()
if len(nodeInfo.Pods())+1 > allowedPodNumber {
	predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourcePods, 1, int64(len(nodeInfo.Pods())), int64(allowedPodNumber)))
	}
```

## 6.4. podRequest

如果podRequest都为0，则允许调度到该节点，直接返回结果。

```go
if podRequest.MilliCPU == 0 &&
	podRequest.Memory == 0 &&
	podRequest.EphemeralStorage == 0 &&
	len(podRequest.ScalarResources) == 0 {
	return len(predicateFails) == 0, predicateFails, nil
}
```

## 6.5. AllocatableResource

如果当前预调度的pod的request资源加上当前node上所有pod的request总和大于该node的可分配资源总量，则不允许调度到该节点，直接返回结果。其中request资源包括CPU、内存、storage。

```go
allocatable := nodeInfo.AllocatableResource()
if allocatable.MilliCPU < podRequest.MilliCPU+nodeInfo.RequestedResource().MilliCPU {
	predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourceCPU, podRequest.MilliCPU, nodeInfo.RequestedResource().MilliCPU, allocatable.MilliCPU))
}
if allocatable.Memory < podRequest.Memory+nodeInfo.RequestedResource().Memory {
	predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourceMemory, podRequest.Memory, nodeInfo.RequestedResource().Memory, allocatable.Memory))
}
if allocatable.EphemeralStorage < podRequest.EphemeralStorage+nodeInfo.RequestedResource().EphemeralStorage {
	predicateFails = append(predicateFails, NewInsufficientResourceError(v1.ResourceEphemeralStorage, podRequest.EphemeralStorage, nodeInfo.RequestedResource().EphemeralStorage, allocatable.EphemeralStorage))
	}
```

## 6.6. ScalarResources

判断其他拓展的标量资源，是否该pod的request值加上当前node上所有pod的对应资源的request总和大于该node上对应资源的可分配总量，如果是，则不允许调度到该节点。

```go
for rName, rQuant := range podRequest.ScalarResources {
	if v1helper.IsExtendedResourceName(rName) {
		// If this resource is one of the extended resources that should be
		// ignored, we will skip checking it.
		if ignoredExtendedResources.Has(string(rName)) {
			continue
		}
	}
	if allocatable.ScalarResources[rName] < rQuant+nodeInfo.RequestedResource().ScalarResources[rName] {
		predicateFails = append(predicateFails, NewInsufficientResourceError(rName, podRequest.ScalarResources[rName], nodeInfo.RequestedResource().ScalarResources[rName], allocatable.ScalarResources[rName]))
	}
}
```

# 7. 总结

`findNodesThatFit`基于给定的预选函数过滤node，每个node传入到预选函数中来确实该节点是否符合要求。

`findNodesThatFit`的入参是被调度的pod和当前的节点列表，返回预选节点列表和错误。

**`findNodesThatFit`基本流程如下：**

1. 设置可行节点的总数，作为预选节点数组的容量，避免总节点过多导致需要筛选的节点过多，效率低。
2. 通过`NodeTree`不断获取下一个节点来判断该节点是否满足pod的调度条件。
3. 通过之前注册的各种预选函数来判断当前节点是否符合pod的调度条件。
4. 最后返回满足调度条件的node列表，供下一步的优选操作。

## 7.1. checkNode

`checkNode`是一个校验node是否符合要求的函数，其中实际调用到的核心函数是`podFitsOnNode`。再通过`workqueue`并发执行`checkNode`操作。

**`checkNode`主要流程如下：**

1. 通过cache中的nodeTree不断获取下一个node。
2. 将当前node和pod传入`podFitsOnNode`判断当前node是否符合要求。
3. 如果当前node符合要求就将当前node加入预选节点的数组中`filtered`。
4. 如果当前node不满足要求，则加入到失败的数组中，并记录原因。
5. 通过`workqueue.ParallelizeUntil`并发执行`checkNode`函数，一旦找到配置的可行节点数，就停止搜索更多节点。

## 7.2. podFitsOnNode

其中会调用到核心函数podFitsOnNode。

`podFitsOnNode`主要内容如下：

- `podFitsOnNode`会检查给定的某个Node是否满足预选的函数。

- 对于给定的pod，`podFitsOnNode`会检查是否有相同的pod存在，尽量复用缓存过的预选结果。

`podFitsOnNode`主要在`Schedule`（调度）和`Preempt`（抢占）的时候被调用。

当在`Schedule`中被调用的时候，主要判断是否可以被调度到当前节点，依据为当前节点上所有已存在的pod及被提名要运行到该节点的具有相等或更高优先级的pod。

当在`Preempt`中被调用的时候，即发生抢占的时候，通过`SelectVictimsOnNode`函数选出需要被移除的pod，移除后然后将预调度的pod调度到该节点上。

**podFitsOnNode基本流程如下：**

1. 遍历之前注册好的预选策略`predicates.Ordering`，并获取预选策略的执行函数。
2. 遍历执行每个`预选函数`，并返回是否合适，预选失败的原因和错误。
3. 如果预选函数执行的结果不合适，则加入预选失败的数组中。
4. 最后返回预选失败的个数是否为0，和预选失败的原因。

## 7.3. PodFitsResources

> 本文只示例分析了其中一个重要的预选函数：PodFitsResources

`PodFitsResources`用来检查一个节点是否有足够的资源来运行当前的pod，包括CPU、内存、GPU等。

**PodFitsResources基本流程如下：**

1. 判断当前节点上pod总数加上预调度pod个数是否大于node的可分配pod总数，若是则不允许调度。
2. 判断pod的request值是否都为0，若是则允许调度。
3. 判断pod的request值加上当前node上所有pod的request值总和是否大于node的可分配资源，若是则不允许调度。
4. 判断pod的拓展资源request值加上当前node上所有pod对应的request值总和是否大于node对应的可分配资源，若是则不允许调度。



参考：

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go>

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/algorithm/predicates/predicates.go>
