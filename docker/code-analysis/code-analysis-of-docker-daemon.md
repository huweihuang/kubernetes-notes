# 1. Docker Daemon架构示意图

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510578079/article/docker/dockerDaemon/DaemonArchitecture.jpg" width="60%">

Docker Daemon是Docker架构中运行在后台的守护进程，大致可以分为Docker Server、Engine和Job三部分。

Docker Daemon可以认为是通过Docker Server模块接受Docker Client的请求，并在Engine中处理请求，然后根据请求类型，创建出指定的Job并运行。

运行过程的作用有以下几种可能：

- 向Docker Registry获取镜像，
- 通过graphdriver执行容器镜像的本地化操作，
- 通过networkdriver执行容器网络环境的配置，
- 通过execdriver执行容器内部运行的执行工作等。

说明：本文分析的代码为Docker 1.2.0版本。

# 2. Docker Daemon启动流程图

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510578079/article/docker/dockerDaemon/DaemonFlow.jpg" width="50%">

启动Docker Daemon时，一般可以使用以下命令：docker --daemon=true; docker –d; docker –d=true等。接着由docker的main()函数来解析以上命令的相应flag参数，并最终完成Docker Daemon的启动。

**/docker/docker.go**

```go
func main() {
    ...
    if *flDaemon {
        mainDaemon()
        return
    }
    ...
}
```

# 3. mainDaemon的具体实现

宏观来讲，mainDaemon()完成创建一个daemon进程，并使其正常运行。

从功能的角度来说，mainDaemon()实现了两部分内容：

- 第一，创建Docker运行环境；
- 第二，服务于Docker Client，接收并处理相应请求。

## 3.1. 配置初始化

**/docker/daemon.go**

```go
var (
    daemonCfg = &daemon.Config{}
)
func init() {
    daemonCfg.InstallFlags()
}
```

在mainDaemon()运行之前，关于Docker Daemon所需要的config配置信息均已经初始化完毕。

声明一个为daemon包中Config类型的变量，名为daemonCfg。而Config对象，定义了Docker Daemon所需的配置信息。在Docker Daemon在启动时，daemonCfg变量被传递至Docker Daemon并被使用。

**/daemon/config.go**

```go
type Config struct {
    Pidfile                  string   //Docker Daemon所属进程的PID文件
    Root                   string   //Docker运行时所使用的root路径
    AutoRestart             bool    //已被启用，转而支持docker run时的重启
    Dns                   []string  //Docker使用的DNS Server地址
    DnsSearch              []string  //Docker使用的指定的DNS查找域名
    Mirrors                 []string  //指定的优先Docker Registry镜像
    EnableIptables           bool    //启用Docker的iptables功能
    EnableIpForward         bool    //启用net.ipv4.ip_forward功能
    EnableIpMasq            bool      //启用IP伪装技术
    DefaultIp                net.IP     //绑定容器端口时使用的默认IP
    BridgeIface              string      //添加容器网络至已有的网桥
    BridgeIP                 string     //创建网桥的IP地址
    FixedCIDR               string     //指定IP的IPv4子网，必须被网桥子网包含
    InterContainerCommunication   bool  //是否允许相同host上容器间的通信
    GraphDriver             string      //Docker运行时使用的特定存储驱动
    GraphOptions            []string   //可设置的存储驱动选项
    ExecDriver               string    // Docker运行时使用的特定exec驱动
    Mtu                    int      //设置容器网络的MTU
    DisableNetwork          bool     //有定义，之后未初始化
    EnableSelinuxSupport      bool     //启用SELinux功能的支持
    Context                 map[string][]string   //有定义，之后未初始化
}
```

init()函数实现了daemonCfg变量中各属性的赋值，具体的实现为：daemonCfg.InstallFlags()

**/daemon/config.go**

