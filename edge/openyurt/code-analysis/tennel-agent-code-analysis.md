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
        Address:                 ata.tunnelServerAddr,  // 指定反向连接的目标地址
        AgentID:                 ata.nodeName,
        AgentIdentifiers:        ata.agentIdentifiers,
        SyncInterval:            5 * time.Second,
        ProbeInterval:           5 * time.Second,
        DialOptions:             []grpc.DialOption{dialOption},
        ServiceAccountTokenPath: "",
    }
		// 调用apiserver-network-proxy的包来创建双向的grpc连接。
    cs := cc.NewAgentClientSet(stopChan)
    cs.Serve()
    klog.Infof("start serving grpc request redirected from %s: %s",
        projectinfo.GetServerName(), ata.tunnelServerAddr)
}
```

以下是apiserver-network-proxy的源码分析。

# 6. apiserver-network-proxy.Client分析

具体代码参考：

- https://github.com/kubernetes-sigs/apiserver-network-proxy/blob/master/pkg/agent/clientset.go

通过`NewAgentClientSet`创建一个client结构体。

```go
func (cc *ClientSetConfig) NewAgentClientSet(stopCh <-chan struct{}) *ClientSet {
	return &ClientSet{
		clients:                 make(map[string]*Client),
		agentID:                 cc.AgentID,
		agentIdentifiers:        cc.AgentIdentifiers,
		address:                 cc.Address,
		syncInterval:            cc.SyncInterval,
		probeInterval:           cc.ProbeInterval,
		dialOptions:             cc.DialOptions,
		serviceAccountTokenPath: cc.ServiceAccountTokenPath,
		stopCh:                  stopCh,
	}
}
```

## 6.1. client.Serve

client.Serve运行一个sync的goroutine的常驻进程，再调用syncOnce函数。

```go
// 运行一个sync的goroutine
func (cs *ClientSet) Serve() {
	go cs.sync()
}

