# kube-scheduler源码分析（五）之 PrioritizeNodes

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析`优选策略`逻辑，即从预选的节点中选择出最优的节点。优选策略的具体实现函数为`PrioritizeNodes`。`PrioritizeNodes`最终返回是一个记录了各个节点分数的列表。

# 1. [调用入口](<https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go#L165>)

`genericScheduler.Schedule`中对`PrioritizeNodes`的调用过程如下：

> 此部分代码位于pkg/scheduler/core/generic_scheduler.go

```go
func (g *genericScheduler) Schedule(pod *v1.Pod, nodeLister algorithm.NodeLister) (string, error) {
  ...
	trace.Step("Prioritizing")
	startPriorityEvalTime := time.Now()
	// When only one node after predicate, just use it.
	if len(filteredNodes) == 1 {
		metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
		return filteredNodes[0].Name, nil
	}

	metaPrioritiesInterface := g.priorityMetaProducer(pod, g.cachedNodeInfoMap)
  // 执行优选逻辑的操作，返回记录各个节点分数的列表
	priorityList, err := PrioritizeNodes(pod, g.cachedNodeInfoMap, metaPrioritiesInterface, g.prioritizers, filteredNodes, g.extenders)
	if err != nil {
		return "", err
	}
	metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
	metrics.SchedulingLatency.WithLabelValues(metrics.PriorityEvaluation).Observe(metrics.SinceInSeconds(startPriorityEvalTime))
  ...
}  
```

核心代码：

```go
// 基于预选节点filteredNodes进一步筛选优选的节点，返回记录各个节点分数的列表
priorityList, err := PrioritizeNodes(pod, g.cachedNodeInfoMap, metaPrioritiesInterface, g.prioritizers, filteredNodes, g.extenders)
```

# 2. [PrioritizeNodes](<https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go#L602>)

优选，从满足的节点中选择出最优的节点。`PrioritizeNodes`最终返回是一个记录了各个节点分数的列表。

具体操作如下：

- PrioritizeNodes通过并行运行各个优先级函数来对节点进行优先级排序。
- 每个优先级函数会给节点打分，打分范围为0-10分。
- 0 表示优先级最低的节点，10表示优先级最高的节点。
- 每个优先级函数也有各自的权重。
- 优先级函数返回的节点分数乘以权重以获得加权分数。
- 最后组合（添加）所有分数以获得所有节点的总加权分数。

**PrioritizeNodes主要流程如下：**

1. 如果没有设置优选函数和拓展函数，则全部节点设置相同的分数，直接返回。
2. 依次给node执行map函数进行打分。
3. 再对上述map函数的执行结果执行reduce函数计算最终得分。
4. 最后根据不同优先级函数的权重对得分取加权平均数。



**入参：**

- pod
- nodeNameToInfo
- meta interface{},
- priorityConfigs
- nodes
- extenders

**出参：**

- HostPriorityList：记录节点分数的列表。

`HostPriority`定义如下:

```go
// HostPriority represents the priority of scheduling to a particular host, higher priority is better.
type HostPriority struct {
	// Name of the host
	Host string
	// Score associated with the host
	Score int
}
```

`PrioritizeNodes`完整代码如下：

> 此部分代码位于pkg/scheduler/core/generic_scheduler.go