```go
// InstallFlags adds command-line options to the top-level flag parser for
// the current process.
// Subsequent calls to `flag.Parse` will populate config with values parsed
// from the command-line.
func (config *Config) InstallFlags() {
    flag.StringVar(&config.Pidfile, []string{"p", "-pidfile"}, "/var/run/docker.pid", "Path to use for daemon PID file")
    flag.StringVar(&config.Root, []string{"g", "-graph"}, "/var/lib/docker", "Path to use as the root of the Docker runtime")
    flag.BoolVar(&config.AutoRestart, []string{"#r", "#-restart"}, true, "--restart on the daemon has been deprecated infavor of --restart policies on docker run")
    flag.BoolVar(&config.EnableIptables, []string{"#iptables", "-iptables"}, true, "Enable Docker's addition of iptables rules")
    flag.BoolVar(&config.EnableIpForward, []string{"#ip-forward", "-ip-forward"}, true, "Enable net.ipv4.ip_forward")
    flag.StringVar(&config.BridgeIP, []string{"#bip", "-bip"}, "", "Use this CIDR notation address for the network bridge's IP, not compatible with -b")
    flag.StringVar(&config.BridgeIface, []string{"b", "-bridge"}, "", "Attach containers to a pre-existing network bridge/nuse 'none' to disable container networking")
    flag.BoolVar(&config.InterContainerCommunication, []string{"#icc", "-icc"}, true, "Enable inter-container communication")
    flag.StringVar(&config.GraphDriver, []string{"s", "-storage-driver"}, "", "Force the Docker runtime to use a specific storage driver")
    flag.StringVar(&config.ExecDriver, []string{"e", "-exec-driver"}, "native", "Force the Docker runtime to use a specific exec driver")
    flag.BoolVar(&config.EnableSelinuxSupport, []string{"-selinux-enabled"}, false, "Enable selinux support. SELinux does not presently support the BTRFS storage driver")
    flag.IntVar(&config.Mtu, []string{"#mtu", "-mtu"}, 0, "Set the containers network MTU/nif no value is provided: default to the default route MTU or 1500 if no default route is available")
    opts.IPVar(&config.DefaultIp, []string{"#ip", "-ip"}, "0.0.0.0", "Default IP address to use when binding container ports")
    opts.ListVar(&config.GraphOptions, []string{"-storage-opt"}, "Set storage driver options")
    // FIXME: why the inconsistency between "hosts" and "sockets"?
    opts.IPListVar(&config.Dns, []string{"#dns", "-dns"}, "Force Docker to use specific DNS servers")
    opts.DnsSearchListVar(&config.DnsSearch, []string{"-dns-search"}, "Force Docker to use specific DNS search domains")
}
```

在InstallFlags()函数的实现过程中，主要是定义某种类型的flag参数，并将该参数的值绑定在config变量的指定属性上，如：

flag.StringVar(&config.Pidfile, []string{"p", "-pidfile"}, " /var/run/docker.pid", "Path to use for daemon PID file")

以上语句的含义为：

- 定义一个为String类型的flag参数；
- 该flag的名称为”p”或者”-pidfile”;
- 该flag的值为” /var/run/docker.pid”,并将该值绑定在变量config.Pidfile上；
- 该flag的描述信息为"Path to use for daemon PID file"。

## 3.2. flag参数检查

**/docker/daemon.go**

```go
if flag.NArg() != 0 {
    flag.Usage()
    return
}
```

- 参数个数不为0，则说明在启动Docker Daemon的时候，传入了多余的参数，此时会输出错误提示，并退出运行程序。
- 若为0，则说明Docker Daemon的启动命令无误，正常运行。

## 3.3. 创建engine对象

**/docker/daemon.go**

```go
eng := engine.New()
```

Engine是Docker架构中的运行引擎，同时也是Docker运行的核心模块。Engine扮演着Docker container存储仓库的角色，并且通过job的形式来管理这些容器。

**/engine/engine.go**

```go
type Engine struct {
    handlers   map[string]Handler
    catchall   Handler
    hack       Hack // data for temporary hackery (see hack.go)
    id         string
    Stdout     io.Writer
    Stderr     io.Writer
    Stdin      io.Reader
    Logging    bool
    tasks      sync.WaitGroup
    l          sync.RWMutex // lock for shutdown
    shutdown   bool
    onShutdown []func() // shutdown handlers
}
```

Engine结构体中最为重要的即为handlers属性。该handlers属性为map类型，key为string类型，value为Handler类型。Handler为一个定义的函数。该函数传入的参数为Job指针，返回为Status状态。

**/engine/engine.go**

```go
type Handler func(*Job) Status
```

New()函数的实现:

**/engine/engine.go**

```go
// New initializes a new engine.
func New() *Engine {
    eng := &Engine{
        handlers: make(map[string]Handler),
        id:       utils.RandomString(),
        Stdout:   os.Stdout,
        Stderr:   os.Stderr,
        Stdin:    os.Stdin,
        Logging:  true,
    }
    eng.Register("commands", func(job *Job) Status {
        for _, name := range eng.commands() {
            job.Printf("%s/n", name)
        }
        return StatusOK
    })
    // Copy existing global handlers
    for k, v := range globalHandlers {
        eng.handlers[k] = v
    }
    return eng
}
```

