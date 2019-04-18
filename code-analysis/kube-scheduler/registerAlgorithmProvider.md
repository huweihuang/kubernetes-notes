# kube-scheduler源码分析（二）之 registerAlgorithmProvider

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

此部分主要介绍调度中使用的各种调度算法，包括调度算法的注册部分。注册部分的代码主要在`/pkg/scheduler/algorithmprovider`中，具体的预选策略和优选策略的算法实现在`/pkg/scheduler/algorithm`中。

# 1. ApplyFeatureGates

注册调度算法的调用入口在SchedulerCommand的Run函数中。

> 此部分代码位于/cmd/kube-scheduler/app/server.go

```go
// Run runs the Scheduler.
func Run(c schedulerserverconfig.CompletedConfig, stopCh <-chan struct{}) error {
	...
	// Apply algorithms based on feature gates.
	// TODO: make configurable?
	algorithmprovider.ApplyFeatureGates()
  ...
}  
```

ApplyFeatureGates的具体实现在`pkg/scheduler/algorithmprovider`的包中。

> 此部分代码位于/pkg/scheduler/algorithmprovider/plugins.go

```go
// ApplyFeatureGates applies algorithm by feature gates.
func ApplyFeatureGates() {
	defaults.ApplyFeatureGates()
}
```

ApplyFeatureGates具体实现如下：

> 此部分代码位于/pkg/scheduler/algorithmprovider/defaults/defaults.go

根据feature移除部分调度策略。

```go
// ApplyFeatureGates applies algorithm by feature gates.
func ApplyFeatureGates() {
	if utilfeature.DefaultFeatureGate.Enabled(features.TaintNodesByCondition) {
		// Remove "CheckNodeCondition", "CheckNodeMemoryPressure", "CheckNodePIDPressurePred"
		// and "CheckNodeDiskPressure" predicates
		factory.RemoveFitPredicate(predicates.CheckNodeConditionPred)
		factory.RemoveFitPredicate(predicates.CheckNodeMemoryPressurePred)
		factory.RemoveFitPredicate(predicates.CheckNodeDiskPressurePred)
		factory.RemoveFitPredicate(predicates.CheckNodePIDPressurePred)
		// Remove key "CheckNodeCondition", "CheckNodeMemoryPressure" and "CheckNodeDiskPressure"
		// from ALL algorithm provider
		// The key will be removed from all providers which in algorithmProviderMap[]
		// if you just want remove specific provider, call func RemovePredicateKeyFromAlgoProvider()
		factory.RemovePredicateKeyFromAlgorithmProviderMap(predicates.CheckNodeConditionPred)
		factory.RemovePredicateKeyFromAlgorithmProviderMap(predicates.CheckNodeMemoryPressurePred)
		factory.RemovePredicateKeyFromAlgorithmProviderMap(predicates.CheckNodeDiskPressurePred)
		factory.RemovePredicateKeyFromAlgorithmProviderMap(predicates.CheckNodePIDPressurePred)

		// Fit is determined based on whether a pod can tolerate all of the node's taints
		factory.RegisterMandatoryFitPredicate(predicates.PodToleratesNodeTaintsPred, predicates.PodToleratesNodeTaints)
		// Fit is determined based on whether a pod can tolerate unschedulable of node
		factory.RegisterMandatoryFitPredicate(predicates.CheckNodeUnschedulablePred, predicates.CheckNodeUnschedulablePredicate)
		// Insert Key "PodToleratesNodeTaints" and "CheckNodeUnschedulable" To All Algorithm Provider
		// The key will insert to all providers which in algorithmProviderMap[]
		// if you just want insert to specific provider, call func InsertPredicateKeyToAlgoProvider()
		factory.InsertPredicateKeyToAlgorithmProviderMap(predicates.PodToleratesNodeTaintsPred)
		factory.InsertPredicateKeyToAlgorithmProviderMap(predicates.CheckNodeUnschedulablePred)

		glog.Warningf("TaintNodesByCondition is enabled, PodToleratesNodeTaints predicate is mandatory")
	}

	// Prioritizes nodes that satisfy pod's resource limits
	if utilfeature.DefaultFeatureGate.Enabled(features.ResourceLimitsPriorityFunction) {
		factory.RegisterPriorityFunction2("ResourceLimitsPriority", priorities.ResourceLimitsPriorityMap, nil, 1)
	}

}
```

# 2. init

