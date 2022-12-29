---
title: "client-go的使用及源码分析"
weight: 1
catalog: true
date: 2017-12-16 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- 源码分析
- Kubernetes
catagories:
- 源码分析
---

# 1. client-go简介

## 1.1 client-go说明

​	client-go是一个调用kubernetes集群资源对象API的客户端，即通过client-go实现对kubernetes集群中资源对象（包括deployment、service、ingress、replicaSet、pod、namespace、node等）的增删改查等操作。大部分对kubernetes进行前置API封装的二次开发都通过client-go这个第三方包来实现。

​	client-go官方文档：https://github.com/kubernetes/client-go

## 1.2 示例代码

```shell
git clone https://github.com/huweihuang/client-go.git
cd client-go
#保证本地HOME目录有配置kubernetes集群的配置文件
go run client-go.go
```

**[client-go.go](https://github.com/huweihuang/client-go/blob/master/client-go.go)**

```go
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

func main() {
	var kubeconfig *string
	if home := homeDir(); home != "" {
		kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
	} else {
		kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
	}
	flag.Parse()
	// uses the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		panic(err.Error())
	}
	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}
	for {
		pods, err := clientset.CoreV1().Pods("").List(metav1.ListOptions{})
		if err != nil {
			panic(err.Error())
		}
		fmt.Printf("There are %d pods in the cluster\n", len(pods.Items))
		time.Sleep(10 * time.Second)
	}
}

func homeDir() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	return os.Getenv("USERPROFILE") // windows
}
```

## 1.3 运行结果

```shell
➜ go run client-go.go
There are 9 pods in the cluster
There are 7 pods in the cluster
There are 7 pods in the cluster
There are 7 pods in the cluster
There are 7 pods in the cluster
```

# 2. client-go源码分析

**client-go源码**：https://github.com/kubernetes/client-go

**client-go源码目录结构**

- The `kubernetes` package contains the clientset to access Kubernetes API.
- The `discovery` package is used to discover APIs supported by a Kubernetes API server.
- The `dynamic` package contains a dynamic client that can perform generic operations on arbitrary Kubernetes API objects.
- The `transport` package is used to set up auth and start a connection.
- The `tools/cache` package is useful for writing controllers.

## 2.1 kubeconfig

```Go
kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
```

获取kubernetes配置文件kubeconfig的绝对路径。一般路径为`$HOME/.kube/config`。该文件主要用来配置本地连接的kubernetes集群。

config内容如下：

```shell
apiVersion: v1
clusters:
- cluster:
    server: http://<kube-master-ip>:8080
  name: k8s
contexts:
- context:
    cluster: k8s
    namespace: default
    user: ""
  name: default
current-context: default
kind: Config
preferences: {}
users: []
```

## 2.2 rest.config

通过参数（master的url或者kubeconfig路径）和`BuildConfigFromFlags`方法来获取`rest.Config`对象，一般是通过参数kubeconfig的路径。

```Go
config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
```

**BuildConfigFromFlags函数源码**

[k8s.io/client-go/tools/clientcmd/client_config.go](https://github.com/kubernetes/client-go/blob/master/tools/clientcmd/client_config.go#L522)

```Go
// BuildConfigFromFlags is a helper function that builds configs from a master
// url or a kubeconfig filepath. These are passed in as command line flags for cluster
// components. Warnings should reflect this usage. If neither masterUrl or kubeconfigPath
// are passed in we fallback to inClusterConfig. If inClusterConfig fails, we fallback
// to the default config.
func BuildConfigFromFlags(masterUrl, kubeconfigPath string) (*restclient.Config, error) {
	if kubeconfigPath == "" && masterUrl == "" {
		glog.Warningf("Neither --kubeconfig nor --master was specified.  Using the inClusterConfig.  This might not work.")
		kubeconfig, err := restclient.InClusterConfig()
		if err == nil {
			return kubeconfig, nil
		}
		glog.Warning("error creating inClusterConfig, falling back to default config: ", err)
	}
	return NewNonInteractiveDeferredLoadingClientConfig(
		&ClientConfigLoadingRules{ExplicitPath: kubeconfigPath},
		&ConfigOverrides{ClusterInfo: clientcmdapi.Cluster{Server: masterUrl}}).ClientConfig()
}
```

## 2.3 clientset

通过`*rest.Config`参数和`NewForConfig`方法来获取`clientset`对象，`clientset`是多个`client`的集合，每个`client`可能包含不同版本的方法调用。

```Go
clientset, err := kubernetes.NewForConfig(config)
```
### 2.3.1 NewForConfig

`NewForConfig`函数就是初始化clientset中的每个client。

[k8s.io/client-go/kubernetes/clientset.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/clientset.go#L396)

```go
// NewForConfig creates a new Clientset for the given config.
func NewForConfig(c *rest.Config) (*Clientset, error) {
	configShallowCopy := *c
	...
	var cs Clientset
	cs.appsV1beta1, err = appsv1beta1.NewForConfig(&configShallowCopy)
	...
	cs.coreV1, err = corev1.NewForConfig(&configShallowCopy)
	...
}
```

### 2.3.2 clientset的结构体

[k8s.io/client-go/kubernetes/clientset.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/clientset.go#L118)

```go
// Clientset contains the clients for groups. Each group has exactly one
// version included in a Clientset.
type Clientset struct {
	*discovery.DiscoveryClient
	admissionregistrationV1alpha1 *admissionregistrationv1alpha1.AdmissionregistrationV1alpha1Client
	appsV1beta1                   *appsv1beta1.AppsV1beta1Client
	appsV1beta2                   *appsv1beta2.AppsV1beta2Client
	authenticationV1              *authenticationv1.AuthenticationV1Client
	authenticationV1beta1         *authenticationv1beta1.AuthenticationV1beta1Client
	authorizationV1               *authorizationv1.AuthorizationV1Client
	authorizationV1beta1          *authorizationv1beta1.AuthorizationV1beta1Client
	autoscalingV1                 *autoscalingv1.AutoscalingV1Client
	autoscalingV2beta1            *autoscalingv2beta1.AutoscalingV2beta1Client
	batchV1                       *batchv1.BatchV1Client
	batchV1beta1                  *batchv1beta1.BatchV1beta1Client
	batchV2alpha1                 *batchv2alpha1.BatchV2alpha1Client
	certificatesV1beta1           *certificatesv1beta1.CertificatesV1beta1Client
	coreV1                        *corev1.CoreV1Client
	extensionsV1beta1             *extensionsv1beta1.ExtensionsV1beta1Client
	networkingV1                  *networkingv1.NetworkingV1Client
	policyV1beta1                 *policyv1beta1.PolicyV1beta1Client
	rbacV1                        *rbacv1.RbacV1Client
	rbacV1beta1                   *rbacv1beta1.RbacV1beta1Client
	rbacV1alpha1                  *rbacv1alpha1.RbacV1alpha1Client
	schedulingV1alpha1            *schedulingv1alpha1.SchedulingV1alpha1Client
	settingsV1alpha1              *settingsv1alpha1.SettingsV1alpha1Client
	storageV1beta1                *storagev1beta1.StorageV1beta1Client
	storageV1                     *storagev1.StorageV1Client
}
```

### 2.3.3 clientset.Interface

clientset实现了以下的Interface，因此可以通过调用以下方法获得具体的client。例如：

```go
pods, err := clientset.CoreV1().Pods("").List(metav1.ListOptions{})
```

**clientset的方法集接口**

[k8s.io/client-go/kubernetes/clientset.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/clientset.go#L54)

```go
type Interface interface {
	Discovery() discovery.DiscoveryInterface
	AdmissionregistrationV1alpha1() admissionregistrationv1alpha1.AdmissionregistrationV1alpha1Interface
	// Deprecated: please explicitly pick a version if possible.
	Admissionregistration() admissionregistrationv1alpha1.AdmissionregistrationV1alpha1Interface
	AppsV1beta1() appsv1beta1.AppsV1beta1Interface
	AppsV1beta2() appsv1beta2.AppsV1beta2Interface
	// Deprecated: please explicitly pick a version if possible.
	Apps() appsv1beta2.AppsV1beta2Interface
	AuthenticationV1() authenticationv1.AuthenticationV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Authentication() authenticationv1.AuthenticationV1Interface
	AuthenticationV1beta1() authenticationv1beta1.AuthenticationV1beta1Interface
	AuthorizationV1() authorizationv1.AuthorizationV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Authorization() authorizationv1.AuthorizationV1Interface
	AuthorizationV1beta1() authorizationv1beta1.AuthorizationV1beta1Interface
	AutoscalingV1() autoscalingv1.AutoscalingV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Autoscaling() autoscalingv1.AutoscalingV1Interface
	AutoscalingV2beta1() autoscalingv2beta1.AutoscalingV2beta1Interface
	BatchV1() batchv1.BatchV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Batch() batchv1.BatchV1Interface
	BatchV1beta1() batchv1beta1.BatchV1beta1Interface
	BatchV2alpha1() batchv2alpha1.BatchV2alpha1Interface
	CertificatesV1beta1() certificatesv1beta1.CertificatesV1beta1Interface
	// Deprecated: please explicitly pick a version if possible.
	Certificates() certificatesv1beta1.CertificatesV1beta1Interface
	CoreV1() corev1.CoreV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Core() corev1.CoreV1Interface
	ExtensionsV1beta1() extensionsv1beta1.ExtensionsV1beta1Interface
	// Deprecated: please explicitly pick a version if possible.
	Extensions() extensionsv1beta1.ExtensionsV1beta1Interface
	NetworkingV1() networkingv1.NetworkingV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Networking() networkingv1.NetworkingV1Interface
	PolicyV1beta1() policyv1beta1.PolicyV1beta1Interface
	// Deprecated: please explicitly pick a version if possible.
	Policy() policyv1beta1.PolicyV1beta1Interface
	RbacV1() rbacv1.RbacV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Rbac() rbacv1.RbacV1Interface
	RbacV1beta1() rbacv1beta1.RbacV1beta1Interface
	RbacV1alpha1() rbacv1alpha1.RbacV1alpha1Interface
	SchedulingV1alpha1() schedulingv1alpha1.SchedulingV1alpha1Interface
	// Deprecated: please explicitly pick a version if possible.
	Scheduling() schedulingv1alpha1.SchedulingV1alpha1Interface
	SettingsV1alpha1() settingsv1alpha1.SettingsV1alpha1Interface
	// Deprecated: please explicitly pick a version if possible.
	Settings() settingsv1alpha1.SettingsV1alpha1Interface
	StorageV1beta1() storagev1beta1.StorageV1beta1Interface
	StorageV1() storagev1.StorageV1Interface
	// Deprecated: please explicitly pick a version if possible.
	Storage() storagev1.StorageV1Interface
}
```

## 2.4 CoreV1Client

我们以clientset中的`CoreV1Client`为例做分析。

通过传入的配置信息`rest.Config`初始化`CoreV1Client`对象。

[k8s.io/client-go/kubernetes/clientset.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/clientset.go#L464)

```Go
cs.coreV1, err = corev1.NewForConfig(&configShallowCopy)
```

### 2.4.1 corev1.NewForConfig

[k8s.io/client-go/kubernetes/typed/core/v1/core_client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/core_client.go#L116:6)

```go
// NewForConfig creates a new CoreV1Client for the given config.
func NewForConfig(c *rest.Config) (*CoreV1Client, error) {
	config := *c
	if err := setConfigDefaults(&config); err != nil {
		return nil, err
	}
	client, err := rest.RESTClientFor(&config)
	if err != nil {
		return nil, err
	}
	return &CoreV1Client{client}, nil
}
```

`corev1.NewForConfig`方法本质是调用了`rest.RESTClientFor(&config)`方法创建`RESTClient`对象，即`CoreV1Client`的本质就是一个`RESTClient`对象。

### 2.4.2 CoreV1Client结构体

以下是`CoreV1Client`结构体的定义：

[k8s.io/client-go/kubernetes/typed/core/v1/core_client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/core_client.go#L47:6)

```go
// CoreV1Client is used to interact with features provided by the  group.
type CoreV1Client struct {
	restClient rest.Interface
}
```

`CoreV1Client`实现了`CoreV1Interface`的接口，即以下方法，从而对kubernetes的资源对象进行增删改查的操作。

[k8s.io/client-go/kubernetes/typed/core/v1/core_client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/core_client.go#L51)

```go
//CoreV1Client的方法
func (c *CoreV1Client) ComponentStatuses() ComponentStatusInterface {...}
//ConfigMaps
func (c *CoreV1Client) ConfigMaps(namespace string) ConfigMapInterface {...}
//Endpoints
func (c *CoreV1Client) Endpoints(namespace string) EndpointsInterface {...}
func (c *CoreV1Client) Events(namespace string) EventInterface {...}
func (c *CoreV1Client) LimitRanges(namespace string) LimitRangeInterface {...}
//Namespaces
func (c *CoreV1Client) Namespaces() NamespaceInterface {...}
//Nodes
func (c *CoreV1Client) Nodes() NodeInterface {...}
func (c *CoreV1Client) PersistentVolumes() PersistentVolumeInterface {...}
func (c *CoreV1Client) PersistentVolumeClaims(namespace string) PersistentVolumeClaimInterface {...}
//Pods
func (c *CoreV1Client) Pods(namespace string) PodInterface {...}
func (c *CoreV1Client) PodTemplates(namespace string) PodTemplateInterface {...}
//ReplicationControllers
func (c *CoreV1Client) ReplicationControllers(namespace string) ReplicationControllerInterface {...}
func (c *CoreV1Client) ResourceQuotas(namespace string) ResourceQuotaInterface {...}
func (c *CoreV1Client) Secrets(namespace string) SecretInterface {...}
//Services
func (c *CoreV1Client) Services(namespace string) ServiceInterface {...}
func (c *CoreV1Client) ServiceAccounts(namespace string) ServiceAccountInterface {...}
```

### 2.4.3 CoreV1Interface

[k8s.io/client-go/kubernetes/typed/core/v1/core_client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/core_client.go#L26)

```go
type CoreV1Interface interface {
	RESTClient() rest.Interface
	ComponentStatusesGetter
	ConfigMapsGetter
	EndpointsGetter
	EventsGetter
	LimitRangesGetter
	NamespacesGetter
	NodesGetter
	PersistentVolumesGetter
	PersistentVolumeClaimsGetter
	PodsGetter
	PodTemplatesGetter
	ReplicationControllersGetter
	ResourceQuotasGetter
	SecretsGetter
	ServicesGetter
	ServiceAccountsGetter
}
```

`CoreV1Interface`中包含了各种`kubernetes`对象的调用接口，例如`PodsGetter`是对kubernetes中`pod`对象增删改查操作的接口。`ServicesGetter`是对`service`对象的操作的接口。

### 2.4.4 PodsGetter

以下我们以`PodsGetter`接口为例分析`CoreV1Client`对`pod`对象的增删改查接口调用。

示例中的代码如下：

```go
pods, err := clientset.CoreV1().Pods("").List(metav1.ListOptions{})
```

**CoreV1().Pods()**

[k8s.io/client-go/kubernetes/typed/core/v1/core_client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/core_client.go#L87)

```go
func (c *CoreV1Client) Pods(namespace string) PodInterface {
	return newPods(c, namespace)
}
```

**newPods()**

[k8s.io/client-go/kubernetes/typed/core/v1/pod.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/pod.go#L54)

```go
// newPods returns a Pods
func newPods(c *CoreV1Client, namespace string) *pods {
	return &pods{
		client: c.RESTClient(),
		ns:     namespace,
	}
}
```

`CoreV1().Pods()`的方法实际上是调用了`newPods()`的方法，创建了一个`pods`对象，`pods`对象继承了`rest.Interface`接口，即最终的实现本质是`RESTClient`的HTTP调用。

[k8s.io/client-go/kubernetes/typed/core/v1/pod.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/pod.go#L48)

```go
// pods implements PodInterface
type pods struct {
	client rest.Interface
	ns     string
}
```

`pods`对象实现了`PodInterface`接口。`PodInterface`定义了`pods`对象的增删改查等方法。

[k8s.io/client-go/kubernetes/typed/core/v1/pod.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/pod.go#L34)

```go
// PodInterface has methods to work with Pod resources.
type PodInterface interface {
	Create(*v1.Pod) (*v1.Pod, error)
	Update(*v1.Pod) (*v1.Pod, error)
	UpdateStatus(*v1.Pod) (*v1.Pod, error)
	Delete(name string, options *meta_v1.DeleteOptions) error
	DeleteCollection(options *meta_v1.DeleteOptions, listOptions meta_v1.ListOptions) error
	Get(name string, options meta_v1.GetOptions) (*v1.Pod, error)
	List(opts meta_v1.ListOptions) (*v1.PodList, error)
	Watch(opts meta_v1.ListOptions) (watch.Interface, error)
	Patch(name string, pt types.PatchType, data []byte, subresources ...string) (result *v1.Pod, err error)
	PodExpansion
}
```

**PodsGetter**

PodsGetter继承了PodInterface的接口。

[k8s.io/client-go/kubernetes/typed/core/v1/pod.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/pod.go#L28)

```go
// PodsGetter has a method to return a PodInterface.
// A group's client should implement this interface.
type PodsGetter interface {
	Pods(namespace string) PodInterface
}
```

**Pods().List()**

pods.List()方法通过`RESTClient`的HTTP调用来实现对kubernetes的pod资源的获取。

[k8s.io/client-go/kubernetes/typed/core/v1/pod.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/pod.go#L75)

```go
// List takes label and field selectors, and returns the list of Pods that match those selectors.
func (c *pods) List(opts meta_v1.ListOptions) (result *v1.PodList, err error) {
	result = &v1.PodList{}
	err = c.client.Get().
		Namespace(c.ns).
		Resource("pods").
		VersionedParams(&opts, scheme.ParameterCodec).
		Do().
		Into(result)
	return
}
```

以上分析了`clientset.CoreV1().Pods("").List(metav1.ListOptions{})`对pod资源获取的过程，最终是调用`RESTClient`的方法实现。

## 2.5 RESTClient

以下分析`RESTClient`的创建过程及作用。

`RESTClient`对象的创建同样是依赖传入的config信息。

[k8s.io/client-go/kubernetes/typed/core/v1/core_client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/kubernetes/typed/core/v1/core_client.go#L121)

```go
client, err := rest.RESTClientFor(&config)
```

### 2.5.1 rest.RESTClientFor

[k8s.io/client-go/rest/config.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/rest/config.go#L182)

```go
// RESTClientFor returns a RESTClient that satisfies the requested attributes on a client Config
// object. Note that a RESTClient may require fields that are optional when initializing a Client.
// A RESTClient created by this method is generic - it expects to operate on an API that follows
// the Kubernetes conventions, but may not be the Kubernetes API.
func RESTClientFor(config *Config) (*RESTClient, error) {
	...
	qps := config.QPS
	...
	burst := config.Burst
	...
	baseURL, versionedAPIPath, err := defaultServerUrlFor(config)
	...
	transport, err := TransportFor(config)
	...
	var httpClient *http.Client
	if transport != http.DefaultTransport {
		httpClient = &http.Client{Transport: transport}
		if config.Timeout > 0 {
			httpClient.Timeout = config.Timeout
		}
	}

	return NewRESTClient(baseURL, versionedAPIPath, config.ContentConfig, qps, burst, config.RateLimiter, httpClient)
}
```

`RESTClientFor`函数调用了`NewRESTClient`的初始化函数。

### 2.5.2 NewRESTClient

[k8s.io/client-go/rest/client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/rest/client.go#L91)

```go
// NewRESTClient creates a new RESTClient. This client performs generic REST functions
// such as Get, Put, Post, and Delete on specified paths.  Codec controls encoding and
// decoding of responses from the server.
func NewRESTClient(baseURL *url.URL, versionedAPIPath string, config ContentConfig, maxQPS float32, maxBurst int, rateLimiter flowcontrol.RateLimiter, client *http.Client) (*RESTClient, error) {
	base := *baseURL
	...
	serializers, err := createSerializers(config)
	...
	return &RESTClient{
		base:             &base,
		versionedAPIPath: versionedAPIPath,
		contentConfig:    config,
		serializers:      *serializers,
		createBackoffMgr: readExpBackoffConfig,
		Throttle:         throttle,
		Client:           client,
	}, nil
}
```

### 2.5.3 RESTClient结构体

以下介绍RESTClient的结构体定义，RESTClient结构体中包含了`http.Client`，即本质上RESTClient就是一个`http.Client`的封装实现。

[k8s.io/client-go/rest/client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/rest/client.go#L54)

```go
// RESTClient imposes common Kubernetes API conventions on a set of resource paths.
// The baseURL is expected to point to an HTTP or HTTPS path that is the parent
// of one or more resources.  The server should return a decodable API resource
// object, or an api.Status object which contains information about the reason for
// any failure.
//
// Most consumers should use client.New() to get a Kubernetes API client.
type RESTClient struct {
	// base is the root URL for all invocations of the client
	base *url.URL
	// versionedAPIPath is a path segment connecting the base URL to the resource root
	versionedAPIPath string

	// contentConfig is the information used to communicate with the server.
	contentConfig ContentConfig

	// serializers contain all serializers for underlying content type.
	serializers Serializers

	// creates BackoffManager that is passed to requests.
	createBackoffMgr func() BackoffManager

	// TODO extract this into a wrapper interface via the RESTClient interface in kubectl.
	Throttle flowcontrol.RateLimiter

	// Set specific behavior of the client.  If not set http.DefaultClient will be used.
	Client *http.Client
}
```

### 2.5.4 RESTClient.Interface

RESTClient实现了以下的接口方法：

[k8s.io/client-go/rest/client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/rest/client.go#L42)

```go
// Interface captures the set of operations for generically interacting with Kubernetes REST apis.
type Interface interface {
	GetRateLimiter() flowcontrol.RateLimiter
	Verb(verb string) *Request
	Post() *Request
	Put() *Request
	Patch(pt types.PatchType) *Request
	Get() *Request
	Delete() *Request
	APIVersion() schema.GroupVersion
}
```

在调用HTTP方法（Post()，Put()，Get()，Delete() ）时，实际上调用了Verb(verb string)函数。

[k8s.io/client-go/rest/client.go](https://github.com/kubernetes/client-go/blob/87887458218a51f3944b2f4c553eb38173458e97/rest/client.go#L208)

```go
// Verb begins a request with a verb (GET, POST, PUT, DELETE).
//
// Example usage of RESTClient's request building interface:
// c, err := NewRESTClient(...)
// if err != nil { ... }
// resp, err := c.Verb("GET").
//  Path("pods").
//  SelectorParam("labels", "area=staging").
//  Timeout(10*time.Second).
//  Do()
// if err != nil { ... }
// list, ok := resp.(*api.PodList)
//
func (c *RESTClient) Verb(verb string) *Request {
	backoff := c.createBackoffMgr()

	if c.Client == nil {
		return NewRequest(nil, verb, c.base, c.versionedAPIPath, c.contentConfig, c.serializers, backoff, c.Throttle)
	}
	return NewRequest(c.Client, verb, c.base, c.versionedAPIPath, c.contentConfig, c.serializers, backoff, c.Throttle)
}
```

`Verb`函数调用了`NewRequest`方法，最后调用`Do()`方法实现一个HTTP请求获取Result。

## 2.6 总结

`client-go`对kubernetes资源对象的调用，需要先获取kubernetes的配置信息，即`$HOME/.kube/config`。

整个调用的过程如下：

kubeconfig→rest.config→clientset→具体的client(CoreV1Client)→具体的资源对象(pod)→RESTClient→http.Client→HTTP请求的发送及响应

通过clientset中不同的client和client中不同资源对象的方法实现对kubernetes中资源对象的增删改查等操作，常用的client有`CoreV1Client`、`AppsV1beta1Client`、`ExtensionsV1beta1Client`等。

# 3. client-go对k8s资源的调用

**创建clientset**

```go
//获取kubeconfig
kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
//创建config	
config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
//创建clientset
clientset, err := kubernetes.NewForConfig(config)
//具体的资源调用见以下例子
```

## 3.1 deployment

```go
//声明deployment对象
var deployment *v1beta1.Deployment
//构造deployment对象
//创建deployment
deployment, err := clientset.AppsV1beta1().Deployments(<namespace>).Create(<deployment>)
//更新deployment
deployment, err := clientset.AppsV1beta1().Deployments(<namespace>).Update(<deployment>)
//删除deployment
err := clientset.AppsV1beta1().Deployments(<namespace>).Delete(<deployment.Name>, &meta_v1.DeleteOptions{})
//查询deployment
deployment, err := clientset.AppsV1beta1().Deployments(<namespace>).Get(<deployment.Name>, meta_v1.GetOptions{})
//列出deployment
deploymentList, err := clientset.AppsV1beta1().Deployments(<namespace>).List(&meta_v1.ListOptions{})
//watch deployment
watchInterface, err := clientset.AppsV1beta1().Deployments(<namespace>).Watch(&meta_v1.ListOptions{})
```

## 3.2 service

```go
//声明service对象
var service *v1.Service
//构造service对象
//创建service
service, err := clientset.CoreV1().Services(<namespace>).Create(<service>)
//更新service
service, err := clientset.CoreV1().Services(<namespace>).Update(<service>)
//删除service
err := clientset.CoreV1().Services(<namespace>).Delete(<service.Name>, &meta_v1.DeleteOptions{})
//查询service
service, err := clientset.CoreV1().Services(<namespace>).Get(<service.Name>, meta_v1.GetOptions{})
//列出service
serviceList, err := clientset.CoreV1().Services(<namespace>).List(&meta_v1.ListOptions{})
//watch service
watchInterface, err := clientset.CoreV1().Services(<namespace>).Watch(&meta_v1.ListOptions{})
```

## 3.3 ingress

```go
//声明ingress对象
var ingress *v1beta1.Ingress
//构造ingress对象
//创建ingress
ingress, err := clientset.ExtensionsV1beta1().Ingresses(<namespace>).Create(<ingress>)
//更新ingress
ingress, err := clientset.ExtensionsV1beta1().Ingresses(<namespace>).Update(<ingress>)
//删除ingress
err := clientset.ExtensionsV1beta1().Ingresses(<namespace>).Delete(<ingress.Name>, &meta_v1.DeleteOptions{})
//查询ingress
ingress, err := clientset.ExtensionsV1beta1().Ingresses(<namespace>).Get(<ingress.Name>, meta_v1.GetOptions{})
//列出ingress
ingressList, err := clientset.ExtensionsV1beta1().Ingresses(<namespace>).List(&meta_v1.ListOptions{})
//watch ingress
watchInterface, err := clientset.ExtensionsV1beta1().Ingresses(<namespace>).Watch(&meta_v1.ListOptions{})
```

## 3.4 replicaSet

```go
//声明replicaSet对象
var replicaSet *v1beta1.ReplicaSet
//构造replicaSet对象
//创建replicaSet
replicaSet, err := clientset.ExtensionsV1beta1().ReplicaSets(<namespace>).Create(<replicaSet>)
//更新replicaSet
replicaSet, err := clientset.ExtensionsV1beta1().ReplicaSets(<namespace>).Update(<replicaSet>)
//删除replicaSet
err := clientset.ExtensionsV1beta1().ReplicaSets(<namespace>).Delete(<replicaSet.Name>, &meta_v1.DeleteOptions{})
//查询replicaSet
replicaSet, err := clientset.ExtensionsV1beta1().ReplicaSets(<namespace>).Get(<replicaSet.Name>, meta_v1.GetOptions{})
//列出replicaSet
replicaSetList, err := clientset.ExtensionsV1beta1().ReplicaSets(<namespace>).List(&meta_v1.ListOptions{})
//watch replicaSet
watchInterface, err := clientset.ExtensionsV1beta1().ReplicaSets(<namespace>).Watch(&meta_v1.ListOptions{})
```

新版的kubernetes中一般通过deployment来创建replicaSet，再通过replicaSet来控制pod。

## 3.5 pod

```go
//声明pod对象
var pod *v1.Pod
//创建pod
pod, err := clientset.CoreV1().Pods(<namespace>).Create(<pod>)
//更新pod
pod, err := clientset.CoreV1().Pods(<namespace>).Update(<pod>)
//删除pod
err := clientset.CoreV1().Pods(<namespace>).Delete(<pod.Name>, &meta_v1.DeleteOptions{})
//查询pod
pod, err := clientset.CoreV1().Pods(<namespace>).Get(<pod.Name>, meta_v1.GetOptions{})
//列出pod
podList, err := clientset.CoreV1().Pods(<namespace>).List(&meta_v1.ListOptions{})
//watch pod
watchInterface, err := clientset.CoreV1().Pods(<namespace>).Watch(&meta_v1.ListOptions{})
```

## 3.6 statefulset

```go
//声明statefulset对象
var statefulset *v1.StatefulSet
//创建statefulset
statefulset, err := clientset.AppsV1().StatefulSets(<namespace>).Create(<statefulset>)
//更新statefulset
statefulset, err := clientset.AppsV1().StatefulSets(<namespace>).Update(<statefulset>)
//删除statefulset
err := clientset.AppsV1().StatefulSets(<namespace>).Delete(<statefulset.Name>, &meta_v1.DeleteOptions{})
//查询statefulset
statefulset, err := clientset.AppsV1().StatefulSets(<namespace>).Get(<statefulset.Name>, meta_v1.GetOptions{})
//列出statefulset
statefulsetList, err := clientset.AppsV1().StatefulSets(<namespace>).List(&meta_v1.ListOptions{})
//watch statefulset
watchInterface, err := clientset.AppsV1().StatefulSets(<namespace>).Watch(&meta_v1.ListOptions{})
```

​	通过以上对kubernetes的资源对象的操作函数可以看出，每个资源对象都有增删改查等方法，基本调用逻辑类似。一般二次开发只需要创建deployment、service、ingress三个资源对象即可，pod对象由deployment包含的replicaSet来控制创建和删除。函数调用的入参一般只有`NAMESPACE`和`kubernetesObject`两个参数，部分操作有`Options`的参数。在创建前，需要对资源对象构造数据，可以理解为编辑一个资源对象的yaml文件，然后通过`kubectl create -f xxx.yaml`来创建对象。


参考文档:

- https://github.com/kubernetes/client-go
