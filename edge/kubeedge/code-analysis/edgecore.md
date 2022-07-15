# kubeedge源码分析之edgecore

> 本文源码分析基于[kubeedge v1.1.0](https://github.com/kubeedge/kubeedge/releases/tag/v1.1.0)

本文主要分析`edgecore`中`EdgeCoreCommand`的基本流程，具体的`edged`、`edgehub`、`metamanager`等模块的实现逻辑待后续单独文章分析。

目录结构：

```bash
edgecore
├── app
│   ├── options
│   │   └── options.go
│   └── server.go  # NewEdgeCoreCommand 、registerModules
└── edgecore.go  # main
```

edgecore模块包含：


- edged
- edgehub
- metamanager
- eventbus
- servicebus
- devicetwin
- edgemesh


# 1. main函数

main入口函数，仍然是cobra命令框架格式。

> edge/cmd/edgecore/edgecore.go

```go
func main() {
	command := app.NewEdgeCoreCommand()
	logs.InitLogs()
	defer logs.FlushLogs()

	if err := command.Execute(); err != nil {
		os.Exit(1)
	}
}
```

# 2. NewEdgeCoreCommand

`NewEdgeCoreCommand`与`NewCloudCoreCommand`一样构造对应的cobra command结构体。

> edge/cmd/edgecore/app/server.go

```go
// NewEdgeCoreCommand create edgecore cmd
func NewEdgeCoreCommand() *cobra.Command {
	opts := options.NewEdgeCoreOptions()
	cmd := &cobra.Command{
		Use: "edgecore",
		Long: `Edgecore is the core edge part of KubeEdge, which contains six modules: devicetwin, edged, 
edgehub, eventbus, metamanager, and servicebus. DeviceTwin is responsible for storing device status 
and syncing device status to the cloud. It also provides query interfaces for applications. Edged is an 
agent that runs on edge nodes and manages containerized applications and devices. Edgehub is a web socket 
client responsible for interacting with Cloud Service for the edge computing (like Edge Controller as in the KubeEdge 
Architecture). This includes syncing cloud-side resource updates to the edge, and reporting 
edge-side host and device status changes to the cloud. EventBus is a MQTT client to interact with MQTT 
servers (mosquito), offering publish and subscribe capabilities to other components. MetaManager 
is the message processor between edged and edgehub. It is also responsible for storing/retrieving metadata 
to/from a lightweight database (SQLite).ServiceBus is a HTTP client to interact with HTTP servers (REST), 
offering HTTP client capabilities to components of cloud to reach HTTP servers running at edge. `,
		Run: func(cmd *cobra.Command, args []string) {
			verflag.PrintAndExitIfRequested()
			flag.PrintFlags(cmd.Flags())

			// To help debugging, immediately log version
			klog.Infof("Version: %+v", version.Get())

			registerModules()
			// start all modules
			core.Run()
		},
	}
	fs := cmd.Flags()
	namedFs := opts.Flags()
	verflag.AddFlags(namedFs.FlagSet("global"))
	globalflag.AddGlobalFlags(namedFs.FlagSet("global"), cmd.Name())
	for _, f := range namedFs.FlagSets {
		fs.AddFlagSet(f)
	}

	usageFmt := "Usage:\n  %s\n"
	cols, _, _ := term.TerminalSize(cmd.OutOrStdout())
	cmd.SetUsageFunc(func(cmd *cobra.Command) error {
		fmt.Fprintf(cmd.OutOrStderr(), usageFmt, cmd.UseLine())
		cliflag.PrintSections(cmd.OutOrStderr(), namedFs, cols)
		return nil
	})
	cmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
		fmt.Fprintf(cmd.OutOrStdout(), "%s\n\n"+usageFmt, cmd.Long, cmd.UseLine())
		cliflag.PrintSections(cmd.OutOrStdout(), namedFs, cols)
	})

	return cmd
}
```

核心代码：

```go
opts := options.NewEdgeCoreOptions()
registerModules()
core.Run()
```

# 3. registerModules

edgecore仍然采用[Beehive](https://kubeedge.readthedocs.io/en/latest/modules/beehive.html)通信框架，模块调用前先注册对应的模块。具体参考[cloudcore.registerModules](https://www.huweihuang.com/kubernetes-notes/kubeedge/code-analysis/cloudcore.html#3-registermodules)处的分析，此处不再展开分析注册流程。此处注册的是edgecore中涉及的组件。

> edge/cmd/edgecore/app/server.go

```go
// registerModules register all the modules started in edgecore
func registerModules() {
	devicetwin.Register()
	edged.Register()
	edgehub.Register()
	eventbus.Register()
	edgemesh.Register()
	metamanager.Register()
	servicebus.Register()
	test.Register()
	dbm.InitDBManager()
}
```

#  4. core.Run

core.Run与[cloudcore.run](https://www.huweihuang.com/kubernetes-notes/kubeedge/code-analysis/cloudcore.html#4-corerun)处逻辑一致不再展开分析。

> vendor/github.com/kubeedge/beehive/pkg/core/core.go

```go
//Run starts the modules and in the end does module cleanup
func Run() {
   //Address the module registration and start the core
   StartModules()
   // monitor system signal and shutdown gracefully
   GracefulShutdown()
}
```



参考：

- https://github.com/kubeedge/kubeedge/tree/release-1.1/edge/cmd/edgecore