当函数逻辑调用到`algorithmprovider`包时，就会自动调用init的初始化函数，此部分主要包括对预选算法和优选算法的注册。

> 此部分代码位于/pkg/scheduler/algorithmprovider/defaults/defaults.go

```go
func init() {
	// Register functions that extract metadata used by predicates and priorities computations.
	factory.RegisterPredicateMetadataProducerFactory(
		func(args factory.PluginFactoryArgs) algorithm.PredicateMetadataProducer {
			return predicates.NewPredicateMetadataFactory(args.PodLister)
		})
	factory.RegisterPriorityMetadataProducerFactory(
		func(args factory.PluginFactoryArgs) algorithm.PriorityMetadataProducer {
			return priorities.NewPriorityMetadataFactory(args.ServiceLister, args.ControllerLister, args.ReplicaSetLister, args.StatefulSetLister)
		})

	registerAlgorithmProvider(defaultPredicates(), defaultPriorities())

	// IMPORTANT NOTES for predicate developers:
	// We are using cached predicate result for pods belonging to the same equivalence class.
	// So when implementing a new predicate, you are expected to check whether the result
	// of your predicate function can be affected by related API object change (ADD/DELETE/UPDATE).
	// If yes, you are expected to invalidate the cached predicate result for related API object change.
	// For example:
	// https://github.com/kubernetes/kubernetes/blob/36a218e/plugin/pkg/scheduler/factory/factory.go#L422

	// Registers predicates and priorities that are not enabled by default, but user can pick when creating their
	// own set of priorities/predicates.

	// PodFitsPorts has been replaced by PodFitsHostPorts for better user understanding.
	// For backwards compatibility with 1.0, PodFitsPorts is registered as well.
	factory.RegisterFitPredicate("PodFitsPorts", predicates.PodFitsHostPorts)
	// Fit is defined based on the absence of port conflicts.
	// This predicate is actually a default predicate, because it is invoked from
	// predicates.GeneralPredicates()
	factory.RegisterFitPredicate(predicates.PodFitsHostPortsPred, predicates.PodFitsHostPorts)
	// Fit is determined by resource availability.
	// This predicate is actually a default predicate, because it is invoked from
	// predicates.GeneralPredicates()
	factory.RegisterFitPredicate(predicates.PodFitsResourcesPred, predicates.PodFitsResources)
	// Fit is determined by the presence of the Host parameter and a string match
	// This predicate is actually a default predicate, because it is invoked from
	// predicates.GeneralPredicates()
	factory.RegisterFitPredicate(predicates.HostNamePred, predicates.PodFitsHost)
	// Fit is determined by node selector query.
	factory.RegisterFitPredicate(predicates.MatchNodeSelectorPred, predicates.PodMatchNodeSelector)

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
	// EqualPriority is a prioritizer function that gives an equal weight of one to all nodes
	// Register the priority function so that its available
	// but do not include it as part of the default priorities
	factory.RegisterPriorityFunction2("EqualPriority", core.EqualPriorityMap, nil, 1)
	// Optional, cluster-autoscaler friendly priority function - give used nodes higher priority.
	factory.RegisterPriorityFunction2("MostRequestedPriority", priorities.MostRequestedPriorityMap, nil, 1)
	factory.RegisterPriorityFunction2(
		"RequestedToCapacityRatioPriority",
		priorities.RequestedToCapacityRatioResourceAllocationPriorityDefault().PriorityMap,
		nil,
		1)
}
```

以下对init中的注册进行拆分介绍。

## 2.1. registerAlgorithmProvider

此部分主要注册默认的预选和优选策略。

```go
// Register functions that extract metadata used by predicates and priorities computations.
factory.RegisterPredicateMetadataProducerFactory(
	func(args factory.PluginFactoryArgs) algorithm.PredicateMetadataProducer {
		return predicates.NewPredicateMetadataFactory(args.PodLister)
	})
factory.RegisterPriorityMetadataProducerFactory(
	func(args factory.PluginFactoryArgs) algorithm.PriorityMetadataProducer {
		return priorities.NewPriorityMetadataFactory(args.ServiceLister, args.ControllerLister, args.ReplicaSetLister, args.StatefulSetLister)
	})

registerAlgorithmProvider(defaultPredicates(), defaultPriorities())
```

**registerAlgorithmProvider**

注册AlgorithmProvider，其中包括`DefaultProvider`和`ClusterAutoscalerProvider`。

