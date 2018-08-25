# 1. 创建Docker Client

​    Docker是一个client/server的架构，通过二进制文件docker创建Docker客户端将请求类型与参数发送给Docker Server，Docker Server具体执行命令调用。
Docker Client运行流程图如下：
<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510578124/article/docker/dockerClient/docker-client-flow.jpg" width="60%"/>

说明：本文分析的代码为Docker 1.2.0版本。

## 1.1. Docker命令flag参数解析

Docker Server与Docker Client由可执行文件docker命令创建并启动。

- Docker Server的启动：docker -d或docker --daemon=true
- Docker Client的启动：docker --daemon=false ps等

docker参数分为两类：

- 命令行参数（flag参数）:--daemon=true,-d
- 实际请求参数:ps ,images, pull, push等

**/docker/docker.go**

```go
func main() {
       if reexec.Init() {
           return
       }
       flag.Parse()
       // FIXME: validate daemon flags here
       ......
   }
```

reexec.Init()作用：协调execdriver与容器创建时dockerinit的关系。如果返回值为真则直接退出运行，否则继续执行。判断reexec.Init()之后，调用flag.Parse()解析命令行中的flag参数。

**/docker/flag.go**

```go
var (
      flVersion     = flag.Bool([]string{"v", "-version"}, false, "Print version information and quit")
      flDaemon      = flag.Bool([]string{"d", "-daemon"}, false, "Enable daemon mode")
      flDebug       = flag.Bool([]string{"D", "-debug"}, false, "Enable debug mode")
      flSocketGroup = flag.String([]string{"G", "-group"}, "docker", "Group to assign the unix socket specified by -H when running in daemon mode/nuse '' (the empty string) to disable setting of a group")
      flEnableCors  = flag.Bool([]string{"#api-enable-cors", "-api-enable-cors"}, false, "Enable CORS headers in the remote API")
      flTls         = flag.Bool([]string{"-tls"}, false, "Use TLS; implied by tls-verify flags")
      flTlsVerify   = flag.Bool([]string{"-tlsverify"}, false, "Use TLS and verify the remote (daemon: verify client, client: verify daemon)")
 
      // these are initialized in init() below since their default values depend on dockerCertPath which isn't fully initialized until init() runs
      flCa    *string
      flCert  *string
      flKey   *string
      flHosts []string
  )
 
  func init() {
      flCa = flag.String([]string{"-tlscacert"}, filepath.Join(dockerCertPath, defaultCaFile), "Trust only remotes providing a certificate signed by the CA given here")
      flCert = flag.String([]string{"-tlscert"}, filepath.Join(dockerCertPath, defaultCertFile), "Path to TLS certificate file")
      flKey = flag.String([]string{"-tlskey"}, filepath.Join(dockerCertPath, defaultKeyFile), "Path to TLS key file")
      opts.HostListVar(&flHosts, []string{"H", "-host"}, "The socket(s) to bind to in daemon mode/nspecified using one or more tcp://host:port, unix:///path/to/socket, fd://* or fd://socketfd.")
  }
```

flag.go定义了flag参数，并执行了init的初始化。

Go中的init函数

1. 用于程序执行前包的初始化工作，比如初始化变量
2. 每个包或源文件可以包含多个init函数
3. init函数不能被调用，而是在mian函数调用前自动被调用
4. 不同init函数的执行顺序，按照包导入的顺序执行

当解析到第一个非flag参数时，flag解析工作就结束。例如docker --daemon=flase --version=false ps

- 完成flag的解析，--daemon=false
- 遇到第一个非flag参数ps，则将ps及其后的参数存入flag.Args()，以便执行之后的具体请求。

## 1.2. 处理flag参数并收集Docker Client的配置信息

处理的flag参数有flVersion,flDebug,flDaemon,flTlsVerify以及flTls。

**/docker/docker.go**

```go
func main() {
    ......
    if len(flHosts) == 0 {
        defaultHost := os.Getenv("DOCKER_HOST")
        if defaultHost == "" || *flDaemon {
            // If we do not have a host, default to unix socket
            defaultHost = fmt.Sprintf("unix://%s", api.DEFAULTUNIXSOCKET)
        }
        if _, err := api.ValidateHost(defaultHost); err != nil {
            log.Fatal(err)
        }
        flHosts = append(flHosts, defaultHost)
    }
    ......
}
```