// sync makes sure that #clients >= #proxy servers
func (cs *ClientSet) sync() {
	defer cs.shutdown()
	backoff := cs.resetBackoff()
	var duration time.Duration
	for {
		if err := cs.syncOnce(); err != nil {
			klog.ErrorS(err, "cannot sync once")
			duration = backoff.Step()
		} else {
			backoff = cs.resetBackoff()
			duration = wait.Jitter(backoff.Duration, backoff.Jitter)
		}
		time.Sleep(duration)
		select {
		case <-cs.stopCh:
			return
		default:
		}
	}
}
```

`syncOnce`运行了真正执行grpc通信的client。

```go
func (cs *ClientSet) syncOnce() error {
	if cs.serverCount != 0 && cs.ClientsCount() >= cs.serverCount {
		return nil
	}
  
  // 创建封装的grpc client
	c, serverCount, err := cs.newAgentClient()
	if err != nil {
		return err
	}
	if cs.serverCount != 0 && cs.serverCount != serverCount {
		klog.V(2).InfoS("Server count change suggestion by server",
			"current", cs.serverCount, "serverID", c.serverID, "actual", serverCount)

	}
	cs.serverCount = serverCount
	if err := cs.AddClient(c.serverID, c); err != nil {
		klog.ErrorS(err, "closing connection failure when adding a client")
		c.Close()
		return nil
	}
	klog.V(2).InfoS("sync added client connecting to proxy server", "serverID", c.serverID)
  
  // 运行封装后的grpc 连接
	go c.Serve()
	return nil
}
```

# 7. Grpc client

代码参考：

- https://github.com/kubernetes-sigs/apiserver-network-proxy/blob/master/pkg/agent/client.go

## 7.1. newAgentClient

`newAgentClient`初始化一个grpc client，并启动连接。

```go
func newAgentClient(address, agentID, agentIdentifiers string, cs *ClientSet, opts ...grpc.DialOption) (*Client, int, error) {
	a := &Client{
		cs:                      cs,
		address:                 address,
		agentID:                 agentID,
		agentIdentifiers:        agentIdentifiers,
		opts:                    opts,
		probeInterval:           cs.probeInterval,
		stopCh:                  make(chan struct{}),
		serviceAccountTokenPath: cs.serviceAccountTokenPath,
		connManager:             newConnectionManager(),
	}
  
  // 启动client的连接
	serverCount, err := a.Connect()
	if err != nil {
		return nil, 0, err
	}
	return a, serverCount, nil
}
```

## 7.2. connect

Connect使grpc连接代理服务器。它返回服务器ID

```go
// Connect makes the grpc dial to the proxy server. It returns the serverID
// it connects to.
func (a *Client) Connect() (int, error) {
  // 运行grpc dial连接
	conn, err := grpc.Dial(a.address, a.opts...)
	if err != nil {
		return 0, err
	}
	// 已删除非必要的代码
  // 创建stream
	stream, err := agent.NewAgentServiceClient(conn).Connect(ctx)
	if err != nil {
		conn.Close() /* #nosec G104 */
		return 0, err
	}
	serverID, err := serverID(stream)
	if err != nil {
		conn.Close() /* #nosec G104 */
		return 0, err
	}
	serverCount, err := serverCount(stream)
	if err != nil {
		conn.Close() /* #nosec G104 */
		return 0, err
	}
	a.conn = conn
	a.stream = stream
	a.serverID = serverID
	klog.V(2).InfoS("Connect to", "server", serverID)
	return serverCount, nil
}
```

## 7.3. Serve()

`Serve`主要启动grpc双向传输通道的goroutine, 主要包括 send（发）和recv（收）2个操作。

```go
func (a *Client) Serve() {
	// 已经删除次要代码
	for {
		// 收包
		pkt, err := a.Recv()
		klog.V(5).InfoS("[tracing] recv packet", "type", pkt.Type)
		// 根据不同包类型进行不同的处理
		switch pkt.Type {
		case client.PacketType_DIAL_REQ:
			resp := &client.Packet{
				Type:    client.PacketType_DIAL_RSP,
				Payload: &client.Packet_DialResponse{DialResponse: &client.DialResponse{}},
			}
      
			if err := a.Send(resp); err != nil {
			}

      // 运行proxy
			go a.remoteToProxy(connID, ctx)
			go a.proxyToRemote(connID, ctx)

    // 接收到数据
		case client.PacketType_DATA:
			data := pkt.GetData()
			ctx, ok := a.connManager.Get(data.ConnectID)
			if ok {
				ctx.dataCh <- data.Data
			}

		case client.PacketType_CLOSE_REQ:
      // 已删除
			}
	}
}
```

# 8. remoteToProxy和proxyToRemote

remoteToProxy

```go
func (a *Client) remoteToProxy(connID int64, ctx *connContext) {
	defer ctx.cleanup()

	var buf [1 << 12]byte
	resp := &client.Packet{
		Type: client.PacketType_DATA,
	}

	for {
		n, err := ctx.conn.Read(buf[:])
		klog.V(4).InfoS("received data from remote", "bytes", n, "connID", connID)
			// 删除次要代码
			resp.Payload = &client.Packet_Data{Data: &client.Data{
				Data:      buf[:n],
				ConnectID: connID,
			}}
			if err := a.Send(resp); err != nil {
				klog.ErrorS(err, "stream send failure", "connID", connID)
			}
		}
	}
}
```

proxyToRemote

```go
func (a *Client) proxyToRemote(connID int64, ctx *connContext) {
	defer ctx.cleanup()

	for d := range ctx.dataCh {
		pos := 0
		for {
			n, err := ctx.conn.Write(d[pos:])
			if err == nil {
				klog.V(4).InfoS("write to remote", "connID", connID, "lastData", n)
				break
			} else if n > 0 {
				klog.ErrorS(err, "write to remote with failure", "connID", connID, "lastData", n)
				pos += n
			} else {
				if !strings.Contains(err.Error(), "use of closed network connection") {
					klog.ErrorS(err, "conn write failure", "connID", connID)
				}
				return
			}
		}
	}
}
```

# 9. Recv() 和Send()

```go
func (a *Client) Send(pkt *client.Packet) error {
	a.sendLock.Lock()
	defer a.sendLock.Unlock()

	err := a.stream.Send(pkt)
	if err != nil && err != io.EOF {
		metrics.Metrics.ObserveFailure(metrics.DirectionToServer)
		a.cs.RemoveClient(a.serverID)
	}
	return err
}

func (a *Client) Recv() (*client.Packet, error) {
	a.recvLock.Lock()
	defer a.recvLock.Unlock()

	pkt, err := a.stream.Recv()
	if err != nil && err != io.EOF {
		metrics.Metrics.ObserveFailure(metrics.DirectionFromServer)
		a.cs.RemoveClient(a.serverID)
	}
	return pkt, err
}
```

# 10. 总结

Tunnel-agent本质是封装了`apiserver-network-proxy`库，最终运行一个grpc的双向收发数据包的通道，所以**本质上tunnel是通过grpc反向建立连接，并实现双向通信的能力。**因此该反向隧道能力的也可以通过其他双向通信的协议来实现，例如websocket（类似kubeedge通过websocket来实现反向隧道）。



参考：

- [/pkg/yurttunnel/agent/anpagent.go](https://github.com/openyurtio/openyurt/blob/180282663457080119a1bc6076cce20c922b5c50/pkg/yurttunnel/agent/anpagent.go)
- https://github.com/kubernetes-sigs/apiserver-network-proxy/blob/master/pkg/agent/client.go
- https://github.com/kubernetes-sigs/apiserver-network-proxy/blob/master/pkg/agent/clientset.go
