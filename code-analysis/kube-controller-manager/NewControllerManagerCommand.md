# kube-controller-manager源码分析（一）之 NewControllerManagerCommand

> 以下代码分析基于 `kubernetes v1.12.0` 版本。
>
> 本文主要分析https://github.com/kubernetes/kubernetes/tree/v1.12.0/cmd/kube-controller-manager 部分的代码。

本文主要分析 `kubernetes/cmd/kube-controller-manager`部分，该部分主要涉及各种类型的`controller`的参数解析，及初始化，例如 `deployment controller` 和`statefulset controller`。并没有具体`controller`运行的详细逻辑，该部分位于`kubernetes/pkg/controller`模块，待后续文章分析。

`kube-controller-manager`的`cmd`部分代码目录结构如下：

```bash
kube-controller-manager
├── app
│   ├── apps.go   # 包含:startDeploymentController、startReplicaSetController、startStatefulSetController、startDaemonSetController
│   ├── autoscaling.go # startHPAController
│   ├── batch.go  # startJobController、startCronJobController
│   ├── bootstrap.go
│   ├── certificates.go
│   ├── cloudproviders.go
│   ├── config
│   │   └── config.go   # config: controller manager执行的上下文
│   ├── controllermanager.go   # 包含:NewControllerManagerCommand、Run、NewControllerInitializers、StartControllers等
│   ├── core.go   # startServiceController、startNodeIpamController、startPersistentVolumeBinderController、startNamespaceController等
│   ├── options    # 包含不同controller的option参数
│   │   ├── attachdetachcontroller.go
│   │   ├── csrsigningcontroller.go
│   │   ├── daemonsetcontroller.go   # DaemonSetControllerOptions
│   │   ├── deploymentcontroller.go  # DeploymentControllerOptions
│   │   ├── deprecatedcontroller.go
│   │   ├── endpointcontroller.go
│   │   ├── garbagecollectorcontroller.go
│   │   ├── hpacontroller.go
│   │   ├── jobcontroller.go
│   │   ├── namespacecontroller.go   # NamespaceControllerOptions
│   │   ├── nodeipamcontroller.go
│   │   ├── nodelifecyclecontroller.go
│   │   ├── options.go  # KubeControllerManagerOptions、NewKubeControllerManagerOptions
│   │   ├── persistentvolumebindercontroller.go
│   │   ├── podgccontroller.go
│   │   ├── replicasetcontroller.go   # ReplicaSetControllerOptions
│   │   ├── replicationcontroller.go
│   │   ├── resourcequotacontroller.go
│   │   ├── serviceaccountcontroller.go
│   │   └── ttlafterfinishedcontroller.go
└── controller-manager.go  # main入口函数
```

# 1. [Main函数](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/controller-manager.go#L41)

