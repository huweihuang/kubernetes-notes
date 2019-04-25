# kube-apiserver源码分析（一）之 NewAPIServerCommand

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析`kube-apiserver`中`cmd`部分的代码，即`NewAPIServerCommand`相关的代码。更多具体的逻辑待后续文章分析。

`kube-apiserver`的`cmd`部分目录代码结构如下：

```bash
kube-apiserver
├── apiserver.go   # kube-apiserver的main入口
└── app
    ├── aggregator.go
    ├── apiextensions.go
    ├── options  # 初始化kube-apiserver使用到的option
    │   ├── options.go     # 包括：NewServerRunOptions、Flags等
    │   ├── options_test.go
    │   └── validation.go
    ├── server.go   # 包括：NewAPIServerCommand、Run、CreateServerChain、Complete等
```

# 1. Main

> 此部分代码位于cmd/kube-apiserver/apiserver.go

```go
func main() {
	rand.Seed(time.Now().UTC().UnixNano())

	command := app.NewAPIServerCommand(server.SetupSignalHandler())

	// TODO: once we switch everything over to Cobra commands, we can go back to calling
	// utilflag.InitFlags() (by removing its pflag.Parse() call). For now, we have to set the
	// normalize func and add the go flag set by hand.
	pflag.CommandLine.SetNormalizeFunc(utilflag.WordSepNormalizeFunc)
	pflag.CommandLine.AddGoFlagSet(goflag.CommandLine)
	// utilflag.InitFlags()
	logs.InitLogs()
	defer logs.FlushLogs()

	if err := command.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
```

核心代码：

```go
// 初始化APIServerCommand
command := app.NewAPIServerCommand(server.SetupSignalHandler())
// 执行Execute
err := command.Execute()
```

# 2. NewAPIServerCommand

> 此部分的代码位于/cmd/kube-apiserver/app/server.go

