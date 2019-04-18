# kubelet源码分析（一）之 NewKubeletCommand

> 以下代码分析基于 `kubernetes v1.12.0` 版本。
>
> 本文主要分析 https://github.com/kubernetes/kubernetes/tree/v1.12.0/cmd/kubelet 部分的代码。

本文主要分析 `kubernetes/cmd/kubelet`部分，该部分主要涉及`kubelet`的参数解析，及初始化和构造相关的依赖组件（主要在`kubeDeps`结构体中），并没有`kubelet`运行的详细逻辑，该部分位于`kubernetes/pkg/kubelet`模块，待后续文章分析。

`kubelet`的`cmd`代码目录结构如下：

```bash
kubelet
├── app
│   ├── auth.go
│   ├── init_others.go
│   ├── init_windows.go
│   ├── options              # 包括kubelet使用到的option
│   │   ├── container_runtime.go
│   │   ├── globalflags.go
│   │   ├── globalflags_linux.go
│   │   ├── globalflags_other.go
│   │   ├── options.go     # 包括KubeletFlags、AddFlags、AddKubeletConfigFlags等
│   │   ├── osflags_others.go
│   │   └── osflags_windows.go
│   ├── plugins.go
│   ├── server.go # 包括NewKubeletCommand、Run、RunKubelet、CreateAndInitKubelet、startKubelet等
│   ├── server_linux.go
│   └── server_unsupported.go
└── kubelet.go              # kubelet的main入口函数
```

# 1. [Main 函数](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/kubelet.go#L36)

`kubelet`的入口函数` Main` 函数，具体代码参考：https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/kubelet.go。 

```go
func main() {
	rand.Seed(time.Now().UTC().UnixNano())

	command := app.NewKubeletCommand(server.SetupSignalHandler())
	logs.InitLogs()
	defer logs.FlushLogs()

	if err := command.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
}
```