```go
// PrioritizeNodes prioritizes the nodes by running the individual priority functions in parallel.
// Each priority function is expected to set a score of 0-10
// 0 is the lowest priority score (least preferred node) and 10 is the highest
// Each priority function can also have its own weight
// The node scores returned by the priority function are multiplied by the weights to get weighted scores
// All scores are finally combined (added) to get the total weighted scores of all nodes
func PrioritizeNodes(
	pod *v1.Pod,
	nodeNameToInfo map[string]*schedulercache.NodeInfo,
	meta interface{},
	priorityConfigs []algorithm.PriorityConfig,
	nodes []*v1.Node,
	extenders []algorithm.SchedulerExtender,
) (schedulerapi.HostPriorityList, error) {
	// If no priority configs are provided, then the EqualPriority function is applied
	// This is required to generate the priority list in the required format
	if len(priorityConfigs) == 0 && len(extenders) == 0 {
		result := make(schedulerapi.HostPriorityList, 0, len(nodes))
		for i := range nodes {
			hostPriority, err := EqualPriorityMap(pod, meta, nodeNameToInfo[nodes[i].Name])
			if err != nil {
				return nil, err
			}
			result = append(result, hostPriority)
		}
		return result, nil
	}

	var (
		mu   = sync.Mutex{}
		wg   = sync.WaitGroup{}
		errs []error
	)
	appendError := func(err error) {
		mu.Lock()
		defer mu.Unlock()
		errs = append(errs, err)
	}

	results := make([]schedulerapi.HostPriorityList, len(priorityConfigs), len(priorityConfigs))

	for i, priorityConfig := range priorityConfigs {
		if priorityConfig.Function != nil {
			// DEPRECATED
			wg.Add(1)
			go func(index int, config algorithm.PriorityConfig) {
				defer wg.Done()
				var err error
				results[index], err = config.Function(pod, nodeNameToInfo, nodes)
				if err != nil {
					appendError(err)
				}
			}(i, priorityConfig)
		} else {
			results[i] = make(schedulerapi.HostPriorityList, len(nodes))
		}
	}
	processNode := func(index int) {
		nodeInfo := nodeNameToInfo[nodes[index].Name]
		var err error
		for i := range priorityConfigs {
			if priorityConfigs[i].Function != nil {
				continue
			}
			results[i][index], err = priorityConfigs[i].Map(pod, meta, nodeInfo)
			if err != nil {
				appendError(err)
				return
			}
		}
	}
	workqueue.Parallelize(16, len(nodes), processNode)
	for i, priorityConfig := range priorityConfigs {
		if priorityConfig.Reduce == nil {
			continue
		}
		wg.Add(1)
		go func(index int, config algorithm.PriorityConfig) {
			defer wg.Done()
			if err := config.Reduce(pod, meta, nodeNameToInfo, results[index]); err != nil {
				appendError(err)
			}
			if glog.V(10) {
				for _, hostPriority := range results[index] {
					glog.Infof("%v -> %v: %v, Score: (%d)", pod.Name, hostPriority.Host, config.Name, hostPriority.Score)
				}
			}
		}(i, priorityConfig)
	}
	// Wait for all computations to be finished.
	wg.Wait()
	if len(errs) != 0 {
		return schedulerapi.HostPriorityList{}, errors.NewAggregate(errs)
	}

	// Summarize all scores.
	result := make(schedulerapi.HostPriorityList, 0, len(nodes))

	for i := range nodes {
		result = append(result, schedulerapi.HostPriority{Host: nodes[i].Name, Score: 0})
		for j := range priorityConfigs {
			result[i].Score += results[j][i].Score * priorityConfigs[j].Weight
		}
	}

	if len(extenders) != 0 && nodes != nil {
		combinedScores := make(map[string]int, len(nodeNameToInfo))
		for _, extender := range extenders {
			if !extender.IsInterested(pod) {
				continue
			}
			wg.Add(1)
			go func(ext algorithm.SchedulerExtender) {
				defer wg.Done()
				prioritizedList, weight, err := ext.Prioritize(pod, nodes)
				if err != nil {
					// Prioritization errors from extender can be ignored, let k8s/other extenders determine the priorities
					return
				}
				mu.Lock()
				for i := range *prioritizedList {
					host, score := (*prioritizedList)[i].Host, (*prioritizedList)[i].Score
					combinedScores[host] += score * weight
				}
				mu.Unlock()
			}(extender)
		}
		// wait for all go routines to finish
		wg.Wait()
		for i := range result {
			result[i].Score += combinedScores[result[i].Host]
		}
	}

	if glog.V(10) {
		for i := range result {
			glog.V(10).Infof("Host %s => Score %d", result[i].Host, result[i].Score)
		}
	}
	return result, nil
}
```

---

以下对`PrioritizeNodes`分段进行分析。

# 3. EqualPriorityMap

如果没有提供优选函数和拓展函数，则将所有的节点设置为相同的优先级，即节点的score都为1，然后直接返回结果。(但一般情况下优选函数列表都不为空)

```go
// If no priority configs are provided, then the EqualPriority function is applied
// This is required to generate the priority list in the required format
if len(priorityConfigs) == 0 && len(extenders) == 0 {
	result := make(schedulerapi.HostPriorityList, 0, len(nodes))
	for i := range nodes {
		hostPriority, err := EqualPriorityMap(pod, meta, nodeNameToInfo[nodes[i].Name])
		if err != nil {
			return nil, err
		}
		result = append(result, hostPriority)
	}
	return result, nil
}
```

EqualPriorityMap具体实现如下：

