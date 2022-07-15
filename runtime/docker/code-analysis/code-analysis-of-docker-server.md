# 1. Docker Server创建流程

Docker Server是Daemon Server的重要组成部分，功能：接收Docker Client发送的请求，并按照相应的路由规则实现请求的路由分发，最终将请求处理的结果返回给Docker Client。
Docker Daemon启动，在mainDaemon()运行的最后创建并运行serverapi的Job，让Docker Daemon提供API访问服务。
Docker Server的整个生命周期

1. 创建Docker Server的Job
2. 配置Job的环境变量
3. 触发执行Job

说明：本文分析的代码为Docker 1.2.0版本。

## 1.1. 创建“serverapi”的Job

**/docker/daemon.go**

```go
func mainDaemon() {
      ...
      // Serve api
      job := eng.Job("serveapi", flHosts...)
      ...
  }
```

运行serverapi的Job时，会执行该Job的处理方法api.ServeApi。

## 1.2. 配置Job环境变量

**/docker/daemon.go**

```go
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
```

参数分为两种

- 创建Job实例时，用指定参数直接初始化Job的Args属性
- 创建Job后，给Job添加指定的环境变量

| 环境变量名         | FLAG参数        | 默认     | 作用值                                |
| ------------- | ------------- | ------ | ---------------------------------- |
| Logging       |               | true   | 启用Docker容器的日志输出                    |
| EnableCors    | flEnableCors  | false  | 在远程API中提供CORS头                     |
| Version       |               |        | 显示Docker版本号                        |
| SocketGroup   | flSockerGroup | docker | 在daemon模式中unix domain socket分配用户组名 |
| Tls           | flTls         | false  | 使用TLS安全传输协议                        |
| TlsVerify     | flTlsVerify   | false  | 使用TLS并验证远程客户端                      |
| TlsCa         | flCa          |        | 指定CA文件路径                           |
| TlsCert       | flCert        |        | TLS证书文件路径                          |
| TlsKey        | flKey         |        | TLS密钥文件路径                          |
| BufferRequest |               | true   | 缓存Docker Client请求                  |

## 1.3. 运行Job

**/api/server/server.go**

```go
if err := job.Run(); err != nil {
    log.Fatal(err)
}
```

Docker在eng对象中注册过键位serverapi的处理方法，在运行Job的时候执行这个处理方法的值函数，相应的处理方法的值为api.ServeApi。

# 2. ServeApi运行流程

​     ServeApi属于Docker Server提供API服务的部分，作为一个监听请求、处理请求、响应请求的服务端，支持三种协议：TCP协议、UNIX Socket形式以及fd的形式。功能是：循环检查Docker Daemon支持的所有协议，并为每一种协议创建一个协程goroutine，并在协程内部配置一个服务于HTTP请求的服务端。

**/api/server/server.go**

```go
// ServeApi loops through all of the protocols sent in to docker and spawns
// off a go routine to setup a serving http.Server for each.
func ServeApi(job *engine.Job) engine.Status {
    if len(job.Args) == 0 {
        return job.Errorf("usage: %s PROTO://ADDR [PROTO://ADDR ...]", job.Name)
    }
    var (
        protoAddrs = job.Args
        chErrors   = make(chan error, len(protoAddrs))
    )
    activationLock = make(chan struct{})
 
    for _, protoAddr := range protoAddrs {
        protoAddrParts := strings.SplitN(protoAddr, "://", 2)
        if len(protoAddrParts) != 2 {
            return job.Errorf("usage: %s PROTO://ADDR [PROTO://ADDR ...]", job.Name)
        }
        go func() {
            log.Infof("Listening for HTTP on %s (%s)", protoAddrParts[0], protoAddrParts[1])
            chErrors <- ListenAndServe(protoAddrParts[0], protoAddrParts[1], job)
        }()
    }
 
    for i := 0; i < len(protoAddrs); i += 1 {
        err := <-chErrors
        if err != nil {
            return job.Error(err)
        }
    }
 
    return engine.StatusOK
}
```

ServeApi执行流程：

1. 检查Job参数，确保传入参数无误
2. 定义Docker Server的监听协议与地址，以及错误信息管理channel
3. 遍历协议地址，针对协议创建相应的服务端
4. 通过chErrors建立goroutine与主进程之间的协调关系

## 2.1. 判断Job参数

判断Job参数，job.Args，即数组flHost，若flHost的长度为0，则说明没有监听的协议与地址，参数有误。

**/api/server/server.go**

```go
func ServeApi(job *engine.Job) engine.Status {
    if len(job.Args) == 0 {
        return job.Errorf("usage: %s PROTO://ADDR [PROTO://ADDR ...]", job.Name)
    }
    ...
}
```