```go
func registerAlgorithmProvider(predSet, priSet sets.String) {
	// Registers algorithm providers. By default we use 'DefaultProvider', but user can specify one to be used
	// by specifying flag.
	factory.RegisterAlgorithmProvider(factory.DefaultProvider, predSet, priSet)
	// Cluster autoscaler friendly scheduling algorithm.
	factory.RegisterAlgorithmProvider(ClusterAutoscalerProvider, predSet,
		copyAndReplace(priSet, "LeastRequestedPriority", "MostRequestedPriority"))
}
```

## 2.2. RegisterFitPredicate

在init部分注册预选策略函数。

预选策略如下：

| 调度策略              | 函数                 | 描述                                                         |
| --------------------- | -------------------- | ------------------------------------------------------------ |
| PodFitsPorts          | PodFitsHostPorts     | PodFitsPorts已经被PodFitsHostPorts代替，此处主要是为了兼容性。 |
| PodFitsHostPortsPred  | PodFitsHostPorts     | 判断是否与宿主机的端口冲突。                                 |
| PodFitsResourcesPred  | PodFitsResources     | 判断node资源是否充足。                                       |
| HostNamePred          | PodFitsHost          | 判断pod所指定调度的节点是否是当前的节点。                    |
| MatchNodeSelectorPred | PodMatchNodeSelector | 判断pod指定的node selector是否匹配当前的node。               |

具体代码如下：

```go
// PodFitsPorts has been replaced by PodFitsHostPorts for better user understanding.
// For backwards compatibility with 1.0, PodFitsPorts is registered as well.
factory.RegisterFitPredicate("PodFitsPorts", predicates.PodFitsHostPorts)
// Fit is defined based on the absence of port conflicts.
// This predicate is actually a default predicate, because it is invoked from
// predicates.GeneralPredicates()
factory.RegisterFitPredicate(predicates.PodFitsHostPortsPred, predicates.PodFitsHostPorts)
// Fit is determined by resource availability.
// This predicate is actually a default predicate, because it is invoked from
// predicates.GeneralPredicates()
factory.RegisterFitPredicate(predicates.PodFitsResourcesPred, predicates.PodFitsResources)
// Fit is determined by the presence of the Host parameter and a string match
// This predicate is actually a default predicate, because it is invoked from
// predicates.GeneralPredicates()
factory.RegisterFitPredicate(predicates.HostNamePred, predicates.PodFitsHost)
// Fit is determined by node selector query.
factory.RegisterFitPredicate(predicates.MatchNodeSelectorPred, predicates.PodMatchNodeSelector)
```

## 2.3. RegisterPriorityFunction2

在init部分注册优选策略函数。

```go
// EqualPriority is a prioritizer function that gives an equal weight of one to all nodes
// Register the priority function so that its available
// but do not include it as part of the default priorities
factory.RegisterPriorityFunction2("EqualPriority", core.EqualPriorityMap, nil, 1)
// Optional, cluster-autoscaler friendly priority function - give used nodes higher priority.
factory.RegisterPriorityFunction2("MostRequestedPriority", priorities.MostRequestedPriorityMap, nil, 1)
factory.RegisterPriorityFunction2(
	"RequestedToCapacityRatioPriority",
	priorities.RequestedToCapacityRatioResourceAllocationPriorityDefault().PriorityMap,
	nil,
	1)
```

# 3. defaultPredicates

此部分为默认预选策略的注册函数。

默认的预选策略如下：

