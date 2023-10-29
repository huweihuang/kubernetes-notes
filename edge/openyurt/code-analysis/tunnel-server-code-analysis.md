---
title: "OpenYurt之TunnelServer源码分析"
linkTitle: "TunnelServer源码分析（1）"
weight: 2
catalog: true
date: 2023-05-18 20:50:57
subtitle:
header-img: 
tags:
- OpenYurt
catagories:
- OpenYurt
---

> 本文以commit id：`180282663457080119a1bc6076cce20c922b5c50`， 对应版本tag: `v1.2.1` 的源码分析tunnel-server的实现逻辑。

# 1. Tunnel-server简介

云与边一般位于不同网络平面，同时边缘节点普遍位于防火墙内部，采用云(中心)边协同架构，将导致原生 K8s 系统的运维监控能力面临如下挑战:

- K8s 原生运维能力缺失(如 kubectl logs/exec 等无法执行)
- 社区主流监控运维组件无法工作(如 Prometheus/metrics-server )

在 OpenYurt 中，引入了专门的组件 YurtTunnel 负责解决云边通信问题。反向通道是解决跨网络通信的一种常见方式，而 YurtTunnel 的本质也是一个反向通道。 它是一个典型的C/S结构的组件，由部署于云端的 YurtTunnelServer 和部署于边缘节点上的 YurtTunnelAgent组成。

本文主要分析tunnel-server的代理逻辑。

以下是基本架构图：

<img title="" src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1682566581/article/openyurt/tunnel_components.jpg" alt="" width="628">

pkg中的目录结构：

```bash
yurttunnel
├── agent  # tunnel agent代码
├── constants # 常量值
├── handlerwrapper
├── informers
├── kubernetes  # k8s clientset工具包
├── server  # 核心代码： tunnel server逻辑
├── trafficforward  # iptables和dns操作
└── util
```

# 2. NewYurttunnelServerCommand

main函数入口：

```go
func main() {
    cmd := app.NewYurttunnelServerCommand(stop)
    cmd.Flags().AddGoFlagSet(flag.CommandLine)
    if err := cmd.Execute(); err != nil {
        klog.Fatalf("%s failed: %s", projectinfo.GetServerName(), err)
    }
}
```

以下是NewYurttunnelServerCommand构造函数，常见的三件套，不做展开：

- 读取参数：serverOptions.AddFlags(cmd.Flags())

- 生成配置：cfg.Complete()

- 执行Run函数：核心逻辑

```go
func NewYurttunnelServerCommand(stopCh <-chan struct{}) *cobra.Command {
    serverOptions := options.NewServerOptions()

    cmd := &cobra.Command{
        Use:   "Launch " + projectinfo.GetServerName(),
        Short: projectinfo.GetServerName() + " sends requests to " + projectinfo.GetAgentName(),
        RunE: func(c *cobra.Command, args []string) error {
            ...
            cfg, err := serverOptions.Config()
            if err != nil {
                return err
            }
            if err := Run(cfg.Complete(), stopCh); err != nil {
                return err
            }
            return nil
        },
        Args: cobra.NoArgs,
    }
    serverOptions.AddFlags(cmd.Flags())
    return cmd
}
```

# 3. Run(cfg.Complete(), stopCh)

Run函数最终是运行一个tunnelserver的常驻进程。在之前会做一些controller或manager的准备工作。

其中包括：

- DNS controller

- IP table manager

- certificate manager

- RegisterInformersForTunnelServer

首先是构建并运行上述的manager或controller， 源码中的注释也大概描述了主要流程：

1. 注册tunnel所需的SharedInformerFactory

2. 运行dns controller

3. 运行ip table manager

4. 给tunnel server创建certificate manager

5. 给tunnel agent 创建certificate manager

6. 创建handler wrappers

7. 生成TLS 证书

8. 运行tunnel server

以下是部分代码，已删除无关紧要的代码：