1. 创建一个Engine结构体实例eng
2. 向eng对象注册名为commands的Handler，其中Handler为临时定义的函数func(job *Job) Status{ } , 该函数的作用是通过job来打印所有已经注册完毕的command名称，最终返回状态StatusOK。
3. 将已定义的变量globalHandlers中的所有的Handler，都复制到eng对象的handlers属性中。最后成功返回eng对象。

## 3.4. 设置engine的信号捕获

**/daemon/daemon.go**

```go
signal.Trap(eng.Shutdown)
```

在Docker Daemon的运行中，设置Trap特定信号的处理方法，特定信号有SIGINT，SIGTERM以及SIGQUIT；当程序捕获到SIGINT或者SIGTERM信号时，执行相应的善后操作，最后保证Docker Daemon程序退出。

**/pkg/signal/trap.go**

```go
//Trap sets up a simplified signal "trap", appropriate for common
// behavior expected from a vanilla unix command-line tool in general
// (and the Docker engine in particular).
//
// * If SIGINT or SIGTERM are received, `cleanup` is called, then the process is terminated.
// * If SIGINT or SIGTERM are repeated 3 times before cleanup is complete, then cleanup is
// skipped and the process terminated directly.
// * If "DEBUG" is set in the environment, SIGQUIT causes an exit without cleanup.
//
func Trap(cleanup func()) {
    c := make(chan os.Signal, 1)
    signals := []os.Signal{os.Interrupt, syscall.SIGTERM}
    if os.Getenv("DEBUG") == "" {
        signals = append(signals, syscall.SIGQUIT)
    }
    gosignal.Notify(c, signals...)
    go func() {
        interruptCount := uint32(0)
        for sig := range c {
            go func(sig os.Signal) {
                log.Printf("Received signal '%v', starting shutdown of docker.../n", sig)
                switch sig {
                case os.Interrupt, syscall.SIGTERM:
                    // If the user really wants to interrupt, let him do so.
                    if atomic.LoadUint32(&interruptCount) < 3 {
                        atomic.AddUint32(&interruptCount, 1)
                        // Initiate the cleanup only once
                        if atomic.LoadUint32(&interruptCount) == 1 {
                            // Call cleanup handler
                            cleanup()
                            os.Exit(0)
                        } else {
                            return
                        }
                    } else {
                        log.Printf("Force shutdown of docker, interrupting cleanup/n")
                    }
                case syscall.SIGQUIT:
                }
                os.Exit(128 + int(sig.(syscall.Signal)))
            }(sig)
        }
    }()
} 
```

- 创建并设置一个channel，用于发送信号通知；
- 定义signals数组变量，初始值为os.SIGINT, os.SIGTERM;若环境变量DEBUG为空的话，则添加os.SIGQUIT至signals数组；
- 通过gosignal.Notify(c, signals...)中Notify函数来实现将接收到的signal信号传递给c。需要注意的是只有signals中被罗列出的信号才会被传递给c，其余信号会被直接忽略；
- 创建一个goroutine来处理具体的signal信号，当信号类型为os.Interrupt或者syscall.SIGTERM时，执行传入Trap函数的具体执行方法，形参为cleanup(),实参为eng.Shutdown。