```go
// EqualPriorityMap is a prioritizer function that gives an equal weight of one to all nodes
func EqualPriorityMap(_ *v1.Pod, _ interface{}, nodeInfo *schedulercache.NodeInfo) (schedulerapi.HostPriority, error) {
	node := nodeInfo.Node()
	if node == nil {
		return schedulerapi.HostPriority{}, fmt.Errorf("node not found")
	}
	return schedulerapi.HostPriority{
		Host:  node.Name,
		Score: 1,
	}, nil
}
```

# 4. processNode

`processNode`就是基于index拿出node的信息，调用之前注册的各种优选函数（此处是`mapFunction`），通过优选函数对node和pod进行处理，最后返回一个记录node分数的列表`result`。`processNode`同样也使用`workqueue.Parallelize`来进行并行处理。(`processNode`类似于预选逻辑`findNodesThatFit`中使用到的`checkNode`的作用)

其中优选函数是通过`priorityConfigs`来记录，每类优选函数包括`PriorityMapFunction`和`PriorityReduceFunction`两种函数。优选函数的注册部分可参考[registerAlgorithmProvider](registerAlgorithmProvider.md)。

```go
processNode := func(index int) {
	nodeInfo := nodeNameToInfo[nodes[index].Name]
	var err error
	for i := range priorityConfigs {
		if priorityConfigs[i].Function != nil {
			continue
		}
		results[i][index], err = priorityConfigs[i].Map(pod, meta, nodeInfo)
		if err != nil {
			appendError(err)
			return
		}
	}
}
// 并行执行processNode
workqueue.Parallelize(16, len(nodes), processNode)
```

`priorityConfigs`定义如下：

核心属性：

- Map ：PriorityMapFunction 
- Reduce：PriorityReduceFunction

```go
// PriorityConfig is a config used for a priority function.
type PriorityConfig struct {
	Name   string
	Map    PriorityMapFunction   
	Reduce PriorityReduceFunction
	// TODO: Remove it after migrating all functions to
	// Map-Reduce pattern.
	Function PriorityFunction
	Weight   int
}
```

具体的优选函数处理逻辑待下文分析，本文会以`NewSelectorSpreadPriority`函数为例。

# 5. PriorityMapFunction

`PriorityMapFunction`是一个计算给定节点的每个节点结果的函数。

`PriorityMapFunction`定义如下：

```go
// PriorityMapFunction is a function that computes per-node results for a given node.
// TODO: Figure out the exact API of this method.
// TODO: Change interface{} to a specific type.
type PriorityMapFunction func(pod *v1.Pod, meta interface{}, nodeInfo *schedulercache.NodeInfo) (schedulerapi.HostPriority, error)
```

PriorityMapFunction是在`processNode`中调用的，代码如下：

```go
results[i][index], err = priorityConfigs[i].Map(pod, meta, nodeInfo)
```

下文会分析`NewSelectorSpreadPriority`在的map函数`CalculateSpreadPriorityMap`。

# 6. PriorityReduceFunction

`PriorityReduceFunction`是一个聚合每个节点结果并计算所有节点的最终得分的函数。

`PriorityReduceFunction`定义如下：

```go
// PriorityReduceFunction is a function that aggregated per-node results and computes
// final scores for all nodes.
// TODO: Figure out the exact API of this method.
// TODO: Change interface{} to a specific type.
type PriorityReduceFunction func(pod *v1.Pod, meta interface{}, nodeNameToInfo map[string]*schedulercache.NodeInfo, result schedulerapi.HostPriorityList) error
```

PrioritizeNodes中对reduce函数调用部分如下：

```go
for i, priorityConfig := range priorityConfigs {
	if priorityConfig.Reduce == nil {
		continue
	}
	wg.Add(1)
	go func(index int, config algorithm.PriorityConfig) {
		defer wg.Done()
		if err := config.Reduce(pod, meta, nodeNameToInfo, results[index]); err != nil {
			appendError(err)
		}
		if glog.V(10) {
			for _, hostPriority := range results[index] {
				glog.Infof("%v -> %v: %v, Score: (%d)", pod.Name, hostPriority.Host, config.Name, hostPriority.Score)
			}
		}
	}(i, priorityConfig)
}
```

下文会分析`NewSelectorSpreadPriority`在的reduce函数`CalculateSpreadPriorityReduce`。

# 7. Summarize all scores

先等待计算完成再计算加权平均数。

```go
// Wait for all computations to be finished.
wg.Wait()
if len(errs) != 0 {
	return schedulerapi.HostPriorityList{}, errors.NewAggregate(errs)
}
```