```go
// run starts the yurttunel-server
func Run(cfg *config.CompletedConfig, stopCh <-chan struct{}) error {
    var wg sync.WaitGroup
    // register informers that tunnel server need
    informers.RegisterInformersForTunnelServer(cfg.SharedInformerFactory)

    // 0. start the DNS controller
    if cfg.EnableDNSController {
        dnsController, err := dns.NewCoreDNSRecordController(...)
        go dnsController.Run(stopCh)
    }
    // 1. start the IP table manager
    if cfg.EnableIptables {
        iptablesMgr, err := iptables.NewIptablesManagerWithIPFamily(...)
        wg.Add(1)
        go iptablesMgr.Run(stopCh, &wg)
    }

    // 2. create a certificate manager for the tunnel server
    certManagerFactory := certfactory.NewCertManagerFactory(cfg.Client)
    ips, dnsNames, err := getTunnelServerIPsAndDNSNamesBeforeInformerSynced(cfg.Client, stopCh)

    serverCertMgr, err := certManagerFactory.New(...)
    serverCertMgr.Start()

    // 3. create a certificate manager for the tunnel proxy client
    tunnelProxyCertMgr, err := certManagerFactory.New(...)
    tunnelProxyCertMgr.Start()

    // 4. create handler wrappers
    mInitializer := initializer.NewMiddlewareInitializer(cfg.SharedInformerFactory)
    wrappers, err := wraphandler.InitHandlerWrappers(mInitializer, cfg.IsIPv6())


    // after all of informers are configured completed, start the shared index informer
    cfg.SharedInformerFactory.Start(stopCh)

    // 5. waiting for the certificate is generated
    _ = wait.PollUntil(5*time.Second, func() (bool, error) {
        // keep polling until the certificate is signed
        if serverCertMgr.Current() != nil && tunnelProxyCertMgr.Current() != nil {
            return true, nil
        }
        klog.Infof("waiting for the master to sign the %s certificate", projectinfo.GetServerName())
        return false, nil
    }, stopCh)

    // 6. generate the TLS configuration based on the latest certificate
    tlsCfg, err := certmanager.GenTLSConfigUseCurrentCertAndCertPool(serverCertMgr.Current, cfg.RootCert, "server")


    proxyClientTlsCfg, err := certmanager.GenTLSConfigUseCurrentCertAndCertPool(tunnelProxyCertMgr.Current, cfg.RootCert, "client")


    // 7. start the server
    ts := server.NewTunnelServer(
        cfg.EgressSelectorEnabled,
        cfg.InterceptorServerUDSFile,
        cfg.ListenAddrForMaster,
        cfg.ListenInsecureAddrForMaster,
        cfg.ListenAddrForAgent,
        cfg.ServerCount,
        tlsCfg,
        proxyClientTlsCfg,
        wrappers,
        cfg.ProxyStrategy)
    if err := ts.Run(); err != nil {
        return err
    }

    // 8. start meta server
    util.RunMetaServer(cfg.ListenMetaAddr)

    <-stopCh
    wg.Wait()
    return nil
}
```

# 3. TunnelServer

anpTunnelServer实现了TunnelServer的接口，以下分析TunnelServer.Run的部分。

run部分主要运行了三个server

- proxyServer： 主要是重定向apiserver的请求到tunnel server

- MasterServer：

- AgentServer：主要运行一个grpc server与tunnel agent连接，即云边反向隧道

> 代码参考：[/pkg/yurttunnel/server/anpserver.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurttunnel/server/anpserver.go)

```go
// Run runs the yurttunnel-server
func (ats *anpTunnelServer) Run() error {
    proxyServer := anpserver.NewProxyServer(uuid.New().String(),
        []anpserver.ProxyStrategy{anpserver.ProxyStrategy(ats.proxyStrategy)},
        ats.serverCount,
        &anpserver.AgentTokenAuthenticationOptions{})
    // 1. start the proxier
    proxierErr := runProxier(
        &anpserver.Tunnel{Server: proxyServer},
        ats.egressSelectorEnabled,
        ats.interceptorServerUDSFile,
        ats.tlsCfg)

    wrappedHandler, err := wh.WrapHandler(
        NewRequestInterceptor(ats.interceptorServerUDSFile, ats.proxyClientTlsCfg),
        ats.wrappers,
    )

    // 2. start the master server
    masterServerErr := runMasterServer(
        wrappedHandler,
        ats.egressSelectorEnabled,
        ats.serverMasterAddr,
        ats.serverMasterInsecureAddr,
        ats.tlsCfg)

    // 3. start the agent server
    agentServerErr := runAgentServer(ats.tlsCfg, ats.serverAgentAddr, proxyServer)

    return nil
}
```

# 4. runAgentServer