## 2.2. 定义监听协议与地址及错误信息

**/api/server/server.go**

```go
var (
       protoAddrs = job.Args
       chErrors   = make(chan error, len(protoAddrs))
   )
   activationLock = make(chan struct{})
```

定义protoAddrs[flHosts的内容]、chErrors[错误类型管道]与activationLock[同步serveapi和acceptconnections两个job执行的管道]三个变量，

## 2.3. 遍历协议地址

**/api/server/server.go**

```go
for _, protoAddr := range protoAddrs {
    protoAddrParts := strings.SplitN(protoAddr, "://", 2)
    if len(protoAddrParts) != 2 {
        return job.Errorf("usage: %s PROTO://ADDR [PROTO://ADDR ...]", job.Name)
    }
    go func() {
        log.Infof("Listening for HTTP on %s (%s)", protoAddrParts[0], protoAddrParts[1])
        chErrors <- ListenAndServe(protoAddrParts[0], protoAddrParts[1], job)
    }()
}
```

遍历协议地址，针对协议创建相应的服务端。协议地址

## 2.4. 协调chErrors与主进程关系

根据chErrors的值运行，如果chErrors这个管道中有错误内容，则ServerApi一次循环结束，若无错误内容，循环被阻塞。即chErrors确保ListenAndServe所对应的协程能和主函数ServeApi进行协调，如果协程出错，主函数ServeApi仍然可以捕获这样的错误，从而导致程序退出。

**/api/server/server.go**

```go
for i := 0; i < len(protoAddrs); i += 1 {
    err := <-chErrors
    if err != nil {
        return job.Error(err)
    }
}
return engine.StatusOK
```

# 3. ListenAndServe实现

ListenAndServe的功能：使Docker Server监听某一指定地址，并接收该地址的请求，并对以上请求路由转发至相应的处理方法处。
ListenAndServe执行流程：

1. 创建route路由实例
2. 创建listener监听实例
3. 创建http.Server
4. 启动API服务

流程图：
<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510578158/article/docker/dockerServer/DockerServerFlow.jpg" width="50%">

## 3.1. 创建route路由实例

**/api/server/server.go**

```go
// ListenAndServe sets up the required http.Server and gets it listening for
// each addr passed in and does protocol specific checking.
func ListenAndServe(proto, addr string, job *engine.Job) error {
    var l net.Listener
    r, err := createRouter(job.Eng, job.GetenvBool("Logging"), job.GetenvBool("EnableCors"), job.Getenv("Version"))
    if err != nil {
        return err
    }
    ...
}
```

路由实例的作用：负责Docker Server对外部请求的路由及转发。
实现过程：

1. 创建全新的route路由实例
2. 为route实例添加路由记录

### 3.1.1. 创建空路由实例

**/api/server/server.go**

```go
func createRouter(eng *engine.Engine, logging, enableCors bool, dockerVersion string) (*mux.Router, error) {
     r := mux.NewRouter()
     ...
 }
```

**/vendor/src/github.com/gorilla/mux/mux.go**

```go
// NewRouter returns a new router instance.
func NewRouter() *Router {
    return &Router{namedRoutes: make(map[string]*Route), KeepContext: false}
}
 
// This will send all incoming requests to the router.
type Router struct {
    // Configurable Handler to be used when no route matches.
    NotFoundHandler http.Handler
    // Parent route, if this is a subrouter.
    parent parentRoute
    // Routes to be matched, in order.
    routes []*Route
    // Routes by name for URL building.
    namedRoutes map[string]*Route
    // See Router.StrictSlash(). This defines the flag for new routes.
    strictSlash bool
    // If true, do not clear the request context after handling the request
    KeepContext bool
}
```

NewRoute()函数返回一个全新的route实例r，类型为mux.Router。实例初始化nameRoutes和KeepContext。

- nameRoutes：map类型，key为string类型，value为Route路由记录类型
- KeepContext：属性为false，则处理完请求后清除请求内容，不对请求做存储操作

mux.Router会通过一系列已经注册过的路由记录，来匹配接收的请求。先通过请求的URL或者其他条件找到相应的路由记录，并调用这条记录中的执行处理方法。
mux.Router特性

- 请求可以基于URL的主机名、路径、路径前缀、shemes、请求头和请求值、HTTP请求方法类型或者使用自定义的匹配规则
- URL主机名和路径可以通过一个正则表达式来表示
- 注册的URL可以直接被运用，也可以保留从而保证维护资源的使用
- 路由记录同样看可以作用于子路由记录

### 3.1.2. 添加路由记录

**/api/server/server.go**