Shutdown()函数的定义位于[./docker/engine/engine.go](https://github.com/docker/docker/blob/v1.2.0/engine/engine.go#L153)，主要做的工作是为Docker Daemon的关闭做一些善后工作。

**/engine/engine.go**

```go
// Shutdown permanently shuts down eng as follows:
// - It refuses all new jobs, permanently.
// - It waits for all active jobs to complete (with no timeout)
// - It calls all shutdown handlers concurrently (if any)
// - It returns when all handlers complete, or after 15 seconds,
//    whichever happens first.
func (eng *Engine) Shutdown() {
    eng.l.Lock()
    if eng.shutdown {
        eng.l.Unlock()
        return
    }
    eng.shutdown = true
    eng.l.Unlock()
    // We don't need to protect the rest with a lock, to allow
    // for other calls to immediately fail with "shutdown" instead
    // of hanging for 15 seconds.
    // This requires all concurrent calls to check for shutdown, otherwise
    // it might cause a race.
    // Wait for all jobs to complete.
    // Timeout after 5 seconds.
    tasksDone := make(chan struct{})
    go func() {
        eng.tasks.Wait()
        close(tasksDone)
    }()
    select {
    case <-time.After(time.Second * 5):
    case <-tasksDone:
    }
    // Call shutdown handlers, if any.
    // Timeout after 10 seconds.
    var wg sync.WaitGroup
    for _, h := range eng.onShutdown {
        wg.Add(1)
        go func(h func()) {
            defer wg.Done()
            h()
        }(h)
    }
    done := make(chan struct{})
    go func() {
        wg.Wait()
        close(done)
    }()
    select {
    case <-time.After(time.Second * 10):
    case <-done:
    }
    return
}
```

- Docker Daemon不再接收任何新的Job；
- Docker Daemon等待所有存活的Job执行完毕；
- Docker Daemon调用所有shutdown的处理方法；
- 当所有的handler执行完毕，或者15秒之后，Shutdown()函数返回。

由于在signal.Trap( eng.Shutdown )函数的具体实现中执行eng.Shutdown，在执行完eng.Shutdown之后，随即执行[os.Exit(0)](https://github.com/docker/docker/blob/v1.2.0/pkg/signal/trap.go#L41)，完成当前程序的立即退出。

## 3.5. 加载builtins

**/docker/daemon.go**

```go
if err := builtins.Register(eng); err != nil {
    log.Fatal(err)
}
```

为engine注册多个Handler，以便后续在执行相应任务时，运行指定的Handler。

这些Handler包括：

- 网络初始化、
- web API服务、
- 事件查询、
- 版本查看、
- Docker Registry验证与搜索。

**/builtins/builtins.go**

```go
func Register(eng *engine.Engine) error {
    if err := daemon(eng); err != nil {
        return err
    }
    if err := remote(eng); err != nil {
        return err
    }
    if err := events.New().Install(eng); err != nil {
        return err
    }
    if err := eng.Register("version", dockerVersion); err != nil {
        return err
    }
    return registry.NewService().Install(eng)
}
```

### 3.5.1. 注册初始化网络驱动的Handler

daemon(eng)的实现过程，主要为eng对象注册了一个key为”init_networkdriver”的Handler，该Handler的值为bridge.InitDriver函数，代码如下：

**/builtins/builtins.go**

```go
func daemon(eng *engine.Engine) error {
    return eng.Register("init_networkdriver", bridge.InitDriver)
}
```

需要注意的是，向eng对象注册Handler，并不代表Handler的值函数会被直接运行，如bridge.InitDriver，并不会直接运行，而是将bridge.InitDriver的函数入口，写入eng的handlers属性中。

**/daemon/networkdriver/bridge/driver.go**

```go
func InitDriver(job *engine.Job) engine.Status {
    var (
        network        *net.IPNet
        enableIPTables = job.GetenvBool("EnableIptables")
        icc            = job.GetenvBool("InterContainerCommunication")
        ipForward      = job.GetenvBool("EnableIpForward")
        bridgeIP       = job.Getenv("BridgeIP")
    )
 
    if defaultIP := job.Getenv("DefaultBindingIP"); defaultIP != "" {
        defaultBindingIP = net.ParseIP(defaultIP)
    }
 
    bridgeIface = job.Getenv("BridgeIface")
    usingDefaultBridge := false
    if bridgeIface == "" {
        usingDefaultBridge = true
        bridgeIface = DefaultNetworkBridge
    }
 
    addr, err := networkdriver.GetIfaceAddr(bridgeIface)
    if err != nil {
        // If we're not using the default bridge, fail without trying to create it
        if !usingDefaultBridge {
            job.Logf("bridge not found: %s", bridgeIface)
            return job.Error(err)
        }
        // If the iface is not found, try to create it
        job.Logf("creating new bridge for %s", bridgeIface)
        if err := createBridge(bridgeIP); err != nil {
            return job.Error(err)
        }
 
        job.Logf("getting iface addr")
        addr, err = networkdriver.GetIfaceAddr(bridgeIface)
        if err != nil {
            return job.Error(err)
        }
        network = addr.(*net.IPNet)
    } else {
        network = addr.(*net.IPNet)
        // validate that the bridge ip matches the ip specified by BridgeIP
        if bridgeIP != "" {
            bip, _, err := net.ParseCIDR(bridgeIP)
            if err != nil {
                return job.Error(err)
            }
            if !network.IP.Equal(bip) {
                return job.Errorf("bridge ip (%s) does not match existing bridge configuration %s", network.IP, bip)
            }
        }
    }
 
    // Configure iptables for link support
    if enableIPTables {
        if err := setupIPTables(addr, icc); err != nil {
            return job.Error(err)
        }
    }
 
    if ipForward {
        // Enable IPv4 forwarding
        if err := ioutil.WriteFile("/proc/sys/net/ipv4/ip_forward", []byte{'1', '/n'}, 0644); err != nil {
            job.Logf("WARNING: unable to enable IPv4 forwarding: %s/n", err)
        }
    }
 
    // We can always try removing the iptables
    if err := iptables.RemoveExistingChain("DOCKER"); err != nil {
        return job.Error(err)
    }
 
    if enableIPTables {
        chain, err := iptables.NewChain("DOCKER", bridgeIface)
        if err != nil {
            return job.Error(err)
        }
        portmapper.SetIptablesChain(chain)
    }
 
    bridgeNetwork = network
 
    // https://github.com/docker/docker/issues/2768
    job.Eng.Hack_SetGlobalVar("httpapi.bridgeIP", bridgeNetwork.IP)
 
    for name, f := range map[string]engine.Handler{
        "allocate_interface": Allocate,
        "release_interface":  Release,
        "allocate_port":      AllocatePort,
        "link":               LinkContainers,
    } {
        if err := job.Eng.Register(name, f); err != nil {
            return job.Error(err)
        }
    }
    return engine.StatusOK
}
```

Bridge.InitDriver的作用：

- 获取为Docker服务的网络设备的地址；
- 创建指定IP地址的网桥；
- 配置网络iptables规则；
- 另外还为eng对象注册了多个Handler,如 ”allocate_interface”， ”release_interface”， ”allocate_port”，”link”。

### 3.5.2. 注册API服务的Handler

remote(eng)的实现过程，主要为eng对象注册了两个Handler，分别为”serveapi”与”acceptconnections”。代码实现如下：

**/builtins/builtins.go**

```go
func remote(eng *engine.Engine) error {
    if err := eng.Register("serveapi", apiserver.ServeApi); err != nil {
        return err
    }
    return eng.Register("acceptconnections", apiserver.AcceptConnections)
}
```

注册的两个Handler名称分别为”serveapi”与”acceptconnections”

- ServeApi执行时，通过循环多种协议，创建出goroutine来配置指定的http.Server，最终为不同的协议请求服务；
- AcceptConnections的实现主要是为了通知init守护进程，Docker Daemon已经启动完毕，可以让Docker Daemon进程接受请求。(守护进程)

### 3.5.3. 注册events事件的Handler

events.New().Install(eng)的实现过程，为Docker注册了多个event事件，功能是给Docker用户提供API，使得用户可以通过这些API查看Docker内部的events信息，log信息以及subscribers_count信息。

**/events/events.go**

```go
type Events struct {
    mu          sync.RWMutex
    events      []*utils.JSONMessage
    subscribers []listener
}
func New() *Events {
    return &Events{
        events: make([]*utils.JSONMessage, 0, eventsLimit),
    }
}
// Install installs events public api in docker engine
func (e *Events) Install(eng *engine.Engine) error {
    // Here you should describe public interface
    jobs := map[string]engine.Handler{
        "events":            e.Get,
        "log":               e.Log,
        "subscribers_count": e.SubscribersCount,
    }
    for name, job := range jobs {
        if err := eng.Register(name, job); err != nil {
            return err
        }
    }
    return nil
}
```

### 3.5.4. 注册版本的Handler

eng.Register(“version”,dockerVersion)的实现过程，向eng对象注册key为”version”，value为”dockerVersion”执行方法的Handler，dockerVersion的执行过程中，会向名为version的job的标准输出中写入Docker的版本，Docker API的版本，git版本，Go语言运行时版本以及操作系统等版本信息。

**/builtins/builtins.go**

```go
// builtins jobs independent of any subsystem
func dockerVersion(job *engine.Job) engine.Status {
    v := &engine.Env{}
    v.SetJson("Version", dockerversion.VERSION)
    v.SetJson("ApiVersion", api.APIVERSION)
    v.Set("GitCommit", dockerversion.GITCOMMIT)
    v.Set("GoVersion", runtime.Version())
    v.Set("Os", runtime.GOOS)
    v.Set("Arch", runtime.GOARCH)
    if kernelVersion, err := kernel.GetKernelVersion(); err == nil {
        v.Set("KernelVersion", kernelVersion.String())
    }
    if _, err := v.WriteTo(job.Stdout); err != nil {
        return job.Error(err)
    }
    return engine.StatusOK
}
```

### 3.5.5. 注册registry的Handler

registry.NewService().Install(eng)的实现过程位于[./docker/registry/service.go](https://github.com/docker/docker/blob/v1.2.0/registry/service.go#L25)，在eng对象对外暴露的API信息中添加docker registry的信息。当registry.NewService()成功被Install安装完毕的话，则有两个调用能够被eng使用：”auth”，向公有registry进行认证；”search”，在公有registry上搜索指定的镜像。

**/registry/service.go**

```go
// NewService returns a new instance of Service ready to be
// installed no an engine.
func NewService() *Service {
    return &Service{}
}
// Install installs registry capabilities to eng.
func (s *Service) Install(eng *engine.Engine) error {
    eng.Register("auth", s.Auth)
    eng.Register("search", s.Search)
    return nil
}
```

## 3.6. 使用goroutine加载daemon对象

执行完builtins的加载，回到mainDaemon()的执行，通过一个goroutine来加载daemon对象并开始运行。这一环节的执行，主要包含三个步骤：

- 通过init函数中初始化的daemonCfg与eng对象来创建一个daemon对象d；(守护进程)
- 通过daemon对象的Install函数，向eng对象中注册众多的Handler；
- 在Docker Daemon启动完毕之后，运行名为”acceptconnections”的job，主要工作为向init守护进程发送”READY=1”信号，以便开始正常接受请求。

**/docker/daemon.go**

```go
// load the daemon in the background so we can immediately start
// the http api so that connections don't fail while the daemon
// is booting
go func() {
    d, err := daemon.NewDaemon(daemonCfg, eng)
    if err != nil {
        log.Fatal(err)
    }
    if err := d.Install(eng); err != nil {
        log.Fatal(err)
    }
    // after the daemon is done setting up we can tell the api to start
    // accepting connections
    if err := eng.Job("acceptconnections").Run(); err != nil {
        log.Fatal(err)
    }
}()
```

### 3.6.1. 创建daemon对象

**/docker/daemon.go**

```go
d, err := daemon.NewDaemon(daemonCfg, eng)
if err != nil {
    log.Fatal(err)
}
```

daemon.NewDaemon(daemonCfg, eng)是创建daemon对象d的核心部分。主要作用为初始化Docker Daemon的基本环境，如处理config参数，验证系统支持度，配置Docker工作目录，设置与加载多种driver，创建graph环境等，验证DNS配置等。具体参考[NewDaemon](http://wiki.haplat.net/display/~huwh/NewDaemon) 。

### 3.6.2. 通过daemon对象为engine注册Handler

当创建完daemon对象，goroutine执行d.Install(eng)

**/daemon/daemon.go**

```go
type Daemon struct {
    repository     string
    sysInitPath    string
    containers     *contStore
    graph          *graph.Graph
    repositories   *graph.TagStore
    idIndex        *truncindex.TruncIndex
    sysInfo        *sysinfo.SysInfo
    volumes        *graph.Graph
    eng            *engine.Engine
    config         *Config
    containerGraph *graphdb.Database
    driver         graphdriver.Driver
    execDriver     execdriver.Driver
}
// Install installs daemon capabilities to eng.
func (daemon *Daemon) Install(eng *engine.Engine) error {
    // FIXME: rename "delete" to "rm" for consistency with the CLI command
    // FIXME: rename ContainerDestroy to ContainerRm for consistency with the CLI command
    // FIXME: remove ImageDelete's dependency on Daemon, then move to graph/
    for name, method := range map[string]engine.Handler{
        "attach":            daemon.ContainerAttach,
        "build":             daemon.CmdBuild,
        "commit":            daemon.ContainerCommit,
        "container_changes": daemon.ContainerChanges,
        "container_copy":    daemon.ContainerCopy,
        "container_inspect": daemon.ContainerInspect,
        "containers":        daemon.Containers,
        "create":            daemon.ContainerCreate,
        "delete":            daemon.ContainerDestroy,
        "export":            daemon.ContainerExport,
        "info":              daemon.CmdInfo,
        "kill":              daemon.ContainerKill,
        "logs":              daemon.ContainerLogs,
        "pause":             daemon.ContainerPause,
        "resize":            daemon.ContainerResize,
        "restart":           daemon.ContainerRestart,
        "start":             daemon.ContainerStart,
        "stop":              daemon.ContainerStop,
        "top":               daemon.ContainerTop,
        "unpause":           daemon.ContainerUnpause,
        "wait":              daemon.ContainerWait,
        "image_delete":      daemon.ImageDelete, // FIXME: see above
    } {
        if err := eng.Register(name, method); err != nil {
            return err
        }
    }
    if err := daemon.Repositories().Install(eng); err != nil {
        return err
    }
    // FIXME: this hack is necessary for legacy integration tests to access
    // the daemon object.
    eng.Hack_SetGlobalVar("httpapi.daemon", daemon)
    return nil
}
```

以上代码的实现分为三部分：

- 向eng对象中注册众多的Handler对象；
- daemon.Repositories().Install(eng)实现了向eng对象注册多个与image相关的Handler，Install的实现位于[./docker/graph/service.go](https://github.com/docker/docker/blob/v1.2.0/graph/service.go#L12)；
- eng.Hack_SetGlobalVar("httpapi.daemon", daemon)实现向eng对象中map类型的hack对象中添加一条记录，key为”httpapi.daemon”，value为daemon。

### 3.6.3. 运行acceptconnections的job

**/docker/daemon.go**

```go
if err := eng.Job("acceptconnections").Run(); err != nil {
    log.Fatal(err)
}
```

在goroutine内部最后运行名为”acceptconnections”的job，主要作用是通知init守护进程，Docker Daemon可以开始接受请求了。

首先执行eng.Job("acceptconnections")，返回一个Job，随后再执行eng.Job("acceptconnections").Run()，也就是该执行Job的run函数。

**/engine/engine.go**

```go
// Job creates a new job which can later be executed.
// This function mimics `Command` from the standard os/exec package.
func (eng *Engine) Job(name string, args ...string) *Job {
    job := &Job{
        Eng:    eng,
        Name:   name,
        Args:   args,
        Stdin:  NewInput(),
        Stdout: NewOutput(),
        Stderr: NewOutput(),
        env:    &Env{},
    }
    if eng.Logging {
        job.Stderr.Add(utils.NopWriteCloser(eng.Stderr))
    }
    // Catchall is shadowed by specific Register.
    if handler, exists := eng.handlers[name]; exists {
        job.handler = handler
    } else if eng.catchall != nil && name != "" {
        // empty job names are illegal, catchall or not.
        job.handler = eng.catchall
    }
    return job
} 
```

1. 首先创建一个类型为Job的job对象，该对象中Eng属性为函数的调用者eng，Name属性为”acceptconnections”，没有参数传入。
2. 另外在eng对象所有的handlers属性中寻找键为”acceptconnections”记录的值，由于在加载builtins操作中的remote(eng)中已经向eng注册过这样的一条记录，key为”acceptconnections”，value为apiserver.AcceptConnections。
3. 因此job对象的handler为apiserver.AcceptConnections。
4. 最后返回已经初始化完毕的对象job。

创建完job对象之后，随即执行该job对象的run()函数。

**/engine/job.go**

```go
// A job is the fundamental unit of work in the docker engine.
// Everything docker can do should eventually be exposed as a job.
// For example: execute a process in a container, create a new container,
// download an archive from the internet, serve the http api, etc.
//
// The job API is designed after unix processes: a job has a name, arguments,
// environment variables, standard streams for input, output and error, and
// an exit status which can indicate success (0) or error (anything else).
//
// One slight variation is that jobs report their status as a string. The
// string "0" indicates success, and any other strings indicates an error.
// This allows for richer error reporting.
//
type Job struct {
    Eng     *Engine
    Name    string
    Args    []string
    env     *Env
    Stdout  *Output
    Stderr  *Output
    Stdin   *Input
    handler Handler
    status  Status
    end     time.Time
}
type Status int
const (
    StatusOK       Status = 0
    StatusErr      Status = 1
    StatusNotFound Status = 127
)
// Run executes the job and blocks until the job completes.
// If the job returns a failure status, an error is returned
// which includes the status.
func (job *Job) Run() error {
    if job.Eng.IsShutdown() {
        return fmt.Errorf("engine is shutdown")
    }
    // FIXME: this is a temporary workaround to avoid Engine.Shutdown
    // waiting 5 seconds for server/api.ServeApi to complete (which it never will)
    // everytime the daemon is cleanly restarted.
    // The permanent fix is to implement Job.Stop and Job.OnStop so that
    // ServeApi can cooperate and terminate cleanly.
    if job.Name != "serveapi" {
        job.Eng.l.Lock()
        job.Eng.tasks.Add(1)
        job.Eng.l.Unlock()
        defer job.Eng.tasks.Done()
    }
    // FIXME: make this thread-safe
    // FIXME: implement wait
    if !job.end.IsZero() {
        return fmt.Errorf("%s: job has already completed", job.Name)
    }
    // Log beginning and end of the job
    job.Eng.Logf("+job %s", job.CallString())
    defer func() {
        job.Eng.Logf("-job %s%s", job.CallString(), job.StatusString())
    }()
    var errorMessage = bytes.NewBuffer(nil)
    job.Stderr.Add(errorMessage)
    if job.handler == nil {
        job.Errorf("%s: command not found", job.Name)
        job.status = 127
    } else {
        job.status = job.handler(job)
        job.end = time.Now()
    }
    // Wait for all background tasks to complete
    if err := job.Stdout.Close(); err != nil {
        return err
    }
    if err := job.Stderr.Close(); err != nil {
        return err
    }
    if err := job.Stdin.Close(); err != nil {
        return err
    }
    if job.status != 0 {
        return fmt.Errorf("%s", Tail(errorMessage, 1))
    }
    return nil
}
```

Run()函数的实现位于[./docker/engine/job.go](https://github.com/docker/docker/blob/v1.2.0/engine/job.go#L48)，该函数执行指定的job，并在job执行完成前一直阻塞。对于名为”acceptconnections”的job对象，运行代码为[job.status = job.handler(job)](https://github.com/docker/docker/blob/v1.2.0/engine/job.go#L79)，由于job.handler值为apiserver.AcceptConnections，故真正执行的是job.status = apiserver.AcceptConnections(job)。

进入AcceptConnections的具体实现，位于[./docker/api/server/server.go](https://github.com/docker/docker/blob/v1.2.0/api/server/server.go#L1370),如下：

**/api/server/server.go**

```go
func AcceptConnections(job *engine.Job) engine.Status {
    // Tell the init daemon we are accepting requests
    go  systemd.SdNotify("READY=1")
    if activationLock != nil {
        close(activationLock)
    }
    return engine.StatusOK
}
```

重点为go systemd.SdNotify("READY=1")的实现，位于[./docker/pkg/system/sd_notify.go](https://github.com/docker/docker/blob/v1.2.0/pkg/systemd/sd_notify.go#L12)，主要作用是通知init守护进程Docker Daemon的启动已经全部完成，潜在的功能是使得Docker Daemon开始接受Docker Client发送来的API请求。

至此，已经完成通过goroutine来加载daemon对象并运行。

## 3.7. 打印Docker版本及驱动信息

显示docker的版本信息，以及ExecDriver和GraphDriver这两个驱动的具体信息

**/docker/daemon.go**

```go
// TODO actually have a resolved graphdriver to show?
log.Printf("docker daemon: %s %s; execdriver: %s; graphdriver: %s",
    dockerversion.VERSION,
    dockerversion.GITCOMMIT,
    daemonCfg.ExecDriver,
    daemonCfg.GraphDriver,
)
```

## 3.8. serveapi的创建与运行

打印部分Docker具体信息之后，Docker Daemon立即创建并运行名为”serveapi”的job，主要作用为让Docker Daemon提供API访问服务。

**/docker/daemon.go**

```go
// Serve api
job := eng.Job("serveapi", flHosts...)
job.SetenvBool("Logging", true)
job.SetenvBool("EnableCors", *flEnableCors)
job.Setenv("Version", dockerversion.VERSION)
job.Setenv("SocketGroup", *flSocketGroup)
job.SetenvBool("Tls", *flTls)
job.SetenvBool("TlsVerify", *flTlsVerify)
job.Setenv("TlsCa", *flCa)
job.Setenv("TlsCert", *flCert)
job.Setenv("TlsKey", *flKey)
job.SetenvBool("BufferRequests", true)
if err := job.Run(); err != nil {
    log.Fatal(err)
}
```

1. 创建一个名为”serveapi”的job，并将flHosts的值赋给job.Args。flHost的作用主要是为Docker Daemon提供使用的协议与监听的地址。
2. Docker Daemon为该job设置了众多的环境变量，如安全传输层协议的环境变量等。最后通过job.Run()运行该serveapi的job。

由于在eng中key为”serveapi”的handler，value为apiserver.ServeApi，故该job运行时，执行apiserver.ServeApi函数，位于[./docker/api/server/server.go](https://github.com/docker/docker/blob/v1.2.0/api/server/server.go#L1339)。ServeApi函数的作用主要是对于用户定义的所有支持协议，Docker Daemon均创建一个goroutine来启动相应的http.Server，分别为不同的协议服务。具体参考[Docker Server](http://wiki.haplat.net/display/~huwh/Docker+Server)。

参考：

- 《Docker源码分析》