flHosts的作用是为Docker Client提供所要连接的host对象，也就是为Docker Server提供所要监听的对象。
当flHosts为空，默认取环境变量DOCKER_HOST，若仍为空或flDaemon为真，则设置为unix socket，值为[unix:///var/run/docker.sock。取自/api/common.go中的常量DEFAULTUNIXSOCKET。]()

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

若flDaemon为真，表示启动Docker Daemon，调用/docker/daemon.go中的func mainDaemon()。

**/docker/docker.go**

```go
if len(flHosts) > 1 {
    log.Fatal("Please specify only one -H")
}
protoAddrParts := strings.SplitN(flHosts[0], "://", 2)
```

protoAddrParts的作用是解析出Docker Client 与Docker Server建立通信的协议与地址，通过strings.SplitN函数分割存储。flHosts[0]的值可以是[tcp://0.0.0.0.2375或者unix:///var/run/docker.sock等。]()

**/docker/docker.go**

```go
var (
    cli       *client.DockerCli
    tlsConfig tls.Config
)
tlsConfig.InsecureSkipVerify = true
```

tlsConfig对象的创建是为了保障cli在传输数据的时候遵循安全传输层协议（TLS）。flTlsVerity参数为真，则说明Docker Client 需Docker Server一起验证连接的安全性，如果flTls和flTlsVerity两个参数中有一个为真，则说明需要加载并发送客户端的证书。

**/docker/flags.go**

```go
flTls         = flag.Bool([]string{"-tls"}, false, "Use TLS; implied by tls-verify flags")
flTlsVerify   = flag.Bool([]string{"-tlsverify"}, false, "Use TLS and verify the remote (daemon: verify client, client: verify daemon)")
```

## 1.3. 如何创建Docker Client

**/docker/docker.go**

```go
if *flTls || *flTlsVerify {
    cli = client.NewDockerCli(os.Stdin, os.Stdout, os.Stderr, protoAddrParts[0], protoAddrParts[1], &tlsConfig)
} else {
    cli = client.NewDockerCli(os.Stdin, os.Stdout, os.Stderr, protoAddrParts[0], protoAddrParts[1], nil)
}
```

在已有配置参数的情况下，通过/api/client/cli.go中的NewDockerCli方法创建Docker Client实例cli。

**/api/client/cli.go**

```go
type DockerCli struct {
    proto      string
    addr       string
    configFile *registry.ConfigFile
    in         io.ReadCloser
    out        io.Writer
    err        io.Writer
    isTerminal bool
    terminalFd uintptr
    tlsConfig  *tls.Config
    scheme     string
}
 
func NewDockerCli(in io.ReadCloser, out, err io.Writer, proto, addr string, tlsConfig *tls.Config) *DockerCli {
    var (
        isTerminal = false
        terminalFd uintptr
        scheme     = "http"
    )
 
    if tlsConfig != nil {
        scheme = "https"
    }
 
    if in != nil {
        if file, ok := out.(*os.File); ok {
            terminalFd = file.Fd()
            isTerminal = term.IsTerminal(terminalFd)
        }
    }
 
    if err == nil {
        err = out
    }
    return &DockerCli{
        proto:      proto,
        addr:       addr,
        in:         in,
        out:        out,
        err:        err,
        isTerminal: isTerminal,
        terminalFd: terminalFd,
        tlsConfig:  tlsConfig,
        scheme:     scheme,
    }
}
```

# 2. Docke命令执行

## 2.1. Docker Client解析请求命令

创建Docker Client，docker命令中的请求参数（例如ps，经flag解析后放入flag.Args()），分析请求参数及请求的类型，转义为Docker Server可识别的请求后发给Docker Server。

**/docker/docker.go**

```go
if err := cli.Cmd(flag.Args()...); err != nil {
    if sterr, ok := err.(*utils.StatusError); ok {
        if sterr.Status != "" {
            log.Println(sterr.Status)
        }
        os.Exit(sterr.StatusCode)
    }
    log.Fatal(err)
}
```

解析flag.Args()的具体请求参数，执行cli.Cmd函数。代码在/api/client/cli.go

**/api/client/cli.go**

```go
    // Cmd executes the specified command
    func (cli *DockerCli) Cmd(args ...string) error {
        if len(args) > 0 {
            method, exists := cli.getMethod(args[0])
            if !exists {
                fmt.Println("Error: Command not found:", args[0])
                return cli.CmdHelp(args[1:]...)
            }
            return method(args[1:]...)
        }
        return cli.CmdHelp(args...)
    }
 
method, exists := cli.getMethod(args[0])获取请求参数，例如docker pull ImageName，args[0]等于pull。
 
    func (cli *DockerCli) getMethod(name string) (func(...string) error, bool) {
        if len(name) == 0 {
            return nil, false
        }
        methodName := "Cmd" + strings.ToUpper(name[:1]) + strings.ToLower(name[1:])
        method := reflect.ValueOf(cli).MethodByName(methodName)
        if !method.IsValid() {
            return nil, false
        }
        return method.Interface().(func(...string) error), true
    }
```

在getMethod中，返回method值为“CmdPull”。最后执行method(args[1:]...)，即CmdPull(args[1:]...)。

## 2.2. Docker Client执行请求命令

docker pull ImageName中，即执行CmdPull(args[1:]...)，args[1:]即为ImageName。命令代码在/api/client/command.go。

**/api/client/commands.go**

```go
func (cli *DockerCli) CmdPull(args ...string) error {
    cmd := cli.Subcmd("pull", "NAME[:TAG]", "Pull an image or a repository from the registry")
    tag := cmd.String([]string{"#t", "#-tag"}, "", "Download tagged image in a repository")
    if err := cmd.Parse(args); err != nil {
        return nil
    }
    ...
}
```

将args参数进行第二次flag参数解析，解析过程中先提取是否有符合tag这个flag的参数，若有赋值给tag参数，其余存入cmd.NArg()，若没有则所有的参数存入cmd.NArg()中。

**/api/client/commands.go**

```go
var (
     v      = url.Values{}
     remote = cmd.Arg(0)
 )
 
 v.Set("fromImage", remote)
 
 if *tag == "" {
     v.Set("tag", *tag)
 }
 
 remote, _ = parsers.ParseRepositoryTag(remote)
 // Resolve the Repository name from fqn to hostname + name
 hostname, _, err := registry.ResolveRepositoryName(remote)
 if err != nil {
     return err
 }
```

通过remote变量先得到镜像的repository名称，并赋值给remote自身，随后解析改变后的remote，得出镜像所在的host地址，即Docker Registry的地址。若没有指定默认为Docker Hub地址[https://index.docker.io/v1/。]()

**/api/client/commands.go**

```go
cli.LoadConfigFile()
 
// Resolve the Auth config relevant for this server
authConfig := cli.configFile.ResolveAuthConfig(hostname)
```

通过cli对象获取与Docker Server的认证配置信息。

**/api/client/commands.go**

```go
pull := func(authConfig registry.AuthConfig) error {
    buf, err := json.Marshal(authConfig)
    if err != nil {
        return err
    }
    registryAuthHeader := []string{
        base64.URLEncoding.EncodeToString(buf),
    }
 
    return cli.stream("POST", "/images/create?"+v.Encode(), nil, cli.out, map[string][]string{
        "X-Registry-Auth": registryAuthHeader,
    })
}
```

定义pull函数：cli.stream("POST", "/images/create?"+v.Encode(),...)像Docker Server发送POST请求，请求url为“"/images/create?"+v.Encode()”，请求的认证信息为：map[string][]string{"X-Registry-Auth": registryAuthHeader,}

**/api/client/commands.go**

```go
if err := pull(authConfig); err != nil {
    if strings.Contains(err.Error(), "Status 401") {
        fmt.Fprintln(cli.out, "/nPlease login prior to pull:")
        if err := cli.CmdLogin(hostname); err != nil {
            return err
        }
        authConfig := cli.configFile.ResolveAuthConfig(hostname)
        return pull(authConfig)
    }
    return err
}
 
return nil
```

调用pull函数，实现下载请求发送。后续有Docker Server接收到请求后具体实现。

参考：

- 《Docker源码分析》