kubelet代码主要采用了[Cobra](https://github.com/spf13/cobra)命令行框架，核心代码如下：

```go
// 初始化命令行
command := app.NewKubeletCommand(server.SetupSignalHandler())
// 执行Execute
err := command.Execute()
```

# 2. [NewKubeletCommand](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/app/server.go#L108)

`NewKubeletCommand`基于参数创建了一个`*cobra.Command`对象。其中核心部分代码为参数解析部分和`Run`函数。

```go
// NewKubeletCommand creates a *cobra.Command object with default parameters
func NewKubeletCommand(stopCh <-chan struct{}) *cobra.Command {
	...
	cmd := &cobra.Command{
		Use: componentKubelet,
		Long: `...`,
		// The Kubelet has special flag parsing requirements to enforce flag precedence rules,
		// so we do all our parsing manually in Run, below.
		// DisableFlagParsing=true provides the full set of flags passed to the kubelet in the
		// `args` arg to Run, without Cobra's interference.
		DisableFlagParsing: true,
		Run: func(cmd *cobra.Command, args []string) {
			...
			// run the kubelet
			glog.V(5).Infof("KubeletConfiguration: %#v", kubeletServer.KubeletConfiguration)
			if err := Run(kubeletServer, kubeletDeps, stopCh); err != nil {
				glog.Fatal(err)
			}
		},
	}
	...
	return cmd
}
```

## 2.1. 参数解析

kubelet开启了`DisableFlagParsing`参数，没有使用`Cobra`框架中的默认参数解析，而是自定义参数解析。

### 2.1.1. 初始化参数和配置

初始化参数解析，初始化`cleanFlagSet`，`kubeletFlags`，`kubeletConfig`。

```go
cleanFlagSet := pflag.NewFlagSet(componentKubelet, pflag.ContinueOnError)
cleanFlagSet.SetNormalizeFunc(flag.WordSepNormalizeFunc)
kubeletFlags := options.NewKubeletFlags()
kubeletConfig, err := options.NewKubeletConfiguration()
```

### 2.1.2. 打印帮助信息和版本信息

如果输入非法参数则打印使用帮助信息。

```go
// initial flag parse, since we disable cobra's flag parsing
if err := cleanFlagSet.Parse(args); err != nil {
	cmd.Usage()
	glog.Fatal(err)
}

// check if there are non-flag arguments in the command line
cmds := cleanFlagSet.Args()
if len(cmds) > 0 {
	cmd.Usage()
	glog.Fatalf("unknown command: %s", cmds[0])
}
```

遇到`help`和`version`参数则打印相关内容并退出。

```go
// short-circuit on help
help, err := cleanFlagSet.GetBool("help")
if err != nil {
	glog.Fatal(`"help" flag is non-bool, programmer error, please correct`)
}
if help {
	cmd.Help()
	return
}

// short-circuit on verflag
verflag.PrintAndExitIfRequested()
utilflag.PrintFlags(cleanFlagSet)
```

### 2.1.3. kubelet config

加载并校验`kubelet config`。其中包括校验初始化的`kubeletFlags`，并从`kubeletFlags`的`KubeletConfigFile`参数获取`kubelet config`的内容。

```go
// set feature gates from initial flags-based config
if err := utilfeature.DefaultFeatureGate.SetFromMap(kubeletConfig.FeatureGates); err != nil {
	glog.Fatal(err)
}

// validate the initial KubeletFlags
if err := options.ValidateKubeletFlags(kubeletFlags); err != nil {
	glog.Fatal(err)
}

if kubeletFlags.ContainerRuntime == "remote" && cleanFlagSet.Changed("pod-infra-container-image") {
	glog.Warning("Warning: For remote container runtime, --pod-infra-container-image is ignored in kubelet, which should be set in that remote runtime instead")
}

// load kubelet config file, if provided
if configFile := kubeletFlags.KubeletConfigFile; len(configFile) > 0 {
	kubeletConfig, err = loadConfigFile(configFile)
	if err != nil {
		glog.Fatal(err)
	}
	// We must enforce flag precedence by re-parsing the command line into the new object.
	// This is necessary to preserve backwards-compatibility across binary upgrades.
	// See issue #56171 for more details.
	if err := kubeletConfigFlagPrecedence(kubeletConfig, args); err != nil {
		glog.Fatal(err)
	}
	// update feature gates based on new config
	if err := utilfeature.DefaultFeatureGate.SetFromMap(kubeletConfig.FeatureGates); err != nil {
		glog.Fatal(err)
	}
}

// We always validate the local configuration (command line + config file).
// This is the default "last-known-good" config for dynamic config, and must always remain valid.
if err := kubeletconfigvalidation.ValidateKubeletConfiguration(kubeletConfig); err != nil {
	glog.Fatal(err)
}
```

### 2.1.4. dynamic kubelet config

如果开启使用动态kubelet的配置，则由动态配置文件替换kubelet配置文件。

```go
// use dynamic kubelet config, if enabled
var kubeletConfigController *dynamickubeletconfig.Controller
if dynamicConfigDir := kubeletFlags.DynamicConfigDir.Value(); len(dynamicConfigDir) > 0 {
	var dynamicKubeletConfig *kubeletconfiginternal.KubeletConfiguration
	dynamicKubeletConfig, kubeletConfigController, err = BootstrapKubeletConfigController(dynamicConfigDir,
		func(kc *kubeletconfiginternal.KubeletConfiguration) error {
			// Here, we enforce flag precedence inside the controller, prior to the controller's validation sequence,
			// so that we get a complete validation at the same point where we can decide to reject dynamic config.
			// This fixes the flag-precedence component of issue #63305.
			// See issue #56171 for general details on flag precedence.
			return kubeletConfigFlagPrecedence(kc, args)
		})
	if err != nil {
		glog.Fatal(err)
	}
	// If we should just use our existing, local config, the controller will return a nil config
	if dynamicKubeletConfig != nil {
		kubeletConfig = dynamicKubeletConfig
		// Note: flag precedence was already enforced in the controller, prior to validation,
		// by our above transform function. Now we simply update feature gates from the new config.
		if err := utilfeature.DefaultFeatureGate.SetFromMap(kubeletConfig.FeatureGates); err != nil {
			glog.Fatal(err)
		}
	}
}
```

总结：以上通过对各种特定参数的解析，最终生成`kubeletFlags`和`kubeletConfig`两个重要的参数对象，用来构造`kubeletServer`和其他需求。

## 2.2. 初始化kubeletServer和kubeletDeps

### 2.2.1. kubeletServer

```go
// construct a KubeletServer from kubeletFlags and kubeletConfig
kubeletServer := &options.KubeletServer{
	KubeletFlags:         *kubeletFlags,
	KubeletConfiguration: *kubeletConfig,
}
```

### 2.2.2. kubeletDeps

```go
// use kubeletServer to construct the default KubeletDeps
kubeletDeps, err := UnsecuredDependencies(kubeletServer)
if err != nil {
	glog.Fatal(err)
}

// add the kubelet config controller to kubeletDeps
kubeletDeps.KubeletConfigController = kubeletConfigController
```

### 2.2.3. docker shim

如果开启了docker shim参数，则执行`RunDockershim`。

```go
// start the experimental docker shim, if enabled
if kubeletServer.KubeletFlags.ExperimentalDockershim {
	if err := RunDockershim(&kubeletServer.KubeletFlags, kubeletConfig, stopCh); err != nil {
		glog.Fatal(err)
	}
	return
}
```

## 2.3. AddFlags

```go
// keep cleanFlagSet separate, so Cobra doesn't pollute it with the global flags
kubeletFlags.AddFlags(cleanFlagSet)
options.AddKubeletConfigFlags(cleanFlagSet, kubeletConfig)
options.AddGlobalFlags(cleanFlagSet)
cleanFlagSet.BoolP("help", "h", false, fmt.Sprintf("help for %s", cmd.Name()))

// ugly, but necessary, because Cobra's default UsageFunc and HelpFunc pollute the flagset with global flags
const usageFmt = "Usage:\n  %s\n\nFlags:\n%s"
cmd.SetUsageFunc(func(cmd *cobra.Command) error {
	fmt.Fprintf(cmd.OutOrStderr(), usageFmt, cmd.UseLine(), cleanFlagSet.FlagUsagesWrapped(2))
	return nil
})
cmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
	fmt.Fprintf(cmd.OutOrStdout(), "%s\n\n"+usageFmt, cmd.Long, cmd.UseLine(), cleanFlagSet.FlagUsagesWrapped(2))
})
```

其中：

- `AddFlags`代码可参考：[kubernetes/cmd/kubelet/app/options/options.go#L323](https://github.com/kubernetes/kubernetes/blob/0ed33881dc4355495f623c6f22e7dd0b7632b7c0/cmd/kubelet/app/options/options.go#L323)
- `AddKubeletConfigFlags`代码可参考：[kubernetes/cmd/kubelet/app/options/options.go#L424](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/app/options/options.go#L424)

## 2.4. 运行kubelet

运行kubelet并且不退出。由Run函数进入后续的操作。

```go
// run the kubelet
glog.V(5).Infof("KubeletConfiguration: %#v", kubeletServer.KubeletConfiguration)
if err := Run(kubeletServer, kubeletDeps, stopCh); err != nil {
	glog.Fatal(err)
}
```

# 3. [Run](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/app/server.go#L406)

```go
// Run runs the specified KubeletServer with the given Dependencies. This should never exit.
// The kubeDeps argument may be nil - if so, it is initialized from the settings on KubeletServer.
// Otherwise, the caller is assumed to have set up the Dependencies object and a default one will
// not be generated.
func Run(s *options.KubeletServer, kubeDeps *kubelet.Dependencies, stopCh <-chan struct{}) error {
	// To help debugging, immediately log version
	glog.Infof("Version: %+v", version.Get())
	if err := initForOS(s.KubeletFlags.WindowsService); err != nil {
		return fmt.Errorf("failed OS init: %v", err)
	}
	if err := run(s, kubeDeps, stopCh); err != nil {
		return fmt.Errorf("failed to run Kubelet: %v", err)
	}
	return nil
}
```

当运行环境是Windows的时候，初始化操作，但是该操作为空，只是预留。具体执行`run(s, kubeDeps, stopCh)`函数。

## 3.1. 构造kubeDeps

### 3.1.1. clientConfig

创建`clientConfig`，该对象用来创建各种的`kubeDeps`属性中包含的`client`。

```go
clientConfig, err := createAPIServerClientConfig(s)
if err != nil {
	return fmt.Errorf("invalid kubeconfig: %v", err)
}
```

### 3.1.2. kubeClient

```go
kubeClient, err = clientset.NewForConfig(clientConfig)
if err != nil {
	glog.Warningf("New kubeClient from clientConfig error: %v", err)
} else if kubeClient.CertificatesV1beta1() != nil && clientCertificateManager != nil {
	glog.V(2).Info("Starting client certificate rotation.")
	clientCertificateManager.SetCertificateSigningRequestClient(kubeClient.CertificatesV1beta1().CertificateSigningRequests())
	clientCertificateManager.Start()
}
```

### 3.1.3. dynamicKubeClient

```GO
dynamicKubeClient, err = dynamic.NewForConfig(clientConfig)
if err != nil {
	glog.Warningf("Failed to initialize dynamic KubeClient: %v", err)
}
```

### 3.1.4. eventClient

```GO
// make a separate client for events
eventClientConfig := *clientConfig
eventClientConfig.QPS = float32(s.EventRecordQPS)
eventClientConfig.Burst = int(s.EventBurst)
eventClient, err = v1core.NewForConfig(&eventClientConfig)
if err != nil {
	glog.Warningf("Failed to create API Server client for Events: %v", err)
}
```

### 3.1.5. heartbeatClient

```go
// make a separate client for heartbeat with throttling disabled and a timeout attached
heartbeatClientConfig := *clientConfig
heartbeatClientConfig.Timeout = s.KubeletConfiguration.NodeStatusUpdateFrequency.Duration
// if the NodeLease feature is enabled, the timeout is the minimum of the lease duration and status update frequency
if utilfeature.DefaultFeatureGate.Enabled(features.NodeLease) {
	leaseTimeout := time.Duration(s.KubeletConfiguration.NodeLeaseDurationSeconds) * time.Second
	if heartbeatClientConfig.Timeout > leaseTimeout {
		heartbeatClientConfig.Timeout = leaseTimeout
	}
}
heartbeatClientConfig.QPS = float32(-1)
heartbeatClient, err = clientset.NewForConfig(&heartbeatClientConfig)
if err != nil {
	glog.Warningf("Failed to create API Server client for heartbeat: %v", err)
}
```

### 3.1.6. csiClient

```go
// csiClient works with CRDs that support json only
clientConfig.ContentType = "application/json"
csiClient, err := csiclientset.NewForConfig(clientConfig)
if err != nil {
	glog.Warningf("Failed to create CSI API client: %v", err)
}
```

**client赋值**

```go
kubeDeps.KubeClient = kubeClient
kubeDeps.DynamicKubeClient = dynamicKubeClient
if heartbeatClient != nil {
	kubeDeps.HeartbeatClient = heartbeatClient
	kubeDeps.OnHeartbeatFailure = closeAllConns
}
if eventClient != nil {
	kubeDeps.EventClient = eventClient
}
kubeDeps.CSIClient = csiClient
```

### 3.1.7. CAdvisorInterface

```go
if kubeDeps.CAdvisorInterface == nil {
	imageFsInfoProvider := cadvisor.NewImageFsInfoProvider(s.ContainerRuntime, s.RemoteRuntimeEndpoint)
	kubeDeps.CAdvisorInterface, err = cadvisor.New(imageFsInfoProvider, s.RootDirectory, cadvisor.UsingLegacyCadvisorStats(s.ContainerRuntime, s.RemoteRuntimeEndpoint))
	if err != nil {
		return err
	}
}
```

### 3.1.8. ContainerManager

```go
if kubeDeps.ContainerManager == nil {
	if s.CgroupsPerQOS && s.CgroupRoot == "" {
		glog.Infof("--cgroups-per-qos enabled, but --cgroup-root was not specified.  defaulting to /")
		s.CgroupRoot = "/"
	}
	kubeReserved, err := parseResourceList(s.KubeReserved)
	if err != nil {
		return err
	}
	systemReserved, err := parseResourceList(s.SystemReserved)
	if err != nil {
		return err
	}
	var hardEvictionThresholds []evictionapi.Threshold
	// If the user requested to ignore eviction thresholds, then do not set valid values for hardEvictionThresholds here.
	if !s.ExperimentalNodeAllocatableIgnoreEvictionThreshold {
		hardEvictionThresholds, err = eviction.ParseThresholdConfig([]string{}, s.EvictionHard, nil, nil, nil)
		if err != nil {
			return err
		}
	}
	experimentalQOSReserved, err := cm.ParseQOSReserved(s.QOSReserved)
	if err != nil {
		return err
	}

	devicePluginEnabled := utilfeature.DefaultFeatureGate.Enabled(features.DevicePlugins)

	kubeDeps.ContainerManager, err = cm.NewContainerManager(
		kubeDeps.Mounter,
		kubeDeps.CAdvisorInterface,
		cm.NodeConfig{
			RuntimeCgroupsName:    s.RuntimeCgroups,
			SystemCgroupsName:     s.SystemCgroups,
			KubeletCgroupsName:    s.KubeletCgroups,
			ContainerRuntime:      s.ContainerRuntime,
			CgroupsPerQOS:         s.CgroupsPerQOS,
			CgroupRoot:            s.CgroupRoot,
			CgroupDriver:          s.CgroupDriver,
			KubeletRootDir:        s.RootDirectory,
			ProtectKernelDefaults: s.ProtectKernelDefaults,
			NodeAllocatableConfig: cm.NodeAllocatableConfig{
				KubeReservedCgroupName:   s.KubeReservedCgroup,
				SystemReservedCgroupName: s.SystemReservedCgroup,
				EnforceNodeAllocatable:   sets.NewString(s.EnforceNodeAllocatable...),
				KubeReserved:             kubeReserved,
				SystemReserved:           systemReserved,
				HardEvictionThresholds:   hardEvictionThresholds,
			},
			QOSReserved:                           *experimentalQOSReserved,
			ExperimentalCPUManagerPolicy:          s.CPUManagerPolicy,
			ExperimentalCPUManagerReconcilePeriod: s.CPUManagerReconcilePeriod.Duration,
			ExperimentalPodPidsLimit:              s.PodPidsLimit,
			EnforceCPULimits:                      s.CPUCFSQuota,
			CPUCFSQuotaPeriod:                     s.CPUCFSQuotaPeriod.Duration,
		},
		s.FailSwapOn,
		devicePluginEnabled,
		kubeDeps.Recorder)

	if err != nil {
		return err
	}
}
```

### 3.1.9. oomAdjuster

```go
// TODO(vmarmol): Do this through container config.
oomAdjuster := kubeDeps.OOMAdjuster
if err := oomAdjuster.ApplyOOMScoreAdj(0, int(s.OOMScoreAdj)); err != nil {
	glog.Warning(err)
}
```

## 3.2. Health check

```go
if s.HealthzPort > 0 {
	healthz.DefaultHealthz()
	go wait.Until(func() {
		err := http.ListenAndServe(net.JoinHostPort(s.HealthzBindAddress, strconv.Itoa(int(s.HealthzPort))), nil)
		if err != nil {
			glog.Errorf("Starting health server failed: %v", err)
		}
	}, 5*time.Second, wait.NeverStop)
}
```

## 3.3. RunKubelet

通过各种赋值构造了完整的`kubeDeps`结构体，最后再执行`RunKubelet`转入后续的kubelet执行流程。

```go
if err := RunKubelet(s, kubeDeps, s.RunOnce); err != nil {
	return err
}
```

# 4. [RunKubelet](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kubelet/app/server.go#L914)

```go
// RunKubelet is responsible for setting up and running a kubelet.  It is used in three different applications:
//   1 Integration tests
//   2 Kubelet binary
//   3 Standalone 'kubernetes' binary
// Eventually, #2 will be replaced with instances of #3
func RunKubelet(kubeServer *options.KubeletServer, kubeDeps *kubelet.Dependencies, runOnce bool) error {
	...
	k, err := CreateAndInitKubelet(&kubeServer.KubeletConfiguration,
		...
		kubeServer.NodeStatusMaxImages)
	if err != nil {
		return fmt.Errorf("failed to create kubelet: %v", err)
	}

	// NewMainKubelet should have set up a pod source config if one didn't exist
	// when the builder was run. This is just a precaution.
	if kubeDeps.PodConfig == nil {
		return fmt.Errorf("failed to create kubelet, pod source config was nil")
	}
	podCfg := kubeDeps.PodConfig

	rlimit.RlimitNumFiles(uint64(kubeServer.MaxOpenFiles))

	// process pods and exit.
	if runOnce {
		if _, err := k.RunOnce(podCfg.Updates()); err != nil {
			return fmt.Errorf("runonce failed: %v", err)
		}
		glog.Infof("Started kubelet as runonce")
	} else {
		startKubelet(k, podCfg, &kubeServer.KubeletConfiguration, kubeDeps, kubeServer.EnableServer)
		glog.Infof("Started kubelet")
	}
	return nil
}  
```

`RunKubelet`函数核心代码为执行了`CreateAndInitKubelet`和`startKubelet`两个函数的操作，以下对这两个函数进行分析。

## 4.1. CreateAndInitKubelet

通过传入`kubeDeps`调用`CreateAndInitKubelet`初始化Kubelet。

```go
k, err := CreateAndInitKubelet(&kubeServer.KubeletConfiguration,
	kubeDeps,
	&kubeServer.ContainerRuntimeOptions,
	kubeServer.ContainerRuntime,
	kubeServer.RuntimeCgroups,
	kubeServer.HostnameOverride,
	kubeServer.NodeIP,
	kubeServer.ProviderID,
	kubeServer.CloudProvider,
	kubeServer.CertDirectory,
	kubeServer.RootDirectory,
	kubeServer.RegisterNode,
	kubeServer.RegisterWithTaints,
	kubeServer.AllowedUnsafeSysctls,
	kubeServer.RemoteRuntimeEndpoint,
	kubeServer.RemoteImageEndpoint,
	kubeServer.ExperimentalMounterPath,
	kubeServer.ExperimentalKernelMemcgNotification,
	kubeServer.ExperimentalCheckNodeCapabilitiesBeforeMount,
	kubeServer.ExperimentalNodeAllocatableIgnoreEvictionThreshold,
	kubeServer.MinimumGCAge,
	kubeServer.MaxPerPodContainerCount,
	kubeServer.MaxContainerCount,
	kubeServer.MasterServiceNamespace,
	kubeServer.RegisterSchedulable,
	kubeServer.NonMasqueradeCIDR,
	kubeServer.KeepTerminatedPodVolumes,
	kubeServer.NodeLabels,
	kubeServer.SeccompProfileRoot,
	kubeServer.BootstrapCheckpointPath,
	kubeServer.NodeStatusMaxImages)
if err != nil {
	return fmt.Errorf("failed to create kubelet: %v", err)
}
```

### 4.1.1. NewMainKubelet

`CreateAndInitKubelet`方法中执行的核心函数是`NewMainKubelet`，`NewMainKubelet`实例化一个`kubelet`对象，该部分的具体代码在`kubernetes/pkg/kubelet`中，具体参考：[kubernetes/pkg/kubelet/kubelet.go#L325](https://github.com/kubernetes/kubernetes/blob/0ed33881dc4355495f623c6f22e7dd0b7632b7c0/pkg/kubelet/kubelet.go#L325)。

```go
func CreateAndInitKubelet(kubeCfg *kubeletconfiginternal.KubeletConfiguration,
	...
	nodeStatusMaxImages int32) (k kubelet.Bootstrap, err error) {
	// TODO: block until all sources have delivered at least one update to the channel, or break the sync loop
	// up into "per source" synchronizations

	k, err = kubelet.NewMainKubelet(kubeCfg,
		kubeDeps,
		crOptions,
		containerRuntime,
		runtimeCgroups,
		hostnameOverride,
		nodeIP,
		providerID,
		cloudProvider,
		certDirectory,
		rootDirectory,
		registerNode,
		registerWithTaints,
		allowedUnsafeSysctls,
		remoteRuntimeEndpoint,
		remoteImageEndpoint,
		experimentalMounterPath,
		experimentalKernelMemcgNotification,
		experimentalCheckNodeCapabilitiesBeforeMount,
		experimentalNodeAllocatableIgnoreEvictionThreshold,
		minimumGCAge,
		maxPerPodContainerCount,
		maxContainerCount,
		masterServiceNamespace,
		registerSchedulable,
		nonMasqueradeCIDR,
		keepTerminatedPodVolumes,
		nodeLabels,
		seccompProfileRoot,
		bootstrapCheckpointPath,
		nodeStatusMaxImages)
	if err != nil {
		return nil, err
	}

	k.BirthCry()

	k.StartGarbageCollection()

	return k, nil
}
```

### 4.1.2. PodConfig

```go
if kubeDeps.PodConfig == nil {
	var err error
	kubeDeps.PodConfig, err = makePodSourceConfig(kubeCfg, kubeDeps, nodeName, bootstrapCheckpointPath)
	if err != nil {
		return nil, err
	}
}
```

`NewMainKubelet-->PodConfig-->NewPodConfig-->kubetypes.PodUpdate`。会生成一个`podUpdate`的channel来监听pod的变化，该channel会在`k.Run(podCfg.Updates())`中作为关键入参。

## 4.2. startKubelet

```go
// process pods and exit.
if runOnce {
	if _, err := k.RunOnce(podCfg.Updates()); err != nil {
		return fmt.Errorf("runonce failed: %v", err)
	}
	glog.Infof("Started kubelet as runonce")
} else {
	startKubelet(k, podCfg, &kubeServer.KubeletConfiguration, kubeDeps, kubeServer.EnableServer)
	glog.Infof("Started kubelet")
}
```

如果设置了只运行一次的参数，则执行`k.RunOnce`，否则执行核心函数`startKubelet`。具体实现如下：

```go
func startKubelet(k kubelet.Bootstrap, podCfg *config.PodConfig, kubeCfg *kubeletconfiginternal.KubeletConfiguration, kubeDeps *kubelet.Dependencies, enableServer bool) {
	// start the kubelet
	go wait.Until(func() {
		k.Run(podCfg.Updates())
	}, 0, wait.NeverStop)

	// start the kubelet server
	if enableServer {
		go k.ListenAndServe(net.ParseIP(kubeCfg.Address), uint(kubeCfg.Port), kubeDeps.TLSOptions, kubeDeps.Auth, kubeCfg.EnableDebuggingHandlers, kubeCfg.EnableContentionProfiling)

	}
	if kubeCfg.ReadOnlyPort > 0 {
		go k.ListenAndServeReadOnly(net.ParseIP(kubeCfg.Address), uint(kubeCfg.ReadOnlyPort))
	}
}
```

### 4.2.1. k.Run

```go
// start the kubelet
go wait.Until(func() {
	k.Run(podCfg.Updates())
}, 0, wait.NeverStop)
```

通过长驻进程的方式运行`k.Run`，不退出，将kubelet的运行逻辑引入[kubernetes/pkg/kubelet/kubelet.go](https://github.com/kubernetes/kubernetes/blob/v1.12.0/pkg/kubelet/kubelet.go#L1382)部分，`kubernetes/pkg/kubelet`部分的运行逻辑待后续文章分析。

# 5. 总结

1. kubelet采用[Cobra](https://github.com/spf13/cobra)命令行框架和[pflag](https://github.com/spf13/pflag)参数解析框架，和apiserver、scheduler、controller-manager形成统一的代码风格。

2. `kubernetes/cmd/kubelet`部分主要对运行参数进行定义和解析，初始化和构造相关的依赖组件（主要在`kubeDeps`结构体中），并没有kubelet运行的详细逻辑，该部分位于`kubernetes/pkg/kubelet`模块。

3. cmd部分调用流程如下：`Main-->NewKubeletCommand-->Run(kubeletServer, kubeletDeps, stopCh)-->run(s *options.KubeletServer, kubeDeps ..., stopCh ...)--> RunKubelet(s, kubeDeps, s.RunOnce)-->startKubelet-->k.Run(podCfg.Updates())-->pkg/kubelet`。

   同时`RunKubelet(s, kubeDeps, s.RunOnce)-->CreateAndInitKubelet-->kubelet.NewMainKubelet-->pkg/kubelet`。



参考文章：

- https://github.com/kubernetes/kubernetes/tree/v1.12.0