`kube-controller-manager`的入口函数`Main`函数，仍然是采用统一的代码风格，使用[Cobra](https://github.com/spf13/cobra)命令行框架。

```go
func main() {
	rand.Seed(time.Now().UTC().UnixNano())

	command := app.NewControllerManagerCommand()

	// TODO: once we switch everything over to Cobra commands, we can go back to calling
	// utilflag.InitFlags() (by removing its pflag.Parse() call). For now, we have to set the
	// normalize func and add the go flag set by hand.
	pflag.CommandLine.SetNormalizeFunc(utilflag.WordSepNormalizeFunc)
	pflag.CommandLine.AddGoFlagSet(goflag.CommandLine)
	// utilflag.InitFlags()
	logs.InitLogs()
	defer logs.FlushLogs()

	if err := command.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
}
```

核心代码：

```go
// 初始化命令行结构体
command := app.NewControllerManagerCommand()
// 执行Execute
err := command.Execute()
```

# 2. [NewControllerManagerCommand](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/controllermanager.go#L77)

该部分代码位于：`kubernetes/cmd/kube-controller-manager/app/controllermanager.go`

```go
// NewControllerManagerCommand creates a *cobra.Command object with default parameters
func NewControllerManagerCommand() *cobra.Command {
	...
	cmd := &cobra.Command{
		Use: "kube-controller-manager",
		Long: `The Kubernetes controller manager is a daemon that embeds
the core control loops shipped with Kubernetes. In applications of robotics and
automation, a control loop is a non-terminating loop that regulates the state of
the system. In Kubernetes, a controller is a control loop that watches the shared
state of the cluster through the apiserver and makes changes attempting to move the
current state towards the desired state. Examples of controllers that ship with
Kubernetes today are the replication controller, endpoints controller, namespace
controller, and serviceaccounts controller.`,
		Run: func(cmd *cobra.Command, args []string) {
			verflag.PrintAndExitIfRequested()
			utilflag.PrintFlags(cmd.Flags())

			c, err := s.Config(KnownControllers(), ControllersDisabledByDefault.List())
			if err != nil {
				fmt.Fprintf(os.Stderr, "%v\n", err)
				os.Exit(1)
			}

			if err := Run(c.Complete(), wait.NeverStop); err != nil {
				fmt.Fprintf(os.Stderr, "%v\n", err)
				os.Exit(1)
			}
		},
	}
    ...
}    
```

构建一个`*cobra.Command`对象，然后执行`Run`函数。

## 2.1. NewKubeControllerManagerOptions

```go
s, err := options.NewKubeControllerManagerOptions()
if err != nil {
	glog.Fatalf("unable to initialize command options: %v", err)
}
```

初始化controllerManager的参数，其中主要包括了各种controller的option，例如`DeploymentControllerOptions`:

```go
// DeploymentControllerOptions holds the DeploymentController options.
type DeploymentControllerOptions struct {
	ConcurrentDeploymentSyncs      int32
	DeploymentControllerSyncPeriod metav1.Duration
}
```

具体代码如下：

```go
// NewKubeControllerManagerOptions creates a new KubeControllerManagerOptions with a default config.
func NewKubeControllerManagerOptions() (*KubeControllerManagerOptions, error) {
	componentConfig, err := NewDefaultComponentConfig(ports.InsecureKubeControllerManagerPort)
	if err != nil {
		return nil, err
	}

	s := KubeControllerManagerOptions{
		Generic:         cmoptions.NewGenericControllerManagerConfigurationOptions(componentConfig.Generic),
		KubeCloudShared: cmoptions.NewKubeCloudSharedOptions(componentConfig.KubeCloudShared),
		AttachDetachController: &AttachDetachControllerOptions{
			ReconcilerSyncLoopPeriod: componentConfig.AttachDetachController.ReconcilerSyncLoopPeriod,
		},
		CSRSigningController: &CSRSigningControllerOptions{
			ClusterSigningCertFile: componentConfig.CSRSigningController.ClusterSigningCertFile,
			ClusterSigningKeyFile:  componentConfig.CSRSigningController.ClusterSigningKeyFile,
			ClusterSigningDuration: componentConfig.CSRSigningController.ClusterSigningDuration,
		},
		DaemonSetController: &DaemonSetControllerOptions{
			ConcurrentDaemonSetSyncs: componentConfig.DaemonSetController.ConcurrentDaemonSetSyncs,
		},
		DeploymentController: &DeploymentControllerOptions{
			ConcurrentDeploymentSyncs:      componentConfig.DeploymentController.ConcurrentDeploymentSyncs,
			DeploymentControllerSyncPeriod: componentConfig.DeploymentController.DeploymentControllerSyncPeriod,
		},
		DeprecatedFlags: &DeprecatedControllerOptions{
			RegisterRetryCount: componentConfig.DeprecatedController.RegisterRetryCount,
		},
		EndpointController: &EndpointControllerOptions{
			ConcurrentEndpointSyncs: componentConfig.EndpointController.ConcurrentEndpointSyncs,
		},
		GarbageCollectorController: &GarbageCollectorControllerOptions{
			ConcurrentGCSyncs:      componentConfig.GarbageCollectorController.ConcurrentGCSyncs,
			EnableGarbageCollector: componentConfig.GarbageCollectorController.EnableGarbageCollector,
		},
		HPAController: &HPAControllerOptions{
			HorizontalPodAutoscalerSyncPeriod:                   componentConfig.HPAController.HorizontalPodAutoscalerSyncPeriod,
			HorizontalPodAutoscalerUpscaleForbiddenWindow:       componentConfig.HPAController.HorizontalPodAutoscalerUpscaleForbiddenWindow,
			HorizontalPodAutoscalerDownscaleForbiddenWindow:     componentConfig.HPAController.HorizontalPodAutoscalerDownscaleForbiddenWindow,
			HorizontalPodAutoscalerDownscaleStabilizationWindow: componentConfig.HPAController.HorizontalPodAutoscalerDownscaleStabilizationWindow,
			HorizontalPodAutoscalerCPUInitializationPeriod:      componentConfig.HPAController.HorizontalPodAutoscalerCPUInitializationPeriod,
			HorizontalPodAutoscalerInitialReadinessDelay:        componentConfig.HPAController.HorizontalPodAutoscalerInitialReadinessDelay,
			HorizontalPodAutoscalerTolerance:                    componentConfig.HPAController.HorizontalPodAutoscalerTolerance,
			HorizontalPodAutoscalerUseRESTClients:               componentConfig.HPAController.HorizontalPodAutoscalerUseRESTClients,
		},
		JobController: &JobControllerOptions{
			ConcurrentJobSyncs: componentConfig.JobController.ConcurrentJobSyncs,
		},
		NamespaceController: &NamespaceControllerOptions{
			NamespaceSyncPeriod:      componentConfig.NamespaceController.NamespaceSyncPeriod,
			ConcurrentNamespaceSyncs: componentConfig.NamespaceController.ConcurrentNamespaceSyncs,
		},
		NodeIPAMController: &NodeIPAMControllerOptions{
			NodeCIDRMaskSize: componentConfig.NodeIPAMController.NodeCIDRMaskSize,
		},
		NodeLifecycleController: &NodeLifecycleControllerOptions{
			EnableTaintManager:     componentConfig.NodeLifecycleController.EnableTaintManager,
			NodeMonitorGracePeriod: componentConfig.NodeLifecycleController.NodeMonitorGracePeriod,
			NodeStartupGracePeriod: componentConfig.NodeLifecycleController.NodeStartupGracePeriod,
			PodEvictionTimeout:     componentConfig.NodeLifecycleController.PodEvictionTimeout,
		},
		PersistentVolumeBinderController: &PersistentVolumeBinderControllerOptions{
			PVClaimBinderSyncPeriod: componentConfig.PersistentVolumeBinderController.PVClaimBinderSyncPeriod,
			VolumeConfiguration:     componentConfig.PersistentVolumeBinderController.VolumeConfiguration,
		},
		PodGCController: &PodGCControllerOptions{
			TerminatedPodGCThreshold: componentConfig.PodGCController.TerminatedPodGCThreshold,
		},
		ReplicaSetController: &ReplicaSetControllerOptions{
			ConcurrentRSSyncs: componentConfig.ReplicaSetController.ConcurrentRSSyncs,
		},
		ReplicationController: &ReplicationControllerOptions{
			ConcurrentRCSyncs: componentConfig.ReplicationController.ConcurrentRCSyncs,
		},
		ResourceQuotaController: &ResourceQuotaControllerOptions{
			ResourceQuotaSyncPeriod:      componentConfig.ResourceQuotaController.ResourceQuotaSyncPeriod,
			ConcurrentResourceQuotaSyncs: componentConfig.ResourceQuotaController.ConcurrentResourceQuotaSyncs,
		},
		SAController: &SAControllerOptions{
			ConcurrentSATokenSyncs: componentConfig.SAController.ConcurrentSATokenSyncs,
		},
		ServiceController: &cmoptions.ServiceControllerOptions{
			ConcurrentServiceSyncs: componentConfig.ServiceController.ConcurrentServiceSyncs,
		},
		TTLAfterFinishedController: &TTLAfterFinishedControllerOptions{
			ConcurrentTTLSyncs: componentConfig.TTLAfterFinishedController.ConcurrentTTLSyncs,
		},
		SecureServing: apiserveroptions.NewSecureServingOptions().WithLoopback(),
		InsecureServing: (&apiserveroptions.DeprecatedInsecureServingOptions{
			BindAddress: net.ParseIP(componentConfig.Generic.Address),
			BindPort:    int(componentConfig.Generic.Port),
			BindNetwork: "tcp",
		}).WithLoopback(),
		Authentication: apiserveroptions.NewDelegatingAuthenticationOptions(),
		Authorization:  apiserveroptions.NewDelegatingAuthorizationOptions(),
	}

	s.Authentication.RemoteKubeConfigFileOptional = true
	s.Authorization.RemoteKubeConfigFileOptional = true
	s.Authorization.AlwaysAllowPaths = []string{"/healthz"}

	s.SecureServing.ServerCert.CertDirectory = "/var/run/kubernetes"
	s.SecureServing.ServerCert.PairName = "kube-controller-manager"
	s.SecureServing.BindPort = ports.KubeControllerManagerPort

	gcIgnoredResources := make([]kubectrlmgrconfig.GroupResource, 0, len(garbagecollector.DefaultIgnoredResources()))
	for r := range garbagecollector.DefaultIgnoredResources() {
		gcIgnoredResources = append(gcIgnoredResources, kubectrlmgrconfig.GroupResource{Group: r.Group, Resource: r.Resource})
	}

	s.GarbageCollectorController.GCIgnoredResources = gcIgnoredResources

	return &s, nil
}
```

## 2.2. AddFlagSet

添加参数及帮助函数。

```go
fs := cmd.Flags()
namedFlagSets := s.Flags(KnownControllers(), ControllersDisabledByDefault.List())
for _, f := range namedFlagSets.FlagSets {
	fs.AddFlagSet(f)
}
usageFmt := "Usage:\n  %s\n"
cols, _, _ := apiserverflag.TerminalSize(cmd.OutOrStdout())
cmd.SetUsageFunc(func(cmd *cobra.Command) error {
	fmt.Fprintf(cmd.OutOrStderr(), usageFmt, cmd.UseLine())
	apiserverflag.PrintSections(cmd.OutOrStderr(), namedFlagSets, cols)
	return nil
})
cmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
	fmt.Fprintf(cmd.OutOrStdout(), "%s\n\n"+usageFmt, cmd.Long, cmd.UseLine())
	apiserverflag.PrintSections(cmd.OutOrStdout(), namedFlagSets, cols)
})
```

# 3. [Run](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/controllermanager.go#L141)

> 此部分的代码位于cmd/kube-controller-manager/app/controllermanager.go

基于`KubeControllerManagerOptions`运行controllerManager，不退出。

```go
// Run runs the KubeControllerManagerOptions.  This should never exit.
func Run(c *config.CompletedConfig, stopCh <-chan struct{}) error {
	...
	run := func(ctx context.Context) {
		...
		controllerContext, err := CreateControllerContext(c, rootClientBuilder, clientBuilder, ctx.Done())
		if err != nil {
			glog.Fatalf("error building controller context: %v", err)
		}
		saTokenControllerInitFunc := serviceAccountTokenControllerStarter{rootClientBuilder: rootClientBuilder}.startServiceAccountTokenController

		if err := StartControllers(controllerContext, saTokenControllerInitFunc, NewControllerInitializers(controllerContext.LoopMode), unsecuredMux); err != nil {
			glog.Fatalf("error starting controllers: %v", err)
		}

		controllerContext.InformerFactory.Start(controllerContext.Stop)
		close(controllerContext.InformersStarted)

		select {}
	}
	...
}
```

Run函数涉及的核心代码如下：

```go
// 创建controller的context
controllerContext, err := CreateControllerContext(c, rootClientBuilder, clientBuilder, ctx.Done())
// 启动各种controller
err := StartControllers(controllerContext, saTokenControllerInitFunc, NewControllerInitializers(controllerContext.LoopMode), unsecuredMux)
```

其中`StartControllers`中的入参`NewControllerInitializers`初始化了各种controller。

## 3.1. CreateControllerContext

`CreateControllerContext`构建了各种controller所需的资源的上下文，各种controller在启动时，入参为该context，具体参考`initFn(ctx)`。

```go
// CreateControllerContext creates a context struct containing references to resources needed by the
// controllers such as the cloud provider and clientBuilder. rootClientBuilder is only used for
// the shared-informers client and token controller.
func CreateControllerContext(s *config.CompletedConfig, rootClientBuilder, clientBuilder controller.ControllerClientBuilder, stop <-chan struct{}) (ControllerContext, error) {
	versionedClient := rootClientBuilder.ClientOrDie("shared-informers")
	sharedInformers := informers.NewSharedInformerFactory(versionedClient, ResyncPeriod(s)())

	// If apiserver is not running we should wait for some time and fail only then. This is particularly
	// important when we start apiserver and controller manager at the same time.
	if err := genericcontrollermanager.WaitForAPIServer(versionedClient, 10*time.Second); err != nil {
		return ControllerContext{}, fmt.Errorf("failed to wait for apiserver being healthy: %v", err)
	}

	// Use a discovery client capable of being refreshed.
	discoveryClient := rootClientBuilder.ClientOrDie("controller-discovery")
	cachedClient := cacheddiscovery.NewMemCacheClient(discoveryClient.Discovery())
	restMapper := restmapper.NewDeferredDiscoveryRESTMapper(cachedClient)
	go wait.Until(func() {
		restMapper.Reset()
	}, 30*time.Second, stop)

	availableResources, err := GetAvailableResources(rootClientBuilder)
	if err != nil {
		return ControllerContext{}, err
	}

	cloud, loopMode, err := createCloudProvider(s.ComponentConfig.KubeCloudShared.CloudProvider.Name, s.ComponentConfig.KubeCloudShared.ExternalCloudVolumePlugin,
		s.ComponentConfig.KubeCloudShared.CloudProvider.CloudConfigFile, s.ComponentConfig.KubeCloudShared.AllowUntaggedCloud, sharedInformers)
	if err != nil {
		return ControllerContext{}, err
	}

	ctx := ControllerContext{
		ClientBuilder:      clientBuilder,
		InformerFactory:    sharedInformers,
		ComponentConfig:    s.ComponentConfig,
		RESTMapper:         restMapper,
		AvailableResources: availableResources,
		Cloud:              cloud,
		LoopMode:           loopMode,
		Stop:               stop,
		InformersStarted:   make(chan struct{}),
		ResyncPeriod:       ResyncPeriod(s),
	}
	return ctx, nil
}
```

核心代码为`NewSharedInformerFactory`。

```go
// 创建SharedInformerFactory
sharedInformers := informers.NewSharedInformerFactory(versionedClient, ResyncPeriod(s)())
// 赋值给ControllerContext
ctx := ControllerContext{
	InformerFactory:    sharedInformers,
}
```

`SharedInformerFactory`提供了公共的k8s对象的`informers`。

```go
// SharedInformerFactory provides shared informers for resources in all known
// API group versions.
type SharedInformerFactory interface {
	internalinterfaces.SharedInformerFactory
	ForResource(resource schema.GroupVersionResource) (GenericInformer, error)
	WaitForCacheSync(stopCh <-chan struct{}) map[reflect.Type]bool

	Admissionregistration() admissionregistration.Interface
	Apps() apps.Interface
	Autoscaling() autoscaling.Interface
	Batch() batch.Interface
	Certificates() certificates.Interface
	Coordination() coordination.Interface
	Core() core.Interface
	Events() events.Interface
	Extensions() extensions.Interface
	Networking() networking.Interface
	Policy() policy.Interface
	Rbac() rbac.Interface
	Scheduling() scheduling.Interface
	Settings() settings.Interface
	Storage() storage.Interface
}
```

## 3.2. NewControllerInitializers

`NewControllerInitializers`定义了各种controller的类型和其对于的启动函数，例如`deployment``、statefulset`、`replicaset`、`replicationcontroller`、`namespace`等。

```go
// NewControllerInitializers is a public map of named controller groups (you can start more than one in an init func)
// paired to their InitFunc.  This allows for structured downstream composition and subdivision.
func NewControllerInitializers(loopMode ControllerLoopMode) map[string]InitFunc {
	controllers := map[string]InitFunc{}
	controllers["endpoint"] = startEndpointController
	controllers["replicationcontroller"] = startReplicationController
	controllers["podgc"] = startPodGCController
	controllers["resourcequota"] = startResourceQuotaController
	controllers["namespace"] = startNamespaceController
	controllers["serviceaccount"] = startServiceAccountController
	controllers["garbagecollector"] = startGarbageCollectorController
	controllers["daemonset"] = startDaemonSetController
	controllers["job"] = startJobController
	controllers["deployment"] = startDeploymentController
	controllers["replicaset"] = startReplicaSetController
	controllers["horizontalpodautoscaling"] = startHPAController
	controllers["disruption"] = startDisruptionController
	controllers["statefulset"] = startStatefulSetController
	controllers["cronjob"] = startCronJobController
	controllers["csrsigning"] = startCSRSigningController
	controllers["csrapproving"] = startCSRApprovingController
	controllers["csrcleaner"] = startCSRCleanerController
	controllers["ttl"] = startTTLController
	controllers["bootstrapsigner"] = startBootstrapSignerController
	controllers["tokencleaner"] = startTokenCleanerController
	controllers["nodeipam"] = startNodeIpamController
	if loopMode == IncludeCloudLoops {
		controllers["service"] = startServiceController
		controllers["route"] = startRouteController
		// TODO: volume controller into the IncludeCloudLoops only set.
		// TODO: Separate cluster in cloud check from node lifecycle controller.
	}
	controllers["nodelifecycle"] = startNodeLifecycleController
	controllers["persistentvolume-binder"] = startPersistentVolumeBinderController
	controllers["attachdetach"] = startAttachDetachController
	controllers["persistentvolume-expander"] = startVolumeExpandController
	controllers["clusterrole-aggregation"] = startClusterRoleAggregrationController
	controllers["pvc-protection"] = startPVCProtectionController
	controllers["pv-protection"] = startPVProtectionController
	controllers["ttl-after-finished"] = startTTLAfterFinishedController

	return controllers
}
```

## 3.3. StartControllers

```go
func StartControllers(ctx ControllerContext, startSATokenController InitFunc, controllers map[string]InitFunc, unsecuredMux *mux.PathRecorderMux) error {
	...
	for controllerName, initFn := range controllers {
		if !ctx.IsControllerEnabled(controllerName) {
			glog.Warningf("%q is disabled", controllerName)
			continue
		}
		time.Sleep(wait.Jitter(ctx.ComponentConfig.Generic.ControllerStartInterval.Duration, ControllerStartJitter))

		glog.V(1).Infof("Starting %q", controllerName)
		debugHandler, started, err := initFn(ctx)
		if err != nil {
			glog.Errorf("Error starting %q", controllerName)
			return err
		}
		if !started {
			glog.Warningf("Skipping %q", controllerName)
			continue
		}
		if debugHandler != nil && unsecuredMux != nil {
			basePath := "/debug/controllers/" + controllerName
			unsecuredMux.UnlistedHandle(basePath, http.StripPrefix(basePath, debugHandler))
			unsecuredMux.UnlistedHandlePrefix(basePath+"/", http.StripPrefix(basePath, debugHandler))
		}
		glog.Infof("Started %q", controllerName)
	}

	return nil
}
```

核心代码：

```go
for controllerName, initFn := range controllers {
	debugHandler, started, err := initFn(ctx)
}   
```

启动各种controller，controller的启动函数在`NewControllerInitializers`中定义了，例如：

```go
// deployment
controllers["deployment"] = startDeploymentController
// statefulset
controllers["statefulset"] = startStatefulSetController
```

## 3.4. InformerFactory.Start

`InformerFactory`实际上是`SharedInformerFactory`，具体的实现逻辑在`client-go`中的informer的实现机制。

```go
controllerContext.InformerFactory.Start(controllerContext.Stop)
close(controllerContext.InformersStarted)
```

### 3.4.1. SharedInformerFactory

SharedInformerFactory是一个informer工厂的接口定义。

```go
// SharedInformerFactory a small interface to allow for adding an informer without an import cycle
type SharedInformerFactory interface {
	Start(stopCh <-chan struct{})
	InformerFor(obj runtime.Object, newFunc NewInformerFunc) cache.SharedIndexInformer
}
```

### 3.4.2. sharedInformerFactory.Start

Start方法初始化各种类型的informer

```go
// Start initializes all requested informers.
func (f *sharedInformerFactory) Start(stopCh <-chan struct{}) {
	f.lock.Lock()
	defer f.lock.Unlock()

	for informerType, informer := range f.informers {
		if !f.startedInformers[informerType] {
			go informer.Run(stopCh)
			f.startedInformers[informerType] = true
		}
	}
}
```

### 3.4.3. sharedIndexInformer.Run

sharedIndexInformer.Run具体运行了sharedIndexInformer的实现逻辑，该部分待后续对informer机制做专题分析。

```go
func (s *sharedIndexInformer) Run(stopCh <-chan struct{}) {
	defer utilruntime.HandleCrash()

	fifo := NewDeltaFIFO(MetaNamespaceKeyFunc, nil, s.indexer)

	cfg := &Config{
		Queue:            fifo,
		ListerWatcher:    s.listerWatcher,
		ObjectType:       s.objectType,
		FullResyncPeriod: s.resyncCheckPeriod,
		RetryOnError:     false,
		ShouldResync:     s.processor.shouldResync,

		Process: s.HandleDeltas,
	}

	func() {
		s.startedLock.Lock()
		defer s.startedLock.Unlock()

		s.controller = New(cfg)
		s.controller.(*controller).clock = s.clock
		s.started = true
	}()

	// Separate stop channel because Processor should be stopped strictly after controller
	processorStopCh := make(chan struct{})
	var wg wait.Group
	defer wg.Wait()              // Wait for Processor to stop
	defer close(processorStopCh) // Tell Processor to stop
	wg.StartWithChannel(processorStopCh, s.cacheMutationDetector.Run)
	wg.StartWithChannel(processorStopCh, s.processor.run)

	defer func() {
		s.startedLock.Lock()
		defer s.startedLock.Unlock()
		s.stopped = true // Don't want any new listeners
	}()
	s.controller.Run(stopCh)
}
```

# 4. initFn(ctx)

`initFn`实际调用的就是各种类型的controller，代码位于`kubernetes/cmd/kube-controller-manager/app/apps.go`，本文以`startStatefulSetController`和`startDeploymentController`为例，controller中实际调用的函数逻辑位于`kubernetes/pkg/controller`中，待后续分析。

## 4.1. [startStatefulSetController](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/apps.go#L55)

```go
func startStatefulSetController(ctx ControllerContext) (http.Handler, bool, error) {
	if !ctx.AvailableResources[schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "statefulsets"}] {
		return nil, false, nil
	}
	go statefulset.NewStatefulSetController(
		ctx.InformerFactory.Core().V1().Pods(),
		ctx.InformerFactory.Apps().V1().StatefulSets(),
		ctx.InformerFactory.Core().V1().PersistentVolumeClaims(),
		ctx.InformerFactory.Apps().V1().ControllerRevisions(),
		ctx.ClientBuilder.ClientOrDie("statefulset-controller"),
	).Run(1, ctx.Stop)
	return nil, true, nil
}
```

其中使用到了`InformerFactory`，包含了Pods、StatefulSets、PersistentVolumeClaims、ControllerRevisions的informer。

`startStatefulSetController`主要调用的函数为`NewStatefulSetController`和对应的`Run`函数。

## 4.2. [startDeploymentController](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/apps.go#L82)

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

# 5. 总结

1. Kube-controller-manager的代码风格仍然是[Cobra](https://github.com/spf13/cobra)命令行框架。通过构造`ControllerManagerCommand`，然后执行`command.Execute()`函数。基本的流程就是构造option，添加Flags，执行Run函数。
2. cmd部分的调用流程如下：`Main-->NewControllerManagerCommand--> Run(c.Complete(), wait.NeverStop)-->StartControllers-->initFn(ctx)-->startDeploymentController/startStatefulSetController-->sts.NewStatefulSetController.Run/dc.NewDeploymentController.Run-->pkg/controller`。
3. 其中`CreateControllerContext`函数用来创建各类型controller所需要使用的context，`NewControllerInitializers`初始化了各种类型的controller，其中就包括`DeploymentController`和`StatefulSetController`等。



基本流程如下：

1. 构造controller manager option，并转化为Config对象，执行Run函数。
2. 基于Config对象创建ControllerContext，其中包含InformerFactory。
3. 基于ControllerContext运行各种controller，各种controller的定义在`NewControllerInitializers`中。
4. 执行InformerFactory.Start。
5. 每种controller都会构造自身的结构体并执行对应的Run函数。



参考：

- https://github.com/kubernetes/kubernetes/tree/v1.12.0/cmd/kube-controller-manager
- https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/controller-manager.go
- https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/controllermanager.go
- https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-controller-manager/app/apps.go