计算所有节点的加权平均数。

```go
// Summarize all scores.
result := make(schedulerapi.HostPriorityList, 0, len(nodes))

for i := range nodes {
	result = append(result, schedulerapi.HostPriority{Host: nodes[i].Name, Score: 0})
	for j := range priorityConfigs {
		result[i].Score += results[j][i].Score * priorityConfigs[j].Weight
	}
}
```

当设置了拓展的计算方式，则增加拓展计算方式的加权平均数。

```go
if len(extenders) != 0 && nodes != nil {
	combinedScores := make(map[string]int, len(nodeNameToInfo))
	for _, extender := range extenders {
		if !extender.IsInterested(pod) {
			continue
		}
		wg.Add(1)
		go func(ext algorithm.SchedulerExtender) {
			defer wg.Done()
			prioritizedList, weight, err := ext.Prioritize(pod, nodes)
			if err != nil {
				// Prioritization errors from extender can be ignored, let k8s/other extenders determine the priorities
				return
			}
			mu.Lock()
			for i := range *prioritizedList {
				host, score := (*prioritizedList)[i].Host, (*prioritizedList)[i].Score
				combinedScores[host] += score * weight
			}
			mu.Unlock()
		}(extender)
	}
	// wait for all go routines to finish
	wg.Wait()
	for i := range result {
		result[i].Score += combinedScores[result[i].Host]
	}
}
```

# 8. NewSelectorSpreadPriority

以下以`NewSelectorSpreadPriority`这个优选函数来做分析，其他重要的优选函数待后续专门分析。

`NewSelectorSpreadPriority`主要的功能是将属于相同service和rs下的pod尽量分布在不同的node上。

该函数的注册代码如下：

> 此部分代码位于pkg/scheduler/algorithmprovider/defaults/defaults.go

```go
// ServiceSpreadingPriority is a priority config factory that spreads pods by minimizing
// the number of pods (belonging to the same service) on the same node.
// Register the factory so that it's available, but do not include it as part of the default priorities
// Largely replaced by "SelectorSpreadPriority", but registered for backward compatibility with 1.0
factory.RegisterPriorityConfigFactory(
	"ServiceSpreadingPriority",
	factory.PriorityConfigFactory{
		MapReduceFunction: func(args factory.PluginFactoryArgs) (algorithm.PriorityMapFunction, algorithm.PriorityReduceFunction) {
			return priorities.NewSelectorSpreadPriority(args.ServiceLister, algorithm.EmptyControllerLister{}, algorithm.EmptyReplicaSetLister{}, algorithm.EmptyStatefulSetLister{})
		},
		Weight: 1,
	},
)
```

`NewSelectorSpreadPriority`的具体实现如下：

> 此部分代码位于pkg/scheduler/algorithm/priorities/selector_spreading.go

```go
// NewSelectorSpreadPriority creates a SelectorSpread.
func NewSelectorSpreadPriority(
	serviceLister algorithm.ServiceLister,
	controllerLister algorithm.ControllerLister,
	replicaSetLister algorithm.ReplicaSetLister,
	statefulSetLister algorithm.StatefulSetLister) (algorithm.PriorityMapFunction, algorithm.PriorityReduceFunction) {
	selectorSpread := &SelectorSpread{
		serviceLister:     serviceLister,
		controllerLister:  controllerLister,
		replicaSetLister:  replicaSetLister,
		statefulSetLister: statefulSetLister,
	}
	return selectorSpread.CalculateSpreadPriorityMap, selectorSpread.CalculateSpreadPriorityReduce
}
```

`NewSelectorSpreadPriority`主要包括map和reduce两种函数，分别对应`CalculateSpreadPriorityMap`，`CalculateSpreadPriorityReduce`。

## 8.1. [CalculateSpreadPriorityMap](<https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/algorithm/priorities/selector_spreading.go#L66>)

`CalculateSpreadPriorityMap`的主要作用是将相同service、RC、RS或statefulset的pod分布在不同的节点上。当调度一个pod的时候，先寻找与该pod匹配的service、RS、RC或statefulset，然后寻找与其selector匹配的已存在的pod，寻找存在这类pod最少的节点。

**基本流程如下：**

1. 寻找与该pod对应的service、RS、RC、statefulset匹配的selector。
2. 遍历当前节点的所有pod，将该节点上已存在的selector匹配到的pod的个数作为该节点的分数（此时，分数大的表示匹配到的pod越多，越不符合被调度的条件，该分数在reduce阶段会被按10分制处理成分数大的越符合被调度的条件）。