| 预选策略                    | 函数                             | 描述                                                     |
| --------------------------- | -------------------------------- | -------------------------------------------------------- |
| NoVolumeZoneConflictPred    | NewVolumeZonePredicate           | 判断pod使用到的volume是否有节点的要求。目前只支持pvc。   |
| MaxEBSVolumeCountPred       | NewMaxPDVolumeCountPredicate     | 判断pod使用EBSVolume在该节点上是否已经达到上限了。       |
| MaxGCEPDVolumeCountPred     | NewMaxPDVolumeCountPredicate     | 判断pod使用GCEPDVolume在该节点上是否已经达到上限了。     |
| MaxAzureDiskVolumeCountPred | NewMaxPDVolumeCountPredicate     | 判断pod使用AzureDiskVolume在该节点上是否已经达到上限了。 |
| MaxCSIVolumeCountPred       | NewCSIMaxVolumeLimitPredicate    | 判断CSIVolume是否达到上限了。                            |
| MatchInterPodAffinityPred   | NewPodAffinityPredicate          | 匹配pod的亲缘性。                                        |
| NoDiskConflictPred          | NoDiskConflict                   | 判断是否有disk volumes的冲突。                           |
| GeneralPred                 | GeneralPredicates                | 通用的预选策略                                           |
| CheckNodeMemoryPressurePred | CheckNodeMemoryPressurePredicate | 判断节点内存是否充足。                                   |
| CheckNodeDiskPressurePred   | CheckNodeDiskPressurePredicate   | 判断节点是否有磁盘压力。                                 |
| CheckNodePIDPressurePred    | CheckNodePIDPressurePredicate    | 判断节点上的PID                                          |
| CheckNodeConditionPred      | CheckNodeConditionPredicate      | 判断node是否ready。                                      |
| PodToleratesNodeTaintsPred  | PodToleratesNodeTaints           | 判断pod是否可以容忍节点的taints。                        |
| CheckVolumeBindingPred      | NewVolumeBindingPredicate        | 判断是否有volume拓扑的要求。                             |

具体代码如下：

```go
func defaultPredicates() sets.String {
	return sets.NewString(
		// Fit is determined by volume zone requirements.
		factory.RegisterFitPredicateFactory(
			predicates.NoVolumeZoneConflictPred,
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewVolumeZonePredicate(args.PVInfo, args.PVCInfo, args.StorageClassInfo)
			},
		),
		// Fit is determined by whether or not there would be too many AWS EBS volumes attached to the node
		factory.RegisterFitPredicateFactory(
			predicates.MaxEBSVolumeCountPred,
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewMaxPDVolumeCountPredicate(predicates.EBSVolumeFilterType, args.PVInfo, args.PVCInfo)
			},
		),
		// Fit is determined by whether or not there would be too many GCE PD volumes attached to the node
		factory.RegisterFitPredicateFactory(
			predicates.MaxGCEPDVolumeCountPred,
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewMaxPDVolumeCountPredicate(predicates.GCEPDVolumeFilterType, args.PVInfo, args.PVCInfo)
			},
		),
		// Fit is determined by whether or not there would be too many Azure Disk volumes attached to the node
		factory.RegisterFitPredicateFactory(
			predicates.MaxAzureDiskVolumeCountPred,
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewMaxPDVolumeCountPredicate(predicates.AzureDiskVolumeFilterType, args.PVInfo, args.PVCInfo)
			},
		),
		factory.RegisterFitPredicateFactory(
			predicates.MaxCSIVolumeCountPred,
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewCSIMaxVolumeLimitPredicate(args.PVInfo, args.PVCInfo)
			},
		),
		// Fit is determined by inter-pod affinity.
		factory.RegisterFitPredicateFactory(
			predicates.MatchInterPodAffinityPred,
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewPodAffinityPredicate(args.NodeInfo, args.PodLister)
			},
		),

		// Fit is determined by non-conflicting disk volumes.
		factory.RegisterFitPredicate(predicates.NoDiskConflictPred, predicates.NoDiskConflict),

		// GeneralPredicates are the predicates that are enforced by all Kubernetes components
		// (e.g. kubelet and all schedulers)
		factory.RegisterFitPredicate(predicates.GeneralPred, predicates.GeneralPredicates),

		// Fit is determined by node memory pressure condition.
		factory.RegisterFitPredicate(predicates.CheckNodeMemoryPressurePred, predicates.CheckNodeMemoryPressurePredicate),

		// Fit is determined by node disk pressure condition.
		factory.RegisterFitPredicate(predicates.CheckNodeDiskPressurePred, predicates.CheckNodeDiskPressurePredicate),

		// Fit is determined by node pid pressure condition.
		factory.RegisterFitPredicate(predicates.CheckNodePIDPressurePred, predicates.CheckNodePIDPressurePredicate),

		// Fit is determined by node conditions: not ready, network unavailable or out of disk.
		factory.RegisterMandatoryFitPredicate(predicates.CheckNodeConditionPred, predicates.CheckNodeConditionPredicate),

		// Fit is determined based on whether a pod can tolerate all of the node's taints
		factory.RegisterFitPredicate(predicates.PodToleratesNodeTaintsPred, predicates.PodToleratesNodeTaints),

		// Fit is determined by volume topology requirements.
		factory.RegisterFitPredicateFactory(
			predicates.CheckVolumeBindingPred,
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewVolumeBindingPredicate(args.VolumeBinder)
			},
		),
	)
}
```