```go
if os.Getenv("DEBUG") != "" {
       AttachProfiler(r)
   }
 
   m := map[string]map[string]HttpApiFunc{
       "GET": {
           "/_ping":                          ping,
           "/events":                         getEvents,
           "/info":                           getInfo,
           "/version":                        getVersion,
           "/images/json":                    getImagesJSON,
           "/images/viz":                     getImagesViz,
           "/images/search":                  getImagesSearch,
           "/images/{name:.*}/get":           getImagesGet,
           "/images/{name:.*}/history":       getImagesHistory,
           "/images/{name:.*}/json":          getImagesByName,
           "/containers/ps":                  getContainersJSON,
           "/containers/json":                getContainersJSON,
           "/containers/{name:.*}/export":    getContainersExport,
           "/containers/{name:.*}/changes":   getContainersChanges,
           "/containers/{name:.*}/json":      getContainersByName,
           "/containers/{name:.*}/top":       getContainersTop,
           "/containers/{name:.*}/logs":      getContainersLogs,
           "/containers/{name:.*}/attach/ws": wsContainersAttach,
       },
       "POST": {
           "/auth":                         postAuth,
           "/commit":                       postCommit,
           "/build":                        postBuild,
           "/images/create":                postImagesCreate,
           "/images/load":                  postImagesLoad,
           "/images/{name:.*}/push":        postImagesPush,
           "/images/{name:.*}/tag":         postImagesTag,
           "/containers/create":            postContainersCreate,
           "/containers/{name:.*}/kill":    postContainersKill,
           "/containers/{name:.*}/pause":   postContainersPause,
           "/containers/{name:.*}/unpause": postContainersUnpause,
           "/containers/{name:.*}/restart": postContainersRestart,
           "/containers/{name:.*}/start":   postContainersStart,
           "/containers/{name:.*}/stop":    postContainersStop,
           "/containers/{name:.*}/wait":    postContainersWait,
           "/containers/{name:.*}/resize":  postContainersResize,
           "/containers/{name:.*}/attach":  postContainersAttach,
           "/containers/{name:.*}/copy":    postContainersCopy,
       },
       "DELETE": {
           "/containers/{name:.*}": deleteContainers,
           "/images/{name:.*}":     deleteImages,
       },
       "OPTIONS": {
           "": optionsHandler,
       },
   }
```

m的类型为映射，key表示HTTP的请求类型，如GET、POST、DELETE等，value为映射类型，代表URL与执行处理方法的映射。

**/api/server/server.go**

```go
type HttpApiFunc func(eng *engine.Engine, version version.Version, w http.ResponseWriter, r *http.Request, vars map[string]string) error
```

## 3.2. 创建listener监听实例

路由模块完成请求的路由与分发，监听模块完成请求的监听功能。Listener是一种面向流协议的通用网络监听模块。

**/api/server/server.go**

```go
var l net.Listener
 ...
 if job.GetenvBool("BufferRequests") {
     l, err = listenbuffer.NewListenBuffer(proto, addr, activationLock)
 } else {
     l, err = net.Listen(proto, addr)
```

Listenbuffer的作用：让Docker Server立即监听指定协议地址上的请求，但将这些请求暂时先缓存下来，等Docker Daemon全部启动完毕之后才让Docker Server开始接受这些请求。

**/pkg/listenbuffer/buffer.go**

```go
// NewListenBuffer returns a listener listening on addr with the protocol.
func NewListenBuffer(proto, addr string, activate chan struct{}) (net.Listener, error) {
    wrapped, err := net.Listen(proto, addr)
    if err != nil {
        return nil, err
    }
 
    return &defaultListener{
        wrapped:  wrapped,
        activate: activate,
    }, nil
}
```

若协议类型为TCP，Job环境变量中Tls或TlsVerity有一个为true，则说明Docker Server需要支持HTTPS服务。需要建立一个tls.Config类型实例tlsConfig，在tlsConfig中加载证书、认证信息，通过tls包中的NewListener函数创建HTTPS协议请求的Listener实例。

**/api/server/server.go**

```go
l = tls.NewListener(l, tlsConfig)
```

## 3.3. 创建http.Server

**/api/server/server.go**

```go
httpSrv := http.Server{Addr: addr, Handler: r}
```

Docker Server需要创建一个Server对象来运行HTTP/HTTPS服务端，创建http.Server，addr为需要监听的地址，r为mux.Router。

## 3.4. 启动API服务

创建http.Server实例后，即启动API服务，监听请求，并对每一个请求生成一个新的协程来做专属服务。对于每个请求，协程会读取请求，查询路由表中的路由记录项，找到匹配的路由记录，最终调用路由记录中的处理方法，执行完毕返回响应信息。

**/api/server/server.go**

```go
return httpSrv.Serve(l)
```

参考：

- 《Docker源码分析》