> 此部分代码位于pkg/scheduler/algorithm/priorities/selector_spreading.go

```go
// CalculateSpreadPriorityMap spreads pods across hosts, considering pods
// belonging to the same service,RC,RS or StatefulSet.
// When a pod is scheduled, it looks for services, RCs,RSs and StatefulSets that match the pod,
// then finds existing pods that match those selectors.
// It favors nodes that have fewer existing matching pods.
// i.e. it pushes the scheduler towards a node where there's the smallest number of
// pods which match the same service, RC,RSs or StatefulSets selectors as the pod being scheduled.
func (s *SelectorSpread) CalculateSpreadPriorityMap(pod *v1.Pod, meta interface{}, nodeInfo *schedulercache.NodeInfo) (schedulerapi.HostPriority, error) {
	var selectors []labels.Selector
	node := nodeInfo.Node()
	if node == nil {
		return schedulerapi.HostPriority{}, fmt.Errorf("node not found")
	}

	priorityMeta, ok := meta.(*priorityMetadata)
	if ok {
		selectors = priorityMeta.podSelectors
	} else {
		selectors = getSelectors(pod, s.serviceLister, s.controllerLister, s.replicaSetLister, s.statefulSetLister)
	}

	if len(selectors) == 0 {
		return schedulerapi.HostPriority{
			Host:  node.Name,
			Score: int(0),
		}, nil
	}

	count := int(0)
	for _, nodePod := range nodeInfo.Pods() {
		if pod.Namespace != nodePod.Namespace {
			continue
		}
		// When we are replacing a failed pod, we often see the previous
		// deleted version while scheduling the replacement.
		// Ignore the previous deleted version for spreading purposes
		// (it can still be considered for resource restrictions etc.)
		if nodePod.DeletionTimestamp != nil {
			glog.V(4).Infof("skipping pending-deleted pod: %s/%s", nodePod.Namespace, nodePod.Name)
			continue
		}
		for _, selector := range selectors {
			if selector.Matches(labels.Set(nodePod.ObjectMeta.Labels)) {
				count++
				break
			}
		}
	}
	return schedulerapi.HostPriority{
		Host:  node.Name,
		Score: int(count),
	}, nil
}
```

以下分段分析：

先获得selector。

```go
selectors = getSelectors(pod, s.serviceLister, s.controllerLister, s.replicaSetLister, s.statefulSetLister)
```

计算节点上匹配selector的pod的个数，作为该节点分数，该分数并不是最终节点的分数，只是中间过渡的记录状态。

```go
count := int(0)
for _, nodePod := range nodeInfo.Pods() {
	...
	for _, selector := range selectors {
		if selector.Matches(labels.Set(nodePod.ObjectMeta.Labels)) {
			count++
			break
		}
	}
}
```

## 8.2. [CalculateSpreadPriorityReduce](<https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/algorithm/priorities/selector_spreading.go#L117>)

`CalculateSpreadPriorityReduce`根据节点上现有匹配pod的数量计算每个节点的十分制的分数，具有较少现有匹配pod的节点的分数越高，表示节点越可能被调度到。

**基本流程如下：**

1. 记录所有节点中匹配到pod个数最多的节点的分数（即匹配到的pod最多的个数）。
2. 遍历所有的节点，按比例取十分制的得分，计算方式为：(节点中最多匹配pod的个数-当前节点pod的个数)/节点中最多匹配pod的个数。此时，分数越高表示该节点上匹配到的pod的个数越少，越可能被调度到，即满足把相同selector的pod分散到不同节点的需求。

> 此部分代码位于pkg/scheduler/algorithm/priorities/selector_spreading.go

