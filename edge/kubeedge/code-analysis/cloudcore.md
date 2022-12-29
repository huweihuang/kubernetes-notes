---
title: "Kubeedge之cloudcore 源码分析"
linkTitle: "cloudcore"
weight: 1
catalog: true
date: 2021-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubeedge
catagories:
- Kubeedge
---

# kubeedge源码分析之cloudcore

> 本文源码分析基于[kubeedge v1.1.0](https://github.com/kubeedge/kubeedge/releases/tag/v1.1.0)

本文主要分析cloudcore中CloudCoreCommand的基本流程，具体的`cloudhub`、`edgecontroller`、`devicecontroller`模块的实现逻辑待后续单独文章分析。

目录结构：

> cloud/cmd/cloudcore

```bash
cloudcore
├── app
│   ├── options
│   │   └── options.go
│   └── server.go # NewCloudCoreCommand、registerModules
└── cloudcore.go # main函数
```

`cloudcore`部分包含以下模块：

- cloudhub
- edgecontroller
- devicecontroller

# 1. main函数

kubeedge的代码采用cobra命令框架，代码风格与k8s源码风格类似。cmd目录主要为cobra command的基本内容及参数解析，pkg目录包含具体的实现逻辑。

> cloud/cmd/cloudcore/cloudcore.go

```go
func main() {
	command := app.NewCloudCoreCommand()
	logs.InitLogs()
	defer logs.FlushLogs()

	if err := command.Execute(); err != nil {
		os.Exit(1)
	}
}
```

# 2. NewCloudCoreCommand

`NewCloudCoreCommand`为cobra command的构造函数，该类函数一般包含以下部分：

- 构造option
- 添加Flags
- 运行Run函数（核心）

> cloud/cmd/cloudcore/app/server.go

```go
func NewCloudCoreCommand() *cobra.Command {
	opts := options.NewCloudCoreOptions()
	cmd := &cobra.Command{
		Use: "cloudcore",
		Long: `CloudCore is the core cloud part of KubeEdge, which contains three modules: cloudhub,
edgecontroller, and devicecontroller. Cloudhub is a web server responsible for watching changes at the cloud side,
caching and sending messages to EdgeHub. EdgeController is an extended kubernetes controller which manages 
edge nodes and pods metadata so that the data can be targeted to a specific edge node. DeviceController is an extended 
kubernetes controller which manages devices so that the device metadata/status date can be synced between edge and cloud.`,
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
// 构造option
opts := options.NewCloudCoreOptions()
// 执行run函数
registerModules()
core.Run()
// 添加flags
fs.AddFlagSet(f)
```

# 3. registerModules

由于kubeedge的代码的大部分模块都采用了基于go-channel的消息通信框架[Beehive](https://kubeedge.readthedocs.io/en/latest/modules/beehive.html)（待后续单独文章分析），因此在各模块启动之前，需要将该模块注册到beehive的框架中。

其中cloudcore部分涉及的模块有：

- cloudhub
- edgecontroller
- devicecontroller

> cloud/cmd/cloudcore/app/server.go

```go
// registerModules register all the modules started in cloudcore
func registerModules() {
	cloudhub.Register()
	edgecontroller.Register()
	devicecontroller.Register()
}
```

以下以cloudhub为例说明注册的过程。

cloudhub结构体主要包含：

- context：上下文，用来传递消息上下文
- stopChan：go channel通信

beehive框架中的模块需要实现`Module`接口，因此cloudhub也实现了该接口，其中核心方法为Start，用来启动相应模块的运行。

> vendor/github.com/kubeedge/beehive/pkg/core/module.go

```go
// Module interface
type Module interface {
	Name() string
	Group() string
	Start(c *context.Context)
	Cleanup()
}
```

以下为cloudHub结构体及注册函数。

> cloud/pkg/cloudhub/cloudhub.go

```go
type cloudHub struct {
	context  *context.Context
	stopChan chan bool
}

func Register() {
	core.Register(&cloudHub{})
}
```

具体的注册实现函数为core.Register，注册过程实际上就是将具体的模块结构体放入一个以模块名为key的map映射中，待后续调用。

> vendor/github.com/kubeedge/beehive/pkg/core/module.go

```go
// Register register module
func Register(m Module) {
	if isModuleEnabled(m.Name()) {
		modules[m.Name()] = m  //将具体的模块结构体放入一个以模块名为key的map映射中
		log.LOGGER.Info("module " + m.Name() + " registered")
	} else {
		disabledModules[m.Name()] = m
		log.LOGGER.Info("module " + m.Name() +
			" is not register, please check modules.yaml")
	}
}
```

# 4. core.Run

CloudCoreCommand命令的Run函数实际上是运行beehive框架中注册的所有模块。

其中包括两部分逻辑：

- 启动运行所有注册模块
- 监听信号并做优雅清理

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

# 5. StartModules

`StartModules`获取context上下文，并以goroutine的方式运行所有已注册的模块。其中Start函数即每个模块的具体实现`Module`接口中的Start方法。不同模块各自定义自己的具体Start方法实现。

```go
coreContext := context.GetContext(context.MsgCtxTypeChannel)
go module.Start(coreContext)
```

具体实现如下：

> vendor/github.com/kubeedge/beehive/pkg/core/core.go

```go
// StartModules starts modules that are registered
func StartModules() {
	coreContext := context.GetContext(context.MsgCtxTypeChannel)

	modules := GetModules()
	for name, module := range modules {
		//Init the module
		coreContext.AddModule(name)
		//Assemble typeChannels for send2Group
		coreContext.AddModuleGroup(name, module.Group())
		go module.Start(coreContext)
		log.LOGGER.Info("starting module " + name)
	}
}
```

# 6. GracefulShutdown

当收到相关信号，则执行各个模块实现的Cleanup方法。

> vendor/github.com/kubeedge/beehive/pkg/core/core.go

```go
// GracefulShutdown is if it gets the special signals it does modules cleanup
func GracefulShutdown() {
	c := make(chan os.Signal)
	signal.Notify(c, syscall.SIGINT, syscall.SIGHUP, syscall.SIGTERM,
		syscall.SIGQUIT, syscall.SIGILL, syscall.SIGTRAP, syscall.SIGABRT)
	select {
	case s := <-c:
		log.LOGGER.Info("got os signal " + s.String())
		//Cleanup each modules
		modules := GetModules()
		for name, module := range modules {
			log.LOGGER.Info("Cleanup module " + name)
			module.Cleanup()
		}
	}
}
```



参考：

- https://github.com/kubeedge/kubeedge/tree/release-1.1/cloud/cmd/cloudcore
- https://github.com/kubeedge/kubeedge/tree/release-1.1/vendor/github.com/kubeedge/beehive/pkg/core