`NewAPIServerCommand`即[Cobra](https://github.com/spf13/cobra)命令行框架的构造函数，主要包括三部分：

- 构造option
- 添加Flags
- 执行Run函数

完整代码如下：

> 此部分代码位于cmd/kube-apiserver/app/server.go

```go
// NewAPIServerCommand creates a *cobra.Command object with default parameters
func NewAPIServerCommand(stopCh <-chan struct{}) *cobra.Command {
	s := options.NewServerRunOptions()
	cmd := &cobra.Command{
		Use: "kube-apiserver",
		Long: `The Kubernetes API server validates and configures data
for the api objects which include pods, services, replicationcontrollers, and
others. The API Server services REST operations and provides the frontend to the
cluster's shared state through which all other components interact.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			verflag.PrintAndExitIfRequested()
			utilflag.PrintFlags(cmd.Flags())

			// set default options
			completedOptions, err := Complete(s)
			if err != nil {
				return err
			}

			// validate options
			if errs := completedOptions.Validate(); len(errs) != 0 {
				return utilerrors.NewAggregate(errs)
			}

			return Run(completedOptions, stopCh)
		},
	}

	fs := cmd.Flags()
	namedFlagSets := s.Flags()
	for _, f := range namedFlagSets.FlagSets {
		fs.AddFlagSet(f)
	}

	usageFmt := "Usage:\n  %s\n"
	cols, _, _ := apiserverflag.TerminalSize(cmd.OutOrStdout())
	cmd.SetUsageFunc(func(cmd *cobra.Command) error {
		fmt.Fprintf(cmd.OutOrStderr(), usageFmt, cmd.UseLine())
		apiserverflag.PrintSections(cmd.OutOrStderr(), namedFlagSets, cols)
		return nil
	})
	cmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
		fmt.Fprintf(cmd.OutOrStdout(), "%s\n\n"+usageFmt, cmd.Long, cmd.UseLine())
		apiserverflag.PrintSections(cmd.OutOrStdout(), namedFlagSets, cols)
	})

	return cmd
}
```

核心代码：

```go
// 构造option
s := options.NewServerRunOptions()
// 添加flags
fs := cmd.Flags()
namedFlagSets := s.Flags()
for _, f := range namedFlagSets.FlagSets {
	fs.AddFlagSet(f)
}
// set default options
completedOptions, err := Complete(s)
// Run
Run(completedOptions, stopCh)
```

# 3. NewServerRunOptions

`NewServerRunOptions`基于默认的参数构造`ServerRunOptions`结构体。`ServerRunOptions`是apiserver运行的配置信息。具体结构体定义如下。

## 3.1. ServerRunOptions

其中主要的配置如下：

- GenericServerRunOptions
- Etcd
- SecureServing
- KubeletConfig
- ...

```go
// ServerRunOptions runs a kubernetes api server.
type ServerRunOptions struct {
	GenericServerRunOptions *genericoptions.ServerRunOptions
	Etcd                    *genericoptions.EtcdOptions
	SecureServing           *genericoptions.SecureServingOptionsWithLoopback
	InsecureServing         *genericoptions.DeprecatedInsecureServingOptionsWithLoopback
	Audit                   *genericoptions.AuditOptions
	Features                *genericoptions.FeatureOptions
	Admission               *kubeoptions.AdmissionOptions
	Authentication          *kubeoptions.BuiltInAuthenticationOptions
	Authorization           *kubeoptions.BuiltInAuthorizationOptions
	CloudProvider           *kubeoptions.CloudProviderOptions
	StorageSerialization    *kubeoptions.StorageSerializationOptions
	APIEnablement           *genericoptions.APIEnablementOptions

	AllowPrivileged           bool
	EnableLogsHandler         bool
	EventTTL                  time.Duration
	KubeletConfig             kubeletclient.KubeletClientConfig
	KubernetesServiceNodePort int
	MaxConnectionBytesPerSec  int64
	ServiceClusterIPRange     net.IPNet // TODO: make this a list
	ServiceNodePortRange      utilnet.PortRange
	SSHKeyfile                string
	SSHUser                   string

	ProxyClientCertFile string
	ProxyClientKeyFile  string

	EnableAggregatorRouting bool

	MasterCount            int
	EndpointReconcilerType string

	ServiceAccountSigningKeyFile string
}
```

## 3.2. NewServerRunOptions

`NewServerRunOptions`初始化配置结构体。

```go
// NewServerRunOptions creates a new ServerRunOptions object with default parameters
func NewServerRunOptions() *ServerRunOptions {
	s := ServerRunOptions{
		GenericServerRunOptions: genericoptions.NewServerRunOptions(),
		Etcd:                 genericoptions.NewEtcdOptions(storagebackend.NewDefaultConfig(kubeoptions.DefaultEtcdPathPrefix, nil)),
		SecureServing:        kubeoptions.NewSecureServingOptions(),
		InsecureServing:      kubeoptions.NewInsecureServingOptions(),
		Audit:                genericoptions.NewAuditOptions(),
		Features:             genericoptions.NewFeatureOptions(),
		Admission:            kubeoptions.NewAdmissionOptions(),
		Authentication:       kubeoptions.NewBuiltInAuthenticationOptions().WithAll(),
		Authorization:        kubeoptions.NewBuiltInAuthorizationOptions(),
		CloudProvider:        kubeoptions.NewCloudProviderOptions(),
		StorageSerialization: kubeoptions.NewStorageSerializationOptions(),
		APIEnablement:        genericoptions.NewAPIEnablementOptions(),

		EnableLogsHandler:      true,
		EventTTL:               1 * time.Hour,
		MasterCount:            1,
		EndpointReconcilerType: string(reconcilers.LeaseEndpointReconcilerType),
		KubeletConfig: kubeletclient.KubeletClientConfig{
			Port:         ports.KubeletPort,
			ReadOnlyPort: ports.KubeletReadOnlyPort,
			PreferredAddressTypes: []string{
				// --override-hostname
				string(api.NodeHostName),

				// internal, preferring DNS if reported
				string(api.NodeInternalDNS),
				string(api.NodeInternalIP),

				// external, preferring DNS if reported
				string(api.NodeExternalDNS),
				string(api.NodeExternalIP),
			},
			EnableHttps: true,
			HTTPTimeout: time.Duration(5) * time.Second,
		},
		ServiceNodePortRange: kubeoptions.DefaultServiceNodePortRange,
	}
	s.ServiceClusterIPRange = kubeoptions.DefaultServiceIPCIDR

	// Overwrite the default for storage data format.
	s.Etcd.DefaultStorageMediaType = "application/vnd.kubernetes.protobuf"

	return &s
}
```

## 3.3. Complete

当kube-apiserver的flags被解析后，调用`Complete`完成默认配置。

> 此部分代码位于cmd/kube-apiserver/app/server.go

```go
// Should be called after kube-apiserver flags parsed.
func Complete(s *options.ServerRunOptions) (completedServerRunOptions, error) {
	var options completedServerRunOptions
	// set defaults
	if err := s.GenericServerRunOptions.DefaultAdvertiseAddress(s.SecureServing.SecureServingOptions); err != nil {
		return options, err
	}
	if err := kubeoptions.DefaultAdvertiseAddress(s.GenericServerRunOptions, s.InsecureServing.DeprecatedInsecureServingOptions); err != nil {
		return options, err
	}
	serviceIPRange, apiServerServiceIP, err := master.DefaultServiceIPRange(s.ServiceClusterIPRange)
	if err != nil {
		return options, fmt.Errorf("error determining service IP ranges: %v", err)
	}
	s.ServiceClusterIPRange = serviceIPRange
	if err := s.SecureServing.MaybeDefaultWithSelfSignedCerts(s.GenericServerRunOptions.AdvertiseAddress.String(), []string{"kubernetes.default.svc", "kubernetes.default", "kubernetes"}, []net.IP{apiServerServiceIP}); err != nil {
		return options, fmt.Errorf("error creating self-signed certificates: %v", err)
	}

	if len(s.GenericServerRunOptions.ExternalHost) == 0 {
		if len(s.GenericServerRunOptions.AdvertiseAddress) > 0 {
			s.GenericServerRunOptions.ExternalHost = s.GenericServerRunOptions.AdvertiseAddress.String()
		} else {
			if hostname, err := os.Hostname(); err == nil {
				s.GenericServerRunOptions.ExternalHost = hostname
			} else {
				return options, fmt.Errorf("error finding host name: %v", err)
			}
		}
		glog.Infof("external host was not specified, using %v", s.GenericServerRunOptions.ExternalHost)
	}

	s.Authentication.ApplyAuthorization(s.Authorization)

	// Use (ServiceAccountSigningKeyFile != "") as a proxy to the user enabling
	// TokenRequest functionality. This defaulting was convenient, but messed up
	// a lot of people when they rotated their serving cert with no idea it was
	// connected to their service account keys. We are taking this oppurtunity to
	// remove this problematic defaulting.
	if s.ServiceAccountSigningKeyFile == "" {
		// Default to the private server key for service account token signing
		if len(s.Authentication.ServiceAccounts.KeyFiles) == 0 && s.SecureServing.ServerCert.CertKey.KeyFile != "" {
			if kubeauthenticator.IsValidServiceAccountKeyFile(s.SecureServing.ServerCert.CertKey.KeyFile) {
				s.Authentication.ServiceAccounts.KeyFiles = []string{s.SecureServing.ServerCert.CertKey.KeyFile}
			} else {
				glog.Warning("No TLS key provided, service account token authentication disabled")
			}
		}
	}

	if s.Etcd.StorageConfig.DeserializationCacheSize == 0 {
		// When size of cache is not explicitly set, estimate its size based on
		// target memory usage.
		glog.V(2).Infof("Initializing deserialization cache size based on %dMB limit", s.GenericServerRunOptions.TargetRAMMB)

		// This is the heuristics that from memory capacity is trying to infer
		// the maximum number of nodes in the cluster and set cache sizes based
		// on that value.
		// From our documentation, we officially recommend 120GB machines for
		// 2000 nodes, and we scale from that point. Thus we assume ~60MB of
		// capacity per node.
		// TODO: We may consider deciding that some percentage of memory will
		// be used for the deserialization cache and divide it by the max object
		// size to compute its size. We may even go further and measure
		// collective sizes of the objects in the cache.
		clusterSize := s.GenericServerRunOptions.TargetRAMMB / 60
		s.Etcd.StorageConfig.DeserializationCacheSize = 25 * clusterSize
		if s.Etcd.StorageConfig.DeserializationCacheSize < 1000 {
			s.Etcd.StorageConfig.DeserializationCacheSize = 1000
		}
	}
	if s.Etcd.EnableWatchCache {
		glog.V(2).Infof("Initializing cache sizes based on %dMB limit", s.GenericServerRunOptions.TargetRAMMB)
		sizes := cachesize.NewHeuristicWatchCacheSizes(s.GenericServerRunOptions.TargetRAMMB)
		if userSpecified, err := serveroptions.ParseWatchCacheSizes(s.Etcd.WatchCacheSizes); err == nil {
			for resource, size := range userSpecified {
				sizes[resource] = size
			}
		}
		s.Etcd.WatchCacheSizes, err = serveroptions.WriteWatchCacheSizes(sizes)
		if err != nil {
			return options, err
		}
	}

	// TODO: remove when we stop supporting the legacy group version.
	if s.APIEnablement.RuntimeConfig != nil {
		for key, value := range s.APIEnablement.RuntimeConfig {
			if key == "v1" || strings.HasPrefix(key, "v1/") ||
				key == "api/v1" || strings.HasPrefix(key, "api/v1/") {
				delete(s.APIEnablement.RuntimeConfig, key)
				s.APIEnablement.RuntimeConfig["/v1"] = value
			}
			if key == "api/legacy" {
				delete(s.APIEnablement.RuntimeConfig, key)
			}
		}
	}
	options.ServerRunOptions = s
	return options, nil
}
```

# 3. AddFlagSet

`AddFlagSet`主要的作用是通过外部传入的flag的具体值，解析的时候传递给option的结构体，最终给apiserver使用。

其中`NewAPIServerCommand`关于`AddFlagSet`的相关代码如下：

```go
fs := cmd.Flags()
namedFlagSets := s.Flags()
for _, f := range namedFlagSets.FlagSets {
	fs.AddFlagSet(f)
}
```

## 3.1. Flags

`Flags`完整代码如下：

> 此部分代码位于cmd/kube-apiserver/app/options/options.go

```go
// Flags returns flags for a specific APIServer by section name
func (s *ServerRunOptions) Flags() (fss apiserverflag.NamedFlagSets) {
	// Add the generic flags.
	s.GenericServerRunOptions.AddUniversalFlags(fss.FlagSet("generic"))
	s.Etcd.AddFlags(fss.FlagSet("etcd"))
	s.SecureServing.AddFlags(fss.FlagSet("secure serving"))
	s.InsecureServing.AddFlags(fss.FlagSet("insecure serving"))
	s.InsecureServing.AddUnqualifiedFlags(fss.FlagSet("insecure serving")) // TODO: remove it until kops stops using `--address`
	s.Audit.AddFlags(fss.FlagSet("auditing"))
	s.Features.AddFlags(fss.FlagSet("features"))
	s.Authentication.AddFlags(fss.FlagSet("authentication"))
	s.Authorization.AddFlags(fss.FlagSet("authorization"))
	s.CloudProvider.AddFlags(fss.FlagSet("cloud provider"))
	s.StorageSerialization.AddFlags(fss.FlagSet("storage"))
	s.APIEnablement.AddFlags(fss.FlagSet("api enablement"))
	s.Admission.AddFlags(fss.FlagSet("admission"))

	// Note: the weird ""+ in below lines seems to be the only way to get gofmt to
	// arrange these text blocks sensibly. Grrr.
	fs := fss.FlagSet("misc")
	fs.DurationVar(&s.EventTTL, "event-ttl", s.EventTTL,
		"Amount of time to retain events.")

	fs.BoolVar(&s.AllowPrivileged, "allow-privileged", s.AllowPrivileged,
		"If true, allow privileged containers. [default=false]")

	fs.BoolVar(&s.EnableLogsHandler, "enable-logs-handler", s.EnableLogsHandler,
		"If true, install a /logs handler for the apiserver logs.")

	// Deprecated in release 1.9
	fs.StringVar(&s.SSHUser, "ssh-user", s.SSHUser,
		"If non-empty, use secure SSH proxy to the nodes, using this user name")
	fs.MarkDeprecated("ssh-user", "This flag will be removed in a future version.")

	// Deprecated in release 1.9
	fs.StringVar(&s.SSHKeyfile, "ssh-keyfile", s.SSHKeyfile,
		"If non-empty, use secure SSH proxy to the nodes, using this user keyfile")
	fs.MarkDeprecated("ssh-keyfile", "This flag will be removed in a future version.")

	fs.Int64Var(&s.MaxConnectionBytesPerSec, "max-connection-bytes-per-sec", s.MaxConnectionBytesPerSec, ""+
		"If non-zero, throttle each user connection to this number of bytes/sec. "+
		"Currently only applies to long-running requests.")

	fs.IntVar(&s.MasterCount, "apiserver-count", s.MasterCount,
		"The number of apiservers running in the cluster, must be a positive number. (In use when --endpoint-reconciler-type=master-count is enabled.)")

	fs.StringVar(&s.EndpointReconcilerType, "endpoint-reconciler-type", string(s.EndpointReconcilerType),
		"Use an endpoint reconciler ("+strings.Join(reconcilers.AllTypes.Names(), ", ")+")")

	// See #14282 for details on how to test/try this option out.
	// TODO: remove this comment once this option is tested in CI.
	fs.IntVar(&s.KubernetesServiceNodePort, "kubernetes-service-node-port", s.KubernetesServiceNodePort, ""+
		"If non-zero, the Kubernetes master service (which apiserver creates/maintains) will be "+
		"of type NodePort, using this as the value of the port. If zero, the Kubernetes master "+
		"service will be of type ClusterIP.")

	fs.IPNetVar(&s.ServiceClusterIPRange, "service-cluster-ip-range", s.ServiceClusterIPRange, ""+
		"A CIDR notation IP range from which to assign service cluster IPs. This must not "+
		"overlap with any IP ranges assigned to nodes for pods.")

	fs.Var(&s.ServiceNodePortRange, "service-node-port-range", ""+
		"A port range to reserve for services with NodePort visibility. "+
		"Example: '30000-32767'. Inclusive at both ends of the range.")

	// Kubelet related flags:
	fs.BoolVar(&s.KubeletConfig.EnableHttps, "kubelet-https", s.KubeletConfig.EnableHttps,
		"Use https for kubelet connections.")

	fs.StringSliceVar(&s.KubeletConfig.PreferredAddressTypes, "kubelet-preferred-address-types", s.KubeletConfig.PreferredAddressTypes,
		"List of the preferred NodeAddressTypes to use for kubelet connections.")

	fs.UintVar(&s.KubeletConfig.Port, "kubelet-port", s.KubeletConfig.Port,
		"DEPRECATED: kubelet port.")
	fs.MarkDeprecated("kubelet-port", "kubelet-port is deprecated and will be removed.")

	fs.UintVar(&s.KubeletConfig.ReadOnlyPort, "kubelet-read-only-port", s.KubeletConfig.ReadOnlyPort,
		"DEPRECATED: kubelet port.")

	fs.DurationVar(&s.KubeletConfig.HTTPTimeout, "kubelet-timeout", s.KubeletConfig.HTTPTimeout,
		"Timeout for kubelet operations.")

	fs.StringVar(&s.KubeletConfig.CertFile, "kubelet-client-certificate", s.KubeletConfig.CertFile,
		"Path to a client cert file for TLS.")

	fs.StringVar(&s.KubeletConfig.KeyFile, "kubelet-client-key", s.KubeletConfig.KeyFile,
		"Path to a client key file for TLS.")

	fs.StringVar(&s.KubeletConfig.CAFile, "kubelet-certificate-authority", s.KubeletConfig.CAFile,
		"Path to a cert file for the certificate authority.")

	// TODO: delete this flag in 1.13
	repair := false
	fs.BoolVar(&repair, "repair-malformed-updates", false, "deprecated")
	fs.MarkDeprecated("repair-malformed-updates", "This flag will be removed in a future version")

	fs.StringVar(&s.ProxyClientCertFile, "proxy-client-cert-file", s.ProxyClientCertFile, ""+
		"Client certificate used to prove the identity of the aggregator or kube-apiserver "+
		"when it must call out during a request. This includes proxying requests to a user "+
		"api-server and calling out to webhook admission plugins. It is expected that this "+
		"cert includes a signature from the CA in the --requestheader-client-ca-file flag. "+
		"That CA is published in the 'extension-apiserver-authentication' configmap in "+
		"the kube-system namespace. Components receiving calls from kube-aggregator should "+
		"use that CA to perform their half of the mutual TLS verification.")
	fs.StringVar(&s.ProxyClientKeyFile, "proxy-client-key-file", s.ProxyClientKeyFile, ""+
		"Private key for the client certificate used to prove the identity of the aggregator or kube-apiserver "+
		"when it must call out during a request. This includes proxying requests to a user "+
		"api-server and calling out to webhook admission plugins.")

	fs.BoolVar(&s.EnableAggregatorRouting, "enable-aggregator-routing", s.EnableAggregatorRouting,
		"Turns on aggregator routing requests to endpoints IP rather than cluster IP.")

	fs.StringVar(&s.ServiceAccountSigningKeyFile, "service-account-signing-key-file", s.ServiceAccountSigningKeyFile, ""+
		"Path to the file that contains the current private key of the service account token issuer. The issuer will sign issued ID tokens with this private key. (Requires the 'TokenRequest' feature gate.)")

	return fss
}
```

# 4. Run

`Run`以常驻的方式运行apiserver。

**主要内容如下：**

1. 构造一个聚合的server结构体。
2. 执行PrepareRun。
3. 最终执行Run。

> 此部分代码位于cmd/kube-apiserver/app/server.go

```go
// Run runs the specified APIServer.  This should never exit.
func Run(completeOptions completedServerRunOptions, stopCh <-chan struct{}) error {
	// To help debugging, immediately log version
	glog.Infof("Version: %+v", version.Get())

	server, err := CreateServerChain(completeOptions, stopCh)
	if err != nil {
		return err
	}

	return server.PrepareRun().Run(stopCh)
}
```

## 4.1. CreateServerChain

构造聚合的Server。

**基本流程如下：**

1. 首先生成config对象，包括`kubeAPIServerConfig`、`apiExtensionsConfig`。
2. 再通过config生成server对象，包括`apiExtensionsServer`、`kubeAPIServer`。
3. 执行`apiExtensionsServer`、`kubeAPIServer`的`PrepareRun`部分。
4. 生成聚合的config对象`aggregatorConfig`。
5. 基于`aggregatorConfig`、`kubeAPIServer`、`apiExtensionsServer`生成聚合的server`aggregatorServer`。

> 此部分代码位于cmd/kube-apiserver/app/server.go

```go
// CreateServerChain creates the apiservers connected via delegation.
func CreateServerChain(completedOptions completedServerRunOptions, stopCh <-chan struct{}) (*genericapiserver.GenericAPIServer, error) {
	nodeTunneler, proxyTransport, err := CreateNodeDialer(completedOptions)
	if err != nil {
		return nil, err
	}

	kubeAPIServerConfig, insecureServingInfo, serviceResolver, pluginInitializer, admissionPostStartHook, err := CreateKubeAPIServerConfig(completedOptions, nodeTunneler, proxyTransport)
	if err != nil {
		return nil, err
	}

	// If additional API servers are added, they should be gated.
	apiExtensionsConfig, err := createAPIExtensionsConfig(*kubeAPIServerConfig.GenericConfig, kubeAPIServerConfig.ExtraConfig.VersionedInformers, pluginInitializer, completedOptions.ServerRunOptions, completedOptions.MasterCount)
	if err != nil {
		return nil, err
	}
	apiExtensionsServer, err := createAPIExtensionsServer(apiExtensionsConfig, genericapiserver.NewEmptyDelegate())
	if err != nil {
		return nil, err
	}

	kubeAPIServer, err := CreateKubeAPIServer(kubeAPIServerConfig, apiExtensionsServer.GenericAPIServer, admissionPostStartHook)
	if err != nil {
		return nil, err
	}

	// otherwise go down the normal path of standing the aggregator up in front of the API server
	// this wires up openapi
	kubeAPIServer.GenericAPIServer.PrepareRun()

	// This will wire up openapi for extension api server
	apiExtensionsServer.GenericAPIServer.PrepareRun()

	// aggregator comes last in the chain
	aggregatorConfig, err := createAggregatorConfig(*kubeAPIServerConfig.GenericConfig, completedOptions.ServerRunOptions, kubeAPIServerConfig.ExtraConfig.VersionedInformers, serviceResolver, proxyTransport, pluginInitializer)
	if err != nil {
		return nil, err
	}
	aggregatorServer, err := createAggregatorServer(aggregatorConfig, kubeAPIServer.GenericAPIServer, apiExtensionsServer.Informers)
	if err != nil {
		// we don't need special handling for innerStopCh because the aggregator server doesn't create any go routines
		return nil, err
	}

	if insecureServingInfo != nil {
		insecureHandlerChain := kubeserver.BuildInsecureHandlerChain(aggregatorServer.GenericAPIServer.UnprotectedHandler(), kubeAPIServerConfig.GenericConfig)
		if err := insecureServingInfo.Serve(insecureHandlerChain, kubeAPIServerConfig.GenericConfig.RequestTimeout, stopCh); err != nil {
			return nil, err
		}
	}

	return aggregatorServer.GenericAPIServer, nil
}
```

## 4.2. PrepareRun

`PrepareRun`主要执行一些API安装操作。

> 此部分的代码位于vendor/k8s.io/apiserver/pkg/server/genericapiserver.go

```go
// PrepareRun does post API installation setup steps.
func (s *GenericAPIServer) PrepareRun() preparedGenericAPIServer {
	if s.swaggerConfig != nil {
		routes.Swagger{Config: s.swaggerConfig}.Install(s.Handler.GoRestfulContainer)
	}
	if s.openAPIConfig != nil {
		routes.OpenAPI{
			Config: s.openAPIConfig,
		}.Install(s.Handler.GoRestfulContainer, s.Handler.NonGoRestfulMux)
	}

	s.installHealthz()

	// Register audit backend preShutdownHook.
	if s.AuditBackend != nil {
		s.AddPreShutdownHook("audit-backend", func() error {
			s.AuditBackend.Shutdown()
			return nil
		})
	}

	return preparedGenericAPIServer{s}
}
```

## 4.3. preparedGenericAPIServer.Run

`preparedGenericAPIServer.Run`运行一个安全的http server。具体的实现逻辑待后续文章分析。

> 此部分代码位于vendor/k8s.io/apiserver/pkg/server/genericapiserver.go

```go
// Run spawns the secure http server. It only returns if stopCh is closed
// or the secure port cannot be listened on initially.
func (s preparedGenericAPIServer) Run(stopCh <-chan struct{}) error {
	err := s.NonBlockingRun(stopCh)
	if err != nil {
		return err
	}

	<-stopCh

	err = s.RunPreShutdownHooks()
	if err != nil {
		return err
	}

	// Wait for all requests to finish, which are bounded by the RequestTimeout variable.
	s.HandlerChainWaitGroup.Wait()

	return nil
}
```

核心函数：

```go
err := s.NonBlockingRun(stopCh)
```

`preparedGenericAPIServer.Run`主要是调用`NonBlockingRun`函数，最终运行一个http server。该部分逻辑待后续文章分析。

# 5. 总结

`NewAPIServerCommand`采用了[Cobra](https://github.com/spf13/cobra)命令行框架，该框架使用主要包含以下部分：

- 构造option参数，提供给执行主体(例如 本文的server)作为配置参数使用。
- 添加Flags，主要用来通过传入的flags参数最终解析成option中使用的结构体属性。
- 执行Run函数，执行主体的运行逻辑部分（核心部分）。



其中Run函数的主要内容如下：

1. 构造一个聚合的server结构体。
2. 执行PrepareRun。
3. 最终执行preparedGenericAPIServer.Run。

`preparedGenericAPIServer.Run`主要是调用`NonBlockingRun`函数，最终运行一个http server。`NonBlockingRun`的具体逻辑待后续文章再单独分析。



参考：

- <https://github.com/kubernetes/kubernetes/tree/v1.12.0/cmd/kube-apiserver>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-apiserver/app/server.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-apiserver/app/aggregator.go>
- <https://github.com/kubernetes/kubernetes/blob/v1.12.0/cmd/kube-apiserver/app/options/options.go>