```go
// CalculateSpreadPriorityReduce calculates the source of each node
// based on the number of existing matching pods on the node
// where zone information is included on the nodes, it favors nodes
// in zones with fewer existing matching pods.
func (s *SelectorSpread) CalculateSpreadPriorityReduce(pod *v1.Pod, meta interface{}, nodeNameToInfo map[string]*schedulercache.NodeInfo, result schedulerapi.HostPriorityList) error {
	countsByZone := make(map[string]int, 10)
	maxCountByZone := int(0)
	maxCountByNodeName := int(0)

	for i := range result {
		if result[i].Score > maxCountByNodeName {
			maxCountByNodeName = result[i].Score
		}
		zoneID := utilnode.GetZoneKey(nodeNameToInfo[result[i].Host].Node())
		if zoneID == "" {
			continue
		}
		countsByZone[zoneID] += result[i].Score
	}

	for zoneID := range countsByZone {
		if countsByZone[zoneID] > maxCountByZone {
			maxCountByZone = countsByZone[zoneID]
		}
	}

	haveZones := len(countsByZone) != 0

	maxCountByNodeNameFloat64 := float64(maxCountByNodeName)
	maxCountByZoneFloat64 := float64(maxCountByZone)
	MaxPriorityFloat64 := float64(schedulerapi.MaxPriority)

	for i := range result {
		// initializing to the default/max node score of maxPriority
		fScore := MaxPriorityFloat64
		if maxCountByNodeName > 0 {
			fScore = MaxPriorityFloat64 * (float64(maxCountByNodeName-result[i].Score) / maxCountByNodeNameFloat64)
		}
		// If there is zone information present, incorporate it
		if haveZones {
			zoneID := utilnode.GetZoneKey(nodeNameToInfo[result[i].Host].Node())
			if zoneID != "" {
				zoneScore := MaxPriorityFloat64
				if maxCountByZone > 0 {
					zoneScore = MaxPriorityFloat64 * (float64(maxCountByZone-countsByZone[zoneID]) / maxCountByZoneFloat64)
				}
				fScore = (fScore * (1.0 - zoneWeighting)) + (zoneWeighting * zoneScore)
			}
		}
		result[i].Score = int(fScore)
		if glog.V(10) {
			glog.Infof(
				"%v -> %v: SelectorSpreadPriority, Score: (%d)", pod.Name, result[i].Host, int(fScore),
			)
		}
	}
	return nil
}
```

以下分段分析：

先获取所有节点中匹配到的pod最多的个数。

```go
for i := range result {
	if result[i].Score > maxCountByNodeName {
		maxCountByNodeName = result[i].Score
	}
	zoneID := utilnode.GetZoneKey(nodeNameToInfo[result[i].Host].Node())
	if zoneID == "" {
		continue
	}
	countsByZone[zoneID] += result[i].Score
}
```

遍历所有的节点，按比例取十分制的得分。

```go
for i := range result {
	// initializing to the default/max node score of maxPriority
	fScore := MaxPriorityFloat64
	if maxCountByNodeName > 0 {
		fScore = MaxPriorityFloat64 * (float64(maxCountByNodeName-result[i].Score) / maxCountByNodeNameFloat64)
	}
  ...
}  
```

# 9. 总结

优选，从满足的节点中选择出最优的节点。`PrioritizeNodes`最终返回是一个记录了各个节点分数的列表。

## 9.1. PrioritizeNodes

**主要流程如下：**

1. 如果没有设置优选函数和拓展函数，则全部节点设置相同的分数，直接返回。
2. 依次给node执行map函数进行打分。
3. 再对上述map函数的执行结果执行reduce函数计算最终得分。
4. 最后根据不同优先级函数的权重对得分取加权平均数。

其中每类优选函数会包含map函数和reduce函数两种。

## 9.2. NewSelectorSpreadPriority

其中以`NewSelectorSpreadPriority`这个优选函数为例作分析，该函数的功能是将相同service、RS、RC或statefulset下pod尽量分散到不同的节点上。包括map函数和reduce函数两部分，具体如下。

### 9.2.1. CalculateSpreadPriorityMap

**基本流程如下：**

1. 寻找与该pod对应的service、RS、RC、statefulset匹配的selector。
2. 遍历当前节点的所有pod，将该节点上已存在的selector匹配到的pod的个数作为该节点的分数（此时，分数大的表示匹配到的pod越多，越不符合被调度的条件，该分数在reduce阶段会被按10分制处理成分数大的越符合被调度的条件）。

### 9.2.2. CalculateSpreadPriorityReduce

**基本流程如下：**

1. 记录所有节点中匹配到pod个数最多的节点的分数（即匹配到的pod最多的个数）。
2. 遍历所有的节点，按比例取十分制的得分，计算方式为：(节点中最多匹配pod的个数-当前节点pod的个数)/节点中最多匹配pod的个数。此时，分数越高表示该节点上匹配到的pod的个数越少，越可能被调度到，即满足把相同selector的pod分散到不同节点的需求。





参考：

- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/core/generic_scheduler.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/algorithm/priorities/selector_spreading.go>