# 4. defaultPriorities

此部分主要为默认优选策略的注册函数。

默认优选策略如下：

| 优选策略                    | 函数                                    | 描述                                               |
| --------------------------- | --------------------------------------- | -------------------------------------------------- |
| SelectorSpreadPriority      | NewSelectorSpreadPriority               | 属于相同service和rs下的pod尽量分布在不同的node上。 |
| InterPodAffinityPriority    | NewInterPodAffinityPriority             | 根据pod的亲缘性，将相同拓扑域中的pod放在同一个节点 |
| LeastRequestedPriority      | LeastRequestedPriorityMap               | 按最少请求的利用率对节点进行优先级排序。           |
| BalancedResourceAllocation  | BalancedResourceAllocationMap           | 实现资源的平衡使用。                               |
| NodePreferAvoidPodsPriority | CalculateNodePreferAvoidPodsPriorityMap | 将此权重设置为足以覆盖所有其他优先级函数。         |
| NodeAffinityPriority        | CalculateNodeAffinityPriorityMap        | pod指定label节点调度，来匹配node亲缘性。           |
| TaintTolerationPriority     | ComputeTaintTolerationPriorityMap       | pod有设置tolerate属性来容忍node的taint。           |
| ImageLocalityPriority       | ImageLocalityPriorityMap                | 根据节点上是否有该pod使用到的镜像打分。            |

具体代码实现如下：

```go
func defaultPriorities() sets.String {
	return sets.NewString(
		// spreads pods by minimizing the number of pods (belonging to the same service or replication controller) on the same node.
		factory.RegisterPriorityConfigFactory(
			"SelectorSpreadPriority",
			factory.PriorityConfigFactory{
				MapReduceFunction: func(args factory.PluginFactoryArgs) (algorithm.PriorityMapFunction, algorithm.PriorityReduceFunction) {
					return priorities.NewSelectorSpreadPriority(args.ServiceLister, args.ControllerLister, args.ReplicaSetLister, args.StatefulSetLister)
				},
				Weight: 1,
			},
		),
		// pods should be placed in the same topological domain (e.g. same node, same rack, same zone, same power domain, etc.)
		// as some other pods, or, conversely, should not be placed in the same topological domain as some other pods.
		factory.RegisterPriorityConfigFactory(
			"InterPodAffinityPriority",
			factory.PriorityConfigFactory{
				Function: func(args factory.PluginFactoryArgs) algorithm.PriorityFunction {
					return priorities.NewInterPodAffinityPriority(args.NodeInfo, args.NodeLister, args.PodLister, args.HardPodAffinitySymmetricWeight)
				},
				Weight: 1,
			},
		),

		// Prioritize nodes by least requested utilization.
		factory.RegisterPriorityFunction2("LeastRequestedPriority", priorities.LeastRequestedPriorityMap, nil, 1),

		// Prioritizes nodes to help achieve balanced resource usage
		factory.RegisterPriorityFunction2("BalancedResourceAllocation", priorities.BalancedResourceAllocationMap, nil, 1),

		// Set this weight large enough to override all other priority functions.
		// TODO: Figure out a better way to do this, maybe at same time as fixing #24720.
		factory.RegisterPriorityFunction2("NodePreferAvoidPodsPriority", priorities.CalculateNodePreferAvoidPodsPriorityMap, nil, 10000),

		// Prioritizes nodes that have labels matching NodeAffinity
		factory.RegisterPriorityFunction2("NodeAffinityPriority", priorities.CalculateNodeAffinityPriorityMap, priorities.CalculateNodeAffinityPriorityReduce, 1),

		// Prioritizes nodes that marked with taint which pod can tolerate.
		factory.RegisterPriorityFunction2("TaintTolerationPriority", priorities.ComputeTaintTolerationPriorityMap, priorities.ComputeTaintTolerationPriorityReduce, 1),

		// ImageLocalityPriority prioritizes nodes that have images requested by the pod present.
		factory.RegisterPriorityFunction2("ImageLocalityPriority", priorities.ImageLocalityPriorityMap, nil, 1),
	)
}
```



参考：

- https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/scheduler/algorithmprovider/defaults/defaults.go
