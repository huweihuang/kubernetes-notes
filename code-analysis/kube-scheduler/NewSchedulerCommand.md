# kube-scheduler源码分析（一）之 NewSchedulerCommand

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

scheduler的`cmd`代码目录结构如下：

```bash
kube-scheduler
├── BUILD
├── OWNERS
├── app            # app的目录下主要为运行scheduler相关的对象
│   ├── BUILD
│   ├── config      
│   │   ├── BUILD
│   │   └── config.go    # Scheduler的配置对象config
│   ├── options      # options主要记录 Scheduler 使用到的参数
│   │   ├── BUILD
│   │   ├── configfile.go
│   │   ├── deprecated.go
│   │   ├── deprecated_test.go
│   │   ├── insecure_serving.go
│   │   ├── insecure_serving_test.go
│   │   ├── options.go    # 主要包括Options、NewOptions、AddFlags、Config等函数
│   │   └── options_test.go
│   └── server.go    # 主要包括 NewSchedulerCommand、NewSchedulerConfig、Run等函数
└── scheduler.go     # main入口函数
```

# 1. [Main](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-scheduler/scheduler.go#L34)函数

> 此部分的代码为/cmd/kube-scheduler/scheduler.go

`kube-scheduler`的入口函数`Main`函数，仍然是采用统一的代码风格，使用[Cobra](https://github.com/spf13/cobra)命令行框架。

```go
func main() {
	rand.Seed(time.Now().UTC().UnixNano())

	command := app.NewSchedulerCommand()

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
// 初始化scheduler命令结构体
command := app.NewSchedulerCommand()
// 执行Execute
err := command.Execute()
```

# 2. [NewSchedulerCommand](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-scheduler/app/server.go#L68)

> 此部分的代码为/cmd/kube-scheduler/app/server.go

`NewSchedulerCommand`主要用来构造和初始化SchedulerCommand结构体，

```go
// NewSchedulerCommand creates a *cobra.Command object with default parameters
func NewSchedulerCommand() *cobra.Command {
	opts, err := options.NewOptions()
	if err != nil {
		glog.Fatalf("unable to initialize command options: %v", err)
	}

	cmd := &cobra.Command{
		Use: "kube-scheduler",
		Long: `The Kubernetes scheduler is a policy-rich, topology-aware,
workload-specific function that significantly impacts availability, performance,
and capacity. The scheduler needs to take into account individual and collective
resource requirements, quality of service requirements, hardware/software/policy
constraints, affinity and anti-affinity specifications, data locality, inter-workload
interference, deadlines, and so on. Workload-specific requirements will be exposed
through the API as necessary.`,
		Run: func(cmd *cobra.Command, args []string) {
			verflag.PrintAndExitIfRequested()
			utilflag.PrintFlags(cmd.Flags())

			if len(args) != 0 {
				fmt.Fprint(os.Stderr, "arguments are not supported\n")
			}

			if errs := opts.Validate(); len(errs) > 0 {
				fmt.Fprintf(os.Stderr, "%v\n", utilerrors.NewAggregate(errs))
				os.Exit(1)
			}

			if len(opts.WriteConfigTo) > 0 {
				if err := options.WriteConfigFile(opts.WriteConfigTo, &opts.ComponentConfig); err != nil {
					fmt.Fprintf(os.Stderr, "%v\n", err)
					os.Exit(1)
				}
				glog.Infof("Wrote configuration to: %s\n", opts.WriteConfigTo)
				return
			}

			c, err := opts.Config()
			if err != nil {
				fmt.Fprintf(os.Stderr, "%v\n", err)
				os.Exit(1)
			}

			stopCh := make(chan struct{})
			if err := Run(c.Complete(), stopCh); err != nil {
				fmt.Fprintf(os.Stderr, "%v\n", err)
				os.Exit(1)
			}
		},
	}

	opts.AddFlags(cmd.Flags())
	cmd.MarkFlagFilename("config", "yaml", "yml", "json")

	return cmd
}
```

核心代码：

```go
// 构造option
opts, err := options.NewOptions()
// 初始化config对象
c, err := opts.Config()
// 执行run函数
err := Run(c.Complete(), stopCh)
// 添加参数
opts.AddFlags(cmd.Flags())
```

## 2.1. NewOptions

NewOptions主要用来构造SchedulerServer使用的参数和上下文，其中核心参数是`KubeSchedulerConfiguration`。

```go
opts, err := options.NewOptions()
```

**NewOptions**:

```go
// NewOptions returns default scheduler app options.
func NewOptions() (*Options, error) {
	cfg, err := newDefaultComponentConfig()
	if err != nil {
		return nil, err
	}

	hhost, hport, err := splitHostIntPort(cfg.HealthzBindAddress)
	if err != nil {
		return nil, err
	}

	o := &Options{
		ComponentConfig: *cfg,
		SecureServing:   nil, // TODO: enable with apiserveroptions.NewSecureServingOptions()
		CombinedInsecureServing: &CombinedInsecureServingOptions{
			Healthz: &apiserveroptions.DeprecatedInsecureServingOptions{
				BindNetwork: "tcp",
			},
			Metrics: &apiserveroptions.DeprecatedInsecureServingOptions{
				BindNetwork: "tcp",
			},
			BindPort:    hport,
			BindAddress: hhost,
		},
		Authentication: nil, // TODO: enable with apiserveroptions.NewDelegatingAuthenticationOptions()
		Authorization:  nil, // TODO: enable with apiserveroptions.NewDelegatingAuthorizationOptions()
		Deprecated: &DeprecatedOptions{
			UseLegacyPolicyConfig:    false,
			PolicyConfigMapNamespace: metav1.NamespaceSystem,
		},
	}

	return o, nil
}
```

## 2.2. Options.Config

Config初始化调度器的配置对象。

```go
c, err := opts.Config()
```

Config函数主要执行以下操作：

- 构建scheduler client、leaderElectionClient、eventClient。
- 创建event recorder
- 设置leader选举
- 创建informer对象，主要函数有`NewSharedInformerFactory`和`NewPodInformer`。

Config具体代码如下：

```go
// Config return a scheduler config object
func (o *Options) Config() (*schedulerappconfig.Config, error) {
	c := &schedulerappconfig.Config{}
	if err := o.ApplyTo(c); err != nil {
		return nil, err
	}

	// prepare kube clients.
	client, leaderElectionClient, eventClient, err := createClients(c.ComponentConfig.ClientConnection, o.Master, c.ComponentConfig.LeaderElection.RenewDeadline.Duration)
	if err != nil {
		return nil, err
	}

	// Prepare event clients.
	eventBroadcaster := record.NewBroadcaster()
	recorder := eventBroadcaster.NewRecorder(legacyscheme.Scheme, corev1.EventSource{Component: c.ComponentConfig.SchedulerName})

	// Set up leader election if enabled.
	var leaderElectionConfig *leaderelection.LeaderElectionConfig
	if c.ComponentConfig.LeaderElection.LeaderElect {
		leaderElectionConfig, err = makeLeaderElectionConfig(c.ComponentConfig.LeaderElection, leaderElectionClient, recorder)
		if err != nil {
			return nil, err
		}
	}

	c.Client = client
	c.InformerFactory = informers.NewSharedInformerFactory(client, 0)
	c.PodInformer = factory.NewPodInformer(client, 0)
	c.EventClient = eventClient
	c.Recorder = recorder
	c.Broadcaster = eventBroadcaster
	c.LeaderElection = leaderElectionConfig

	return c, nil
}
```

## 2.3. AddFlags

`AddFlags`为SchedulerServer添加指定的参数。

```go
opts.AddFlags(cmd.Flags())
```

AddFlags函数的具体代码如下：

```go
// AddFlags adds flags for the scheduler options.
func (o *Options) AddFlags(fs *pflag.FlagSet) {
	fs.StringVar(&o.ConfigFile, "config", o.ConfigFile, "The path to the configuration file. Flags override values in this file.")
	fs.StringVar(&o.WriteConfigTo, "write-config-to", o.WriteConfigTo, "If set, write the configuration values to this file and exit.")
	fs.StringVar(&o.Master, "master", o.Master, "The address of the Kubernetes API server (overrides any value in kubeconfig)")

	o.SecureServing.AddFlags(fs)
	o.CombinedInsecureServing.AddFlags(fs)
	o.Authentication.AddFlags(fs)
	o.Authorization.AddFlags(fs)
	o.Deprecated.AddFlags(fs, &o.ComponentConfig)

	leaderelectionconfig.BindFlags(&o.ComponentConfig.LeaderElection.LeaderElectionConfiguration, fs)
	utilfeature.DefaultFeatureGate.AddFlag(fs)
}
```

# 3. [Run](https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-scheduler/app/server.go#L126)

> 此部分的代码为/cmd/kube-scheduler/app/server.go

```go
err := Run(c.Complete(), stopCh)
```

` Run`运行一个不退出的常驻进程，来执行scheduler的相关操作。

Run函数的主要内容如下：

- 通过scheduler config来创建scheduler的结构体。
- 运行event broadcaster、healthz server、metrics server。
- 运行所有的informer并在调度前等待cache的同步（重点）。
- 执行`sched.Run()`来运行scheduler的调度逻辑。
- 如果多个scheduler并开启了`LeaderElect`，则执行leader选举。

以下对重点代码分开分析：

## 3.1. NewSchedulerConfig

> NewSchedulerConfig初始化SchedulerConfig（此部分具体逻辑待后续专门分析），最后初始化生成scheduler结构体。

```go
// Build a scheduler config from the provided algorithm source.
schedulerConfig, err := NewSchedulerConfig(c)
if err != nil {
	return err
}

// Create the scheduler.
sched := scheduler.NewFromConfig(schedulerConfig)
```

## 3.2. InformerFactory.Start

运行PodInformer，并运行InformerFactory。此部分的逻辑为client-go的informer机制，在[Informer机制](https://www.huweihuang.com/kubernetes-notes/code-analysis/kube-controller-manager/sharedIndexInformer.html)中有详细分析。

```go
// Start all informers.
go c.PodInformer.Informer().Run(stopCh)
c.InformerFactory.Start(stopCh)
```

## 3.3. WaitForCacheSync

在调度前等待cache同步。

```go
// Wait for all caches to sync before scheduling.
c.InformerFactory.WaitForCacheSync(stopCh)
controller.WaitForCacheSync("scheduler", stopCh, c.PodInformer.Informer().HasSynced)
```

### 3.3.1. InformerFactory.WaitForCacheSync

`InformerFactory.WaitForCacheSync`等待所有启动的informer的cache进行同步，保持本地的store信息与etcd的信息是最新一致的。

```go
// WaitForCacheSync waits for all started informers' cache were synced.
func (f *sharedInformerFactory) WaitForCacheSync(stopCh <-chan struct{}) map[reflect.Type]bool {
	informers := func() map[reflect.Type]cache.SharedIndexInformer {
		f.lock.Lock()
		defer f.lock.Unlock()

		informers := map[reflect.Type]cache.SharedIndexInformer{}
		for informerType, informer := range f.informers {
			if f.startedInformers[informerType] {
				informers[informerType] = informer
			}
		}
		return informers
	}()

	res := map[reflect.Type]bool{}
	for informType, informer := range informers {
		res[informType] = cache.WaitForCacheSync(stopCh, informer.HasSynced)
	}
	return res
}
```

接着调用` cache.WaitForCacheSync`。

```go
// WaitForCacheSync waits for caches to populate.  It returns true if it was successful, false
// if the controller should shutdown
func WaitForCacheSync(stopCh <-chan struct{}, cacheSyncs ...InformerSynced) bool {
	err := wait.PollUntil(syncedPollPeriod,
		func() (bool, error) {
			for _, syncFunc := range cacheSyncs {
				if !syncFunc() {
					return false, nil
				}
			}
			return true, nil
		},
		stopCh)
	if err != nil {
		glog.V(2).Infof("stop requested")
		return false
	}

	glog.V(4).Infof("caches populated")
	return true
}
```

### 3.3.2. controller.WaitForCacheSync

`controller.WaitForCacheSync`是对`cache.WaitForCacheSync`的一层封装，通过不同的controller的名字来记录不同controller等待cache同步。

```go
controller.WaitForCacheSync("scheduler", stop, s.PodInformer.Informer().HasSynced)
```

`controller.WaitForCacheSync`具体代码如下：

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

## 3.4. LeaderElection

如果有多个scheduler，并开启leader选举，则运行`LeaderElector`直到选举结束或退出。

```go
// If leader election is enabled, run via LeaderElector until done and exit.
if c.LeaderElection != nil {
	c.LeaderElection.Callbacks = leaderelection.LeaderCallbacks{
		OnStartedLeading: run,
		OnStoppedLeading: func() {
			utilruntime.HandleError(fmt.Errorf("lost master"))
		},
	}
	leaderElector, err := leaderelection.NewLeaderElector(*c.LeaderElection)
	if err != nil {
		return fmt.Errorf("couldn't create leader elector: %v", err)
	}

	leaderElector.Run(ctx)

	return fmt.Errorf("lost lease")
}
```

## 3.5. Scheduler.Run

```go
// Prepare a reusable run function.
run := func(ctx context.Context) {
	sched.Run()
	<-ctx.Done()
}

ctx, cancel := context.WithCancel(context.TODO()) // TODO once Run() accepts a context, it should be used here
defer cancel()

go func() {
	select {
	case <-stopCh:
		cancel()
	case <-ctx.Done():
	}
}()
...
run(ctx)
```

`Scheduler.Run`先等待cache同步，然后开启调度逻辑的goroutine。

Scheduler.Run的具体代码如下：

```go
// Run begins watching and scheduling. It waits for cache to be synced, then starts a goroutine and returns immediately.
func (sched *Scheduler) Run() {
	if !sched.config.WaitForCacheSync() {
		return
	}

	go wait.Until(sched.scheduleOne, 0, sched.config.StopEverything)
}
```

以上是对`/cmd/kube-scheduler/scheduler.go`部分代码的分析，`Scheduler.Run`后续的具体代码位于`pkg/scheduler/scheduler.go`待后续文章分析。



参考：

- https://github.com/kubernetes/kubernetes/tree/v1.12.0/cmd/kube-scheduler
- https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-scheduler/scheduler.go
- https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-scheduler/app/server.go
