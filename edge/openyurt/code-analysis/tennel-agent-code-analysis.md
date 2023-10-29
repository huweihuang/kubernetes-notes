---
title: "OpenYurt之Tunnel-Agent源码分析"
linkTitle: "Tunnel-Agent源码分析"
weight: 3
catalog: true
date: 2023-05-10 10:50:57
subtitle:
header-img: 
tags:
- OpenYurt
catagories:
- OpenYurt
---

# 1. Tunnel-Agent简介

tunnel-agent是通过daemonset部署在每个worker节点，通过grpc协议与云端的tunnel-server建立连接。以下分析tunnel-agent的源码逻辑。

常用的启动参数：

```bash
      - args:
        - --node-name=$(NODE_NAME)
        - --node-ip=$(POD_IP)
        - --tunnelserver-addr=tunnel-server-address[ip:port]
        - --v=2
        command:
        - yurt-tunnel-agent
```

# 2. NewYurttunnelAgentCommand

NewYurttunnelAgentCommand还是常用命令代码三板斧，此处不做展开，直接分析Run函数。

```go
// NewYurttunnelAgentCommand creates a new yurttunnel-agent command
func NewYurttunnelAgentCommand(stopCh <-chan struct{}) *cobra.Command {
    agentOptions := options.NewAgentOptions()

    // 已经删除非重要的代码
    cmd := &cobra.Command{
        RunE: func(c *cobra.Command, args []string) error {
            cfg, err := agentOptions.Config()
            if err := Run(cfg.Complete(), stopCh); err != nil {
                return err
            }
        },
    }

    agentOptions.AddFlags(cmd.Flags())
    return cmd
}
```

# 3. Run

Run函数即启动一个agent服务，主要包含以下几个步骤：

1. 先获取配置项tunnelserver-addr中的地址，如果地址不存在，则获取x-tunnel-server-svc的service 地址。（说明：一般情况下，tunnel-server跟agent不在同一个网络域，因此网络会不通，所以一般需要配置独立且可连通的地址，可以通过Nginx转发）

2. agent通过host的网络模式运行在宿主机上，启动证书manager。并等待证书生成。

3. 生成连接tunnel-server的证书。

4. 启动 yurttunnel-agent。

5. 启动meta server。

```go
// Run starts the yurttunel-agent
func Run(cfg *config.CompletedConfig, stopCh <-chan struct{}) error {
    // 1. get the address of the yurttunnel-server
    tunnelServerAddr = cfg.TunnelServerAddr
    if tunnelServerAddr == "" {
        if tunnelServerAddr, err = serveraddr.GetTunnelServerAddr(cfg.Client); err != nil {
            return err
        }
    }

    // 2. create a certificate manager
    // As yurttunnel-agent will run on the edge node with Host network mode,
    // we can use the status.podIP as the node IP
    nodeIP := os.Getenv(constants.YurttunnelAgentPodIPEnv)

    agentCertMgr, err = certfactory.NewCertManagerFactory(cfg.Client).New(&certfactory.CertManagerConfig{
        ComponentName: projectinfo.GetAgentName(),
        CertDir:       cfg.CertDir,
        SignerName:    certificatesv1.KubeAPIServerClientSignerName,
        CommonName:    constants.YurtTunnelAgentCSRCN,
        Organizations: []string{constants.YurtTunnelCSROrg},
        DNSNames:      []string{os.Getenv("NODE_NAME")},
        IPs:           []net.IP{net.ParseIP(nodeIP)},
    })

    agentCertMgr.Start()

    // 2.1. waiting for the certificate is generated
    _ = wait.PollUntil(5*time.Second, func() (bool, error) {
        if agentCertMgr.Current() != nil {
            return true, nil
        }
        klog.Infof("certificate %s not signed, waiting...",
            projectinfo.GetAgentName())
        return false, nil
    }, stopCh)

    // 3. generate a TLS configuration for securing the connection to server
    tlsCfg, err := certmanager.GenTLSConfigUseCertMgrAndCA(agentCertMgr,
        tunnelServerAddr, constants.YurttunnelCAFile)


    // 4. start the yurttunnel-agent
    ta := agent.NewTunnelAgent(tlsCfg, tunnelServerAddr, cfg.NodeName, cfg.AgentIdentifiers)
    ta.Run(stopCh)

    // 5. start meta server
    util.RunMetaServer(cfg.AgentMetaAddr)

    <-stopCh
    return nil
}
```

# 4. TunnelAgent

TunnelAgent与tunnel-server建立tunnel，接收server的请求，并转发给kubelet。

```go
// TunnelAgent sets up tunnel to TunnelServer, receive requests
// from tunnel, and forwards requests to kubelet
type TunnelAgent interface {
    Run(<-chan struct{})
}

// NewTunnelAgent generates a new TunnelAgent
func NewTunnelAgent(tlsCfg *tls.Config,
    tunnelServerAddr, nodeName, agentIdentifiers string) TunnelAgent {
    ata := anpTunnelAgent{
        tlsCfg:           tlsCfg,
        tunnelServerAddr: tunnelServerAddr,
        nodeName:         nodeName,
        agentIdentifiers: agentIdentifiers,
    }

    return &ata
}
```

# 5. anpTunnelAgent.Run

anpTunnelAgent使用apiserver-network-proxy包来实现tunnel逻辑。项目具体参考：[https://github.com/kubernetes-sigs/apiserver-network-proxy](https://github.com/kubernetes-sigs/apiserver-network-proxy))

> 代码：[/pkg/yurttunnel/agent/anpagent.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurttunnel/agent/anpagent.go)

```go
// RunAgent runs the yurttunnel-agent which will try to connect yurttunnel-server
func (ata *anpTunnelAgent) Run(stopChan <-chan struct{}) {
    dialOption := grpc.WithTransportCredentials(credentials.NewTLS(ata.tlsCfg))
    cc := &anpagent.ClientSetConfig{
        Address:                 ata.tunnelServerAddr,
        AgentID:                 ata.nodeName,
        AgentIdentifiers:        ata.agentIdentifiers,
        SyncInterval:            5 * time.Second,
        ProbeInterval:           5 * time.Second,
        DialOptions:             []grpc.DialOption{dialOption},
        ServiceAccountTokenPath: "",
    }

    cs := cc.NewAgentClientSet(stopChan)
    cs.Serve()
    klog.Infof("start serving grpc request redirected from %s: %s",
        projectinfo.GetServerName(), ata.tunnelServerAddr)
}
```

以下是apiserver-network-proxy的源码分析，待补充。

参考：

- [/pkg/yurttunnel/agent/anpagent.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurttunnel/agent/anpagent.go)