runAgentServer主要运行一个grpc server与edge端的agent形成grpc连接。

```go
// runAgentServer runs a grpc server that handles connections from the yurttunel-agent
// NOTE agent server is responsible for managing grpc connection yurttunel-server
// and yurttunnel-agent, and the proxy server is responsible for redirecting requests
// to corresponding yurttunel-agent
func runAgentServer(tlsCfg *tls.Config,
    agentServerAddr string,
    proxyServer *anpserver.ProxyServer) error {
    serverOption := grpc.Creds(credentials.NewTLS(tlsCfg))

    ka := keepalive.ServerParameters{
        // Ping the client if it is idle for `Time` seconds to ensure the
        // connection is still active
        Time: constants.YurttunnelANPGrpcKeepAliveTimeSec * time.Second,
        // Wait `Timeout` second for the ping ack before assuming the
        // connection is dead
        Timeout: constants.YurttunnelANPGrpcKeepAliveTimeoutSec * time.Second,
    }

    grpcServer := grpc.NewServer(serverOption,
        grpc.KeepaliveParams(ka))

    anpagent.RegisterAgentServiceServer(grpcServer, proxyServer)
    listener, err := net.Listen("tcp", agentServerAddr)
    klog.Info("start handling connection from agents")
    if err != nil {
        return fmt.Errorf("fail to listen to agent on %s: %w", agentServerAddr, err)
    }
    go grpcServer.Serve(listener)
    return nil
}
```

# 5. Interceptor

Interceptor（请求拦截器）拦截kube-apiserver的请求转发给tunnel，通过tunnel请求kubelet。

流程图：

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1683615159/article/openyurt/tunnel_sequence_diag.webp" title="" alt="" width="719">

> 代码地址：[/pkg/yurttunnel/server/interceptor.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurttunnel/server/interceptor.go)

```go
// NewRequestInterceptor creates a interceptor object that intercept request from kube-apiserver
func NewRequestInterceptor(udsSockFile string, cfg *tls.Config) *RequestInterceptor {
    if len(udsSockFile) == 0 || cfg == nil {
        return nil
    }

    cfg.InsecureSkipVerify = true
    contextDialer := func(addr string, header http.Header, isTLS bool) (net.Conn, error) {
        klog.V(4).Infof("Sending request to %q.", addr)
        proxyConn, err := net.Dial("unix", udsSockFile)
        if err != nil {
            return nil, fmt.Errorf("dialing proxy %q failed: %w", udsSockFile, err)
        }

        var connectHeaders string
        for _, h := range supportedHeaders {
            if v := header.Get(h); len(v) != 0 {
                connectHeaders = fmt.Sprintf("%s\r\n%s: %s", connectHeaders, h, v)
            }
        }

        fmt.Fprintf(proxyConn, "CONNECT %s HTTP/1.1\r\nHost: localhost%s\r\n\r\n", addr, connectHeaders)
        br := newBufioReader(proxyConn)
        defer putBufioReader(br)
        res, err := http.ReadResponse(br, nil)
        if err != nil {
            proxyConn.Close()
            return nil, fmt.Errorf("reading HTTP response from CONNECT to %s via proxy %s failed: %w", addr, udsSockFile, err)
        }
        if res.StatusCode != 200 {
            proxyConn.Close()
            return nil, fmt.Errorf("proxy error from %s while dialing %s, code %d: %v", udsSockFile, addr, res.StatusCode, res.Status)
        }

        // if the request scheme is https, setup a tls connection over the
        // proxy tunnel (i.e. interceptor <--tls--> kubelet)
        if isTLS {
            tlsTunnelConn := tls.Client(proxyConn, cfg)
            if err := tlsTunnelConn.Handshake(); err != nil {
                proxyConn.Close()
                return nil, fmt.Errorf("fail to setup TLS handshake through the Tunnel: %w", err)
            }
            klog.V(4).Infof("successfully setup TLS connection to %q with headers: %s", addr, connectHeaders)
            return tlsTunnelConn, nil
        }
        klog.V(2).Infof("successfully setup connection to %q with headers: %q", addr, connectHeaders)
        return proxyConn, nil
    }

    return &RequestInterceptor{
        contextDialer: contextDialer,
    }
}
```

参考：

- https://openyurt.io/zh/docs/core-concepts/yurttunnel
