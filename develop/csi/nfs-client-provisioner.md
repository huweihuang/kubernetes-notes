---
title: "nfs-client-provisioner源码分析"
weight: 2
catalog: true
date: 2018-6-24 15:24:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1542285471/header/building.jpg"
tags:
- 源码分析
catagories:
- 源码分析
---

> 如果要开发一个`Dynamic Provisioner`，需要使用到[the helper library](https://github.com/kubernetes-incubator/external-storage/tree/master/lib)。

# 1. Dynamic Provisioner

## 1.1. Provisioner Interface

开发`Dynamic Provisioner`需要实现[Provisioner](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/volume.go#L29)接口，该接口有两个方法，分别是：

- Provision：创建存储资源，并且返回一个PV对象。
- Delete：移除对应的存储资源，但并没有删除PV对象。

[Provisioner](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/volume.go#L29) 接口源码如下：

```go
// Provisioner is an interface that creates templates for PersistentVolumes
// and can create the volume as a new resource in the infrastructure provider.
// It can also remove the volume it created from the underlying storage
// provider.
type Provisioner interface {
	// Provision creates a volume i.e. the storage asset and returns a PV object
	// for the volume
	Provision(VolumeOptions) (*v1.PersistentVolume, error)
	// Delete removes the storage asset that was created by Provision backing the
	// given PV. Does not delete the PV object itself.
	//
	// May return IgnoredError to indicate that the call has been ignored and no
	// action taken.
	Delete(*v1.PersistentVolume) error
}
```

## 1.2. VolumeOptions

`Provisioner`接口的`Provision`方法的入参是一个`VolumeOptions`对象。`VolumeOptions`对象包含了创建PV对象所需要的信息，例如：PV的回收策略，PV的名字，PV所对应的PVC对象以及PVC的`StorageClass`对象使用的参数等。

[VolumeOptions](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/volume.go#L73) 源码如下：

```go
// VolumeOptions contains option information about a volume
// https://github.com/kubernetes/kubernetes/blob/release-1.4/pkg/volume/plugins.go
type VolumeOptions struct {
	// Reclamation policy for a persistent volume
	PersistentVolumeReclaimPolicy v1.PersistentVolumeReclaimPolicy
	// PV.Name of the appropriate PersistentVolume. Used to generate cloud
	// volume name.
	PVName string

	// PV mount options. Not validated - mount of the PVs will simply fail if one is invalid.
	MountOptions []string

	// PVC is reference to the claim that lead to provisioning of a new PV.
	// Provisioners *must* create a PV that would be matched by this PVC,
	// i.e. with required capacity, accessMode, labels matching PVC.Selector and
	// so on.
	PVC *v1.PersistentVolumeClaim
	// Volume provisioning parameters from StorageClass
	Parameters map[string]string

	// Node selected by the scheduler for the volume.
	SelectedNode *v1.Node
	// Topology constraint parameter from StorageClass
	AllowedTopologies []v1.TopologySelectorTerm
}
```

## 1.3. ProvisionController

`ProvisionController`是一个给PVC提供PV的控制器，具体执行`Provisioner`接口的`Provision`和`Delete`的方法的所有逻辑。

## 1.4. 开发provisioner的步骤

1. 写一个`provisioner`实现`Provisioner`接口（包含`Provision`和`Delete`的方法）。
2. 通过该`provisioner`构建`ProvisionController`。
3. 执行`ProvisionController`的`Run`方法。

# 2. NFS Client Provisioner

`nfs-client-provisioner`是一个`automatic provisioner`，使用NFS作为存储，自动创建PV和对应的PVC，本身不提供NFS存储，需要外部先有一套NFS存储服务。

- PV以 `${namespace}-${pvcName}-${pvName}`的命名格式提供（在NFS服务器上）
- PV回收的时候以 `archieved-${namespace}-${pvcName}-${pvName}` 的命名格式（在NFS服务器上）

以下通过`nfs-client-provisioner`的源码分析来说明开发自定义`provisioner`整个过程。`nfs-client-provisioner`的主要代码都在[provisioner.go](https://github.com/kubernetes-incubator/external-storage/blob/master/nfs-client/cmd/nfs-client-provisioner/provisioner.go)的文件中。

> `nfs-client-provisioner`源码地址：https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client

## 2.1. [Main函数](https://github.com/kubernetes-incubator/external-storage/blob/master/nfs-client/cmd/nfs-client-provisioner/provisioner.go#L148)

### 2.1.1. 读取环境变量

源码如下：

```go
func main() {
	flag.Parse()
	flag.Set("logtostderr", "true")

	server := os.Getenv("NFS_SERVER")
	if server == "" {
		glog.Fatal("NFS_SERVER not set")
	}
	path := os.Getenv("NFS_PATH")
	if path == "" {
		glog.Fatal("NFS_PATH not set")
	}
	provisionerName := os.Getenv(provisionerNameKey)
	if provisionerName == "" {
		glog.Fatalf("environment variable %s is not set! Please set it.", provisionerNameKey)
	}
    ...
}   
```

main函数先获取`NFS_SERVER`、`NFS_PATH`、`PROVISIONER_NAME`三个环境变量的值，因此在部署nfs-client-provisioner的时候，需要将这三个环境变量的值传入。

- `NFS_SERVER`：NFS服务端的IP地址。
- `NFS_PATH`：NFS服务端设置的共享目录
- `PROVISIONER_NAME`：provisioner的名字，需要和`StorageClass`对象中的`provisioner`字段一致。

例如`StorageClass`对象的yaml文件如下：

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-nfs-storage
provisioner: fuseim.pri/ifs # or choose another name, must match deployment's env PROVISIONER_NAME'
parameters:
  archiveOnDelete: "false" # When set to "false" your PVs will not be archived by the provisioner upon deletion of the PVC.
```

### 2.1.2. 获取clientset对象

源码如下：

```go
// Create an InClusterConfig and use it to create a client for the controller
// to use to communicate with Kubernetes
config, err := rest.InClusterConfig()
if err != nil {
	glog.Fatalf("Failed to create config: %v", err)
}
clientset, err := kubernetes.NewForConfig(config)
if err != nil {
	glog.Fatalf("Failed to create client: %v", err)
}
```

通过读取对应的k8s的配置，创建`clientset`对象，用来执行k8s对应的API，其中主要包括对PV和PVC等对象的创建删除等操作。

### 2.1.3. 构造nfsProvisioner对象

源码如下：

```go
// The controller needs to know what the server version is because out-of-tree
// provisioners aren't officially supported until 1.5
serverVersion, err := clientset.Discovery().ServerVersion()
if err != nil {
	glog.Fatalf("Error getting server version: %v", err)
}

clientNFSProvisioner := &nfsProvisioner{
	client: clientset,
	server: server,
	path:   path,
}
```

通过`clientset`、`server`、`path`等值构造`nfsProvisioner`对象，同时还获取了k8s的版本信息，因为provisioners的功能在k8s 1.5及以上版本才支持。

`nfsProvisioner`类型定义如下：

```go
type nfsProvisioner struct {
	client kubernetes.Interface
	server string
	path   string
}

var _ controller.Provisioner = &nfsProvisioner{}
```

`nfsProvisioner`是一个自定义的`provisioner`，用来实现`Provisioner`的接口，其中的属性除了`server`、`path`这两个关于NFS相关的参数，还包含了`client`，主要用来调用k8s的API。

```go
var _ controller.Provisioner = &nfsProvisioner{}
```

以上用法用来检测`nfsProvisioner`是否实现了`Provisioner`的接口。

### 2.1.4. 构建并运行ProvisionController

源码如下：

```go
// Start the provision controller which will dynamically provision efs NFS
// PVs
pc := controller.NewProvisionController(clientset, provisionerName, clientNFSProvisioner, serverVersion.GitVersion)
pc.Run(wait.NeverStop)
```

通过`nfsProvisioner`构造`ProvisionController`对象并执行`Run`方法，`ProvisionController`实现了具体的PV和PVC的相关逻辑，`Run`方法以常驻进程的方式运行。

## 2.2. [Provision](https://github.com/kubernetes-incubator/external-storage/blob/master/nfs-client/cmd/nfs-client-provisioner/provisioner.go#L56)和[Delete](https://github.com/kubernetes-incubator/external-storage/blob/master/nfs-client/cmd/nfs-client-provisioner/provisioner.go#L99)方法

### 2.2.1. Provision方法

> `nfsProvisioner`的`Provision`方法具体源码参考：https://github.com/kubernetes-incubator/external-storage/blob/master/nfs-client/cmd/nfs-client-provisioner/provisioner.go#L56

`Provision`方法用来创建存储资源，并且返回一个`PV`对象。其中入参是`VolumeOptions`，用来指定`PV`对象的相关属性。

**1、构建PV和PVC的名称**

```go
func (p *nfsProvisioner) Provision(options controller.VolumeOptions) (*v1.PersistentVolume, error) {
	if options.PVC.Spec.Selector != nil {
		return nil, fmt.Errorf("claim Selector is not supported")
	}
	glog.V(4).Infof("nfs provisioner: VolumeOptions %v", options)

	pvcNamespace := options.PVC.Namespace
	pvcName := options.PVC.Name

	pvName := strings.Join([]string{pvcNamespace, pvcName, options.PVName}, "-")

	fullPath := filepath.Join(mountPath, pvName)
	glog.V(4).Infof("creating path %s", fullPath)
	if err := os.MkdirAll(fullPath, 0777); err != nil {
		return nil, errors.New("unable to create directory to provision new pv: " + err.Error())
	}
	os.Chmod(fullPath, 0777)

	path := filepath.Join(p.path, pvName)
    ...
}    
```

通过`VolumeOptions`的入参，构建PV和PVC的名称，以及创建路径path。

**2、构造PV对象**

```go
pv := &v1.PersistentVolume{
	ObjectMeta: metav1.ObjectMeta{
		Name: options.PVName,
	},
	Spec: v1.PersistentVolumeSpec{
		PersistentVolumeReclaimPolicy: options.PersistentVolumeReclaimPolicy,
		AccessModes:                   options.PVC.Spec.AccessModes,
		MountOptions:                  options.MountOptions,
		Capacity: v1.ResourceList{
			v1.ResourceName(v1.ResourceStorage): options.PVC.Spec.Resources.Requests[v1.ResourceName(v1.ResourceStorage)],
		},
		PersistentVolumeSource: v1.PersistentVolumeSource{
			NFS: &v1.NFSVolumeSource{
				Server:   p.server,
				Path:     path,
				ReadOnly: false,
			},
		},
	},
}
return pv, nil
```

综上可以看出，`Provision`方法只是通过`VolumeOptions`参数来构建`PV`对象，并没有执行具体`PV`的创建或删除的操作。

不同类型的`Provisioner`的，一般是`PersistentVolumeSource`类型和参数不同，例如`nfs-provisioner`对应的`PersistentVolumeSource`为`NFS`，并且需要传入`NFS`相关的参数：`Server`，`Path`等。

### 2.2.2. Delete方法

> `nfsProvisioner`的`delete`方法具体源码参考：https://github.com/kubernetes-incubator/external-storage/blob/master/nfs-client/cmd/nfs-client-provisioner/provisioner.go#L99

**1、获取pvName和path等相关参数**

```go
func (p *nfsProvisioner) Delete(volume *v1.PersistentVolume) error {
	path := volume.Spec.PersistentVolumeSource.NFS.Path
	pvName := filepath.Base(path)
	oldPath := filepath.Join(mountPath, pvName)
	if _, err := os.Stat(oldPath); os.IsNotExist(err) {
		glog.Warningf("path %s does not exist, deletion skipped", oldPath)
		return nil
	}
    ...
}    
```

通过`path`和`pvName`生成`oldPath`，其中`oldPath`是原先NFS服务器上`pod`对应的数据持久化存储路径。

**2、获取archiveOnDelete参数并删除数据**

```go
// Get the storage class for this volume.
storageClass, err := p.getClassForVolume(volume)
if err != nil {
	return err
}
// Determine if the "archiveOnDelete" parameter exists.
// If it exists and has a falsey value, delete the directory.
// Otherwise, archive it.
archiveOnDelete, exists := storageClass.Parameters["archiveOnDelete"]
if exists {
	archiveBool, err := strconv.ParseBool(archiveOnDelete)
	if err != nil {
		return err
	}
	if !archiveBool {
		return os.RemoveAll(oldPath)
	}
}
```

如果`storageClass`对象中指定`archiveOnDelete`参数并且值为`false`，则会自动删除`oldPath`下的所有数据，即`pod`对应的数据持久化存储数据。

> `archiveOnDelete`字面意思为删除时是否存档，false表示不存档，即删除数据，true表示存档，即重命名路径。

**3、重命名旧数据路径**

```go
archivePath := filepath.Join(mountPath, "archived-"+pvName)
glog.V(4).Infof("archiving path %s to %s", oldPath, archivePath)
return os.Rename(oldPath, archivePath)
```

如果`storageClass`对象中没有指定`archiveOnDelete`参数或者值为`true`，表明需要删除时存档，即将`oldPath`重命名，命名格式为`oldPath`前面增加`archived-`的前缀。

# 3. [ProvisionController](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L82) 

## 3.1. ProvisionController结构体

> 源码具体参考：https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L82

`ProvisionController`是一个给PVC提供PV的控制器，具体执行`Provisioner`接口的`Provision`和`Delete`的方法的所有逻辑。

### 3.1.1. 入参

```go
// ProvisionController is a controller that provisions PersistentVolumes for
// PersistentVolumeClaims.
type ProvisionController struct {
	client kubernetes.Interface

	// The name of the provisioner for which this controller dynamically
	// provisions volumes. The value of annDynamicallyProvisioned and
	// annStorageProvisioner to set & watch for, respectively
	provisionerName string

	// The provisioner the controller will use to provision and delete volumes.
	// Presumably this implementer of Provisioner carries its own
	// volume-specific options and such that it needs in order to provision
	// volumes.
	provisioner Provisioner

	// Kubernetes cluster server version:
	// * 1.4: storage classes introduced as beta. Technically out-of-tree dynamic
	// provisioning is not officially supported, though it works
	// * 1.5: storage classes stay in beta. Out-of-tree dynamic provisioning is
	// officially supported
	// * 1.6: storage classes enter GA
	kubeVersion *utilversion.Version
    ...
}   
```

`client`、`provisionerName`、`provisioner`、`kubeVersion`等属性作为`NewProvisionController`的入参。

- `client`：clientset客户端，用来调用k8s的API。
- `provisionerName`：provisioner的名字，需要和`StorageClass`对象中的`provisioner`字段一致。
- `provisioner`：具体的provisioner的实现者，本文为`nfsProvisioner`。
- `kubeVersion`：k8s的版本信息。

### 3.1.2. Controller和Informer

```go
type ProvisionController struct {
	...
	claimInformer    cache.SharedInformer
	claims           cache.Store
	claimController  cache.Controller
	volumeInformer   cache.SharedInformer
	volumes          cache.Store
	volumeController cache.Controller
	classInformer    cache.SharedInformer
	classes          cache.Store
	classController  cache.Controller
    ...
}    
```

`ProvisionController`结构体中包含了`PV`、`PVC`、`StorageClass`三个对象的`Controller`、`Informer`和`Store`，主要用来执行这三个对象的相关操作。

- Controller：通用的控制框架
- Informer：消息通知器
- Store：通用的对象存储接口

### 3.1.3. workqueue

```go
type ProvisionController struct {
    ...
	claimQueue  workqueue.RateLimitingInterface
	volumeQueue workqueue.RateLimitingInterface
    ...
}    
```

`claimQueue`和`volumeQueue`分别是`PV`和`PVC`的任务队列。

### 3.1.4. 其他

```go
// Identity of this controller, generated at creation time and not persisted
// across restarts. Useful only for debugging, for seeing the source of
// events. controller.provisioner may have its own, different notion of
// identity which may/may not persist across restarts
id            string
component     string
eventRecorder record.EventRecorder

resyncPeriod time.Duration

exponentialBackOffOnError bool
threadiness               int

createProvisionedPVRetryCount int
createProvisionedPVInterval   time.Duration

failedProvisionThreshold, failedDeleteThreshold int

// The port for metrics server to serve on.
metricsPort int32
// The IP address for metrics server to serve on.
metricsAddress string
// The path of metrics endpoint path.
metricsPath string

// Parameters of leaderelection.LeaderElectionConfig.
leaseDuration, renewDeadline, retryPeriod time.Duration

hasRun     bool
hasRunLock *sync.Mutex
```

## 3.2. [NewProvisionController](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L418)方法

> 源码地址：https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L418

`NewProvisionController`方法主要用来构造`ProvisionController`。

### 3.2.1. 初始化默认值

```go
// NewProvisionController creates a new provision controller using
// the given configuration parameters and with private (non-shared) informers.
func NewProvisionController(
	client kubernetes.Interface,
	provisionerName string,
	provisioner Provisioner,
	kubeVersion string,
	options ...func(*ProvisionController) error,
) *ProvisionController {
	...
	controller := &ProvisionController{
		client:                        client,
		provisionerName:               provisionerName,
		provisioner:                   provisioner,
		kubeVersion:                   utilversion.MustParseSemantic(kubeVersion),
		id:                            id,
		component:                     component,
		eventRecorder:                 eventRecorder,
		resyncPeriod:                  DefaultResyncPeriod,
		exponentialBackOffOnError:     DefaultExponentialBackOffOnError,
		threadiness:                   DefaultThreadiness,
		createProvisionedPVRetryCount: DefaultCreateProvisionedPVRetryCount,
		createProvisionedPVInterval:   DefaultCreateProvisionedPVInterval,
		failedProvisionThreshold:      DefaultFailedProvisionThreshold,
		failedDeleteThreshold:         DefaultFailedDeleteThreshold,
		leaseDuration:                 DefaultLeaseDuration,
		renewDeadline:                 DefaultRenewDeadline,
		retryPeriod:                   DefaultRetryPeriod,
		metricsPort:                   DefaultMetricsPort,
		metricsAddress:                DefaultMetricsAddress,
		metricsPath:                   DefaultMetricsPath,
		hasRun:                        false,
		hasRunLock:                    &sync.Mutex{},
	}
    ...
}    
```

### 3.2.2. 初始化任务队列

```go
ratelimiter := workqueue.NewMaxOfRateLimiter(
	workqueue.NewItemExponentialFailureRateLimiter(15*time.Second, 1000*time.Second),
	&workqueue.BucketRateLimiter{Limiter: rate.NewLimiter(rate.Limit(10), 100)},
)
if !controller.exponentialBackOffOnError {
	ratelimiter = workqueue.NewMaxOfRateLimiter(
		workqueue.NewItemExponentialFailureRateLimiter(15*time.Second, 15*time.Second),
		&workqueue.BucketRateLimiter{Limiter: rate.NewLimiter(rate.Limit(10), 100)},
	)
}
controller.claimQueue = workqueue.NewNamedRateLimitingQueue(ratelimiter, "claims")
controller.volumeQueue = workqueue.NewNamedRateLimitingQueue(ratelimiter, "volumes")
```

### 3.2.3. ListWatch

```go
// PVC
claimSource := &cache.ListWatch{
	ListFunc: func(options metav1.ListOptions) (runtime.Object, error) {
		return client.CoreV1().PersistentVolumeClaims(v1.NamespaceAll).List(options)
	},
	WatchFunc: func(options metav1.ListOptions) (watch.Interface, error) {
		return client.CoreV1().PersistentVolumeClaims(v1.NamespaceAll).Watch(options)
	},
}
// PV
volumeSource := &cache.ListWatch{
	ListFunc: func(options metav1.ListOptions) (runtime.Object, error) {
		return client.CoreV1().PersistentVolumes().List(options)
	},
	WatchFunc: func(options metav1.ListOptions) (watch.Interface, error) {
		return client.CoreV1().PersistentVolumes().Watch(options)
	},
}
// StorageClass
classSource = &cache.ListWatch{
	ListFunc: func(options metav1.ListOptions) (runtime.Object, error) {
		return client.StorageV1().StorageClasses().List(options)
	},
	WatchFunc: func(options metav1.ListOptions) (watch.Interface, error) {
		return client.StorageV1().StorageClasses().Watch(options)
	},
}
```

`list-watch`机制是k8s中用来监听对象变化的核心机制，`ListWatch`包含`ListFunc`和`WatchFunc`两个函数，且不能为空，以上代码分别构造了PV、PVC、StorageClass三个对象的`ListWatch`结构体。该机制的实现在`client-go`的`cache`包中，具体参考：https://godoc.org/k8s.io/client-go/tools/cache。

更多`ListWatch`代码如下:

> 具体参考：https://github.com/kubernetes-incubator/external-storage/blob/89b0aaf6413b249b37834b124fc314ef7b8ee949/vendor/k8s.io/client-go/tools/cache/listwatch.go#L34

```go
// ListerWatcher is any object that knows how to perform an initial list and start a watch on a resource.
type ListerWatcher interface {
	// List should return a list type object; the Items field will be extracted, and the
	// ResourceVersion field will be used to start the watch in the right place.
	List(options metav1.ListOptions) (runtime.Object, error)
	// Watch should begin a watch at the specified version.
	Watch(options metav1.ListOptions) (watch.Interface, error)
}

// ListFunc knows how to list resources
type ListFunc func(options metav1.ListOptions) (runtime.Object, error)

// WatchFunc knows how to watch resources
type WatchFunc func(options metav1.ListOptions) (watch.Interface, error)

// ListWatch knows how to list and watch a set of apiserver resources.  It satisfies the ListerWatcher interface.
// It is a convenience function for users of NewReflector, etc.
// ListFunc and WatchFunc must not be nil
type ListWatch struct {
	ListFunc  ListFunc
	WatchFunc WatchFunc
	// DisableChunking requests no chunking for this list watcher.
	DisableChunking bool
}
```

### 3.2.4. ResourceEventHandlerFuncs

```go
// PVC
claimHandler := cache.ResourceEventHandlerFuncs{
	AddFunc:    func(obj interface{}) { controller.enqueueWork(controller.claimQueue, obj) },
	UpdateFunc: func(oldObj, newObj interface{}) { controller.enqueueWork(controller.claimQueue, newObj) },
	DeleteFunc: func(obj interface{}) { controller.forgetWork(controller.claimQueue, obj) },
}
// PV
volumeHandler := cache.ResourceEventHandlerFuncs{
	AddFunc:    func(obj interface{}) { controller.enqueueWork(controller.volumeQueue, obj) },
	UpdateFunc: func(oldObj, newObj interface{}) { controller.enqueueWork(controller.volumeQueue, newObj) },
	DeleteFunc: func(obj interface{}) { controller.forgetWork(controller.volumeQueue, obj) },
}
// StorageClass
classHandler := cache.ResourceEventHandlerFuncs{
	// We don't need an actual event handler for StorageClasses,
	// but we must pass a non-nil one to cache.NewInformer()
	AddFunc:    nil,
	UpdateFunc: nil,
	DeleteFunc: nil,
}
```

`ResourceEventHandlerFuncs`是资源事件处理函数，主要用来对k8s资源对象`增删改`变化的事件进行消息通知，该函数实现了`ResourceEventHandler`的接口。具体代码逻辑在`client-go`的cache包中。

更多`ResourceEventHandlerFuncs`代码可参考：

```go
// ResourceEventHandler can handle notifications for events that happen to a
// resource. The events are informational only, so you can't return an
// error.
//  * OnAdd is called when an object is added.
//  * OnUpdate is called when an object is modified. Note that oldObj is the
//      last known state of the object-- it is possible that several changes
//      were combined together, so you can't use this to see every single
//      change. OnUpdate is also called when a re-list happens, and it will
//      get called even if nothing changed. This is useful for periodically
//      evaluating or syncing something.
//  * OnDelete will get the final state of the item if it is known, otherwise
//      it will get an object of type DeletedFinalStateUnknown. This can
//      happen if the watch is closed and misses the delete event and we don't
//      notice the deletion until the subsequent re-list.
type ResourceEventHandler interface {
	OnAdd(obj interface{})
	OnUpdate(oldObj, newObj interface{})
	OnDelete(obj interface{})
}

// ResourceEventHandlerFuncs is an adaptor to let you easily specify as many or
// as few of the notification functions as you want while still implementing
// ResourceEventHandler.
type ResourceEventHandlerFuncs struct {
	AddFunc    func(obj interface{})
	UpdateFunc func(oldObj, newObj interface{})
	DeleteFunc func(obj interface{})
}
```

### 3.2.5. 构造Store和Controller

**1、PVC**

```go
if controller.claimInformer != nil {
	controller.claimInformer.AddEventHandlerWithResyncPeriod(claimHandler, controller.resyncPeriod)
	controller.claims, controller.claimController =
		controller.claimInformer.GetStore(),
		controller.claimInformer.GetController()
} else {
	controller.claims, controller.claimController =
		cache.NewInformer(
			claimSource,
			&v1.PersistentVolumeClaim{},
			controller.resyncPeriod,
			claimHandler,
		)
}
```

**2、PV**

```go
if controller.volumeInformer != nil {
	controller.volumeInformer.AddEventHandlerWithResyncPeriod(volumeHandler, controller.resyncPeriod)
	controller.volumes, controller.volumeController =
		controller.volumeInformer.GetStore(),
		controller.volumeInformer.GetController()
} else {
	controller.volumes, controller.volumeController =
		cache.NewInformer(
			volumeSource,
			&v1.PersistentVolume{},
			controller.resyncPeriod,
			volumeHandler,
		)
}
```

**3、StorageClass**

```go
if controller.classInformer != nil {
	// no resource event handler needed for StorageClasses
	controller.classes, controller.classController =
		controller.classInformer.GetStore(),
		controller.classInformer.GetController()
} else {
	controller.classes, controller.classController = cache.NewInformer(
		classSource,
		versionedClassType,
		controller.resyncPeriod,
		classHandler,
	)
}
```

通过`cache.NewInformer`的方法构造，入参是`ListWatch`结构体和`ResourceEventHandlerFuncs`函数等，返回值是`Store`和`Controller`。

通过以上各个部分的构造，最后返回一个具体的`ProvisionController`对象。

## 3.3. [ProvisionController.Run](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L565)方法

`ProvisionController`的`Run`方法是以常驻进程的方式运行，函数内部再运行其他的controller。

### 3.3.1. prometheus数据收集

```go
// Run starts all of this controller's control loops
func (ctrl *ProvisionController) Run(stopCh <-chan struct{}) {

	run := func(stopCh <-chan struct{}) {
		...
		if ctrl.metricsPort > 0 {
			prometheus.MustRegister([]prometheus.Collector{
				metrics.PersistentVolumeClaimProvisionTotal,
				metrics.PersistentVolumeClaimProvisionFailedTotal,
				metrics.PersistentVolumeClaimProvisionDurationSeconds,
				metrics.PersistentVolumeDeleteTotal,
				metrics.PersistentVolumeDeleteFailedTotal,
				metrics.PersistentVolumeDeleteDurationSeconds,
			}...)
			http.Handle(ctrl.metricsPath, promhttp.Handler())
			address := net.JoinHostPort(ctrl.metricsAddress, strconv.FormatInt(int64(ctrl.metricsPort), 10))
			glog.Infof("Starting metrics server at %s\n", address)
			go wait.Forever(func() {
				err := http.ListenAndServe(address, nil)
				if err != nil {
					glog.Errorf("Failed to listen on %s: %v", address, err)
				}
			}, 5*time.Second)
		}
        ...
}        
```

### 3.3.2. Controller.Run

```go
// If a SharedInformer has been passed in, this controller should not
// call Run again
if ctrl.claimInformer == nil {
	go ctrl.claimController.Run(stopCh)
}
if ctrl.volumeInformer == nil {
	go ctrl.volumeController.Run(stopCh)
}
if ctrl.classInformer == nil {
	go ctrl.classController.Run(stopCh)
}
```

运行消息通知器Informer。

### 3.3.3. Worker

```go
for i := 0; i < ctrl.threadiness; i++ {
	go wait.Until(ctrl.runClaimWorker, time.Second, stopCh)
	go wait.Until(ctrl.runVolumeWorker, time.Second, stopCh)
}
```

`runClaimWorker`和`runVolumeWorker`分别为PVC和PV的worker，这两个的具体执行体分别是`processNextClaimWorkItem`和`processNextVolumeWorkItem`。

执行流程如下：

**PVC的函数调用流程**

```bash
runClaimWorker→processNextClaimWorkItem→syncClaimHandler→syncClaim→provisionClaimOperation
```

**PV的函数调用流程**

```bash
runVolumeWorker→processNextVolumeWorkItem→syncVolumeHandler→syncVolume→deleteVolumeOperation
```

可见最后执行的函数分别是`provisionClaimOperation`和`deleteVolumeOperation`。

## 3.4. Operation

### 3.4.1. [provisionClaimOperation](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L923)

1、`provisionClaimOperation`入参是PVC，通过PVC获得PV对象，并判断PV对象是否存在，如果存在则退出后续操作。

```go
// provisionClaimOperation attempts to provision a volume for the given claim.
// Returns error, which indicates whether provisioning should be retried
// (requeue the claim) or not
func (ctrl *ProvisionController) provisionClaimOperation(claim *v1.PersistentVolumeClaim) error {
	// Most code here is identical to that found in controller.go of kube's PV controller...
	claimClass := helper.GetPersistentVolumeClaimClass(claim)
	operation := fmt.Sprintf("provision %q class %q", claimToClaimKey(claim), claimClass)
	glog.Infof(logOperation(operation, "started"))

	//  A previous doProvisionClaim may just have finished while we were waiting for
	//  the locks. Check that PV (with deterministic name) hasn't been provisioned
	//  yet.
	pvName := ctrl.getProvisionedVolumeNameForClaim(claim)
	volume, err := ctrl.client.CoreV1().PersistentVolumes().Get(pvName, metav1.GetOptions{})
	if err == nil && volume != nil {
		// Volume has been already provisioned, nothing to do.
		glog.Infof(logOperation(operation, "persistentvolume %q already exists, skipping", pvName))
		return nil
	}
    ...
}    
```

2、获取StorageClass对象中的`Provisioner`和`ReclaimPolicy`参数，如果`provisionerName`和`StorageClass`对象中的`provisioner`字段不一致则报错并退出执行。

```go
provisioner, parameters, err := ctrl.getStorageClassFields(claimClass)
if err != nil {
	glog.Errorf(logOperation(operation, "error getting claim's StorageClass's fields: %v", err))
	return nil
}
if provisioner != ctrl.provisionerName {
	// class.Provisioner has either changed since shouldProvision() or
	// annDynamicallyProvisioned contains different provisioner than
	// class.Provisioner.
	glog.Errorf(logOperation(operation, "unknown provisioner %q requested in claim's StorageClass", provisioner))
	return nil
}
// Check if this provisioner can provision this claim.
if err = ctrl.canProvision(claim); err != nil {
	ctrl.eventRecorder.Event(claim, v1.EventTypeWarning, "ProvisioningFailed", err.Error())
	glog.Errorf(logOperation(operation, "failed to provision volume: %v", err))
	return nil
}

reclaimPolicy := v1.PersistentVolumeReclaimDelete
if ctrl.kubeVersion.AtLeast(utilversion.MustParseSemantic("v1.8.0")) {
	reclaimPolicy, err = ctrl.fetchReclaimPolicy(claimClass)
	if err != nil {
		return err
	}
}
```

3、执行具体的`provisioner.Provision`方法，构建PV对象，例如本文中的`provisioner`是`nfs-provisioner`。

```go
options := VolumeOptions{
	PersistentVolumeReclaimPolicy: reclaimPolicy,
	PVName:            pvName,
	PVC:               claim,
	MountOptions:      mountOptions,
	Parameters:        parameters,
	SelectedNode:      selectedNode,
	AllowedTopologies: allowedTopologies,
}

ctrl.eventRecorder.Event(claim, v1.EventTypeNormal, "Provisioning", fmt.Sprintf("External provisioner is provisioning volume for claim %q", claimToClaimKey(claim)))

volume, err = ctrl.provisioner.Provision(options)
if err != nil {
	if ierr, ok := err.(*IgnoredError); ok {
		// Provision ignored, do nothing and hope another provisioner will provision it.
		glog.Infof(logOperation(operation, "volume provision ignored: %v", ierr))
		return nil
	}
	err = fmt.Errorf("failed to provision volume with StorageClass %q: %v", claimClass, err)
	ctrl.eventRecorder.Event(claim, v1.EventTypeWarning, "ProvisioningFailed", err.Error())
	return err
}
```

4、创建k8s的PV对象。

```go
// Try to create the PV object several times
for i := 0; i < ctrl.createProvisionedPVRetryCount; i++ {
	glog.Infof(logOperation(operation, "trying to save persistentvvolume %q", volume.Name))
	if _, err = ctrl.client.CoreV1().PersistentVolumes().Create(volume); err == nil || apierrs.IsAlreadyExists(err) {
		// Save succeeded.
		if err != nil {
			glog.Infof(logOperation(operation, "persistentvolume %q already exists, reusing", volume.Name))
			err = nil
		} else {
			glog.Infof(logOperation(operation, "persistentvolume %q saved", volume.Name))
		}
		break
	}
	// Save failed, try again after a while.
	glog.Infof(logOperation(operation, "failed to save persistentvolume %q: %v", volume.Name, err))
	time.Sleep(ctrl.createProvisionedPVInterval)
}
```

5、创建PV失败，清理存储资源。

```go
if err != nil {
	// Save failed. Now we have a storage asset outside of Kubernetes,
	// but we don't have appropriate PV object for it.
	// Emit some event here and try to delete the storage asset several
	// times.
	...
	for i := 0; i < ctrl.createProvisionedPVRetryCount; i++ {
		if err = ctrl.provisioner.Delete(volume); err == nil {
			// Delete succeeded
			glog.Infof(logOperation(operation, "cleaning volume %q succeeded", volume.Name))
			break
		}
		// Delete failed, try again after a while.
		glog.Infof(logOperation(operation, "failed to clean volume %q: %v", volume.Name, err))
		time.Sleep(ctrl.createProvisionedPVInterval)
	}
	if err != nil {
		// Delete failed several times. There is an orphaned volume and there
		// is nothing we can do about it.
		strerr := fmt.Sprintf("Error cleaning provisioned volume for claim %s: %v. Please delete manually.", claimToClaimKey(claim), err)
		glog.Error(logOperation(operation, strerr))
		ctrl.eventRecorder.Event(claim, v1.EventTypeWarning, "ProvisioningCleanupFailed", strerr)
	}
}
```

如果创建成功，则打印成功的日志，并返回`nil`。

### 3.4.2. [deleteVolumeOperation](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L1096)

1、`deleteVolumeOperation`入参是PV，先获得PV对象，并判断是否需要删除。

```go
// deleteVolumeOperation attempts to delete the volume backing the given
// volume. Returns error, which indicates whether deletion should be retried
// (requeue the volume) or not
func (ctrl *ProvisionController) deleteVolumeOperation(volume *v1.PersistentVolume) error {
	...
	// This method may have been waiting for a volume lock for some time.
	// Our check does not have to be as sophisticated as PV controller's, we can
	// trust that the PV controller has set the PV to Released/Failed and it's
	// ours to delete
	newVolume, err := ctrl.client.CoreV1().PersistentVolumes().Get(volume.Name, metav1.GetOptions{})
	if err != nil {
		return nil
	}
	if !ctrl.shouldDelete(newVolume) {
		glog.Infof(logOperation(operation, "persistentvolume no longer needs deletion, skipping"))
		return nil
	}
    ...
}    
```

2、调用具体的`provisioner`的`Delete`方法，例如，如果是nfs-provisioner，则是调用nfs-provisioner的Delete方法。

```go
err = ctrl.provisioner.Delete(volume)
if err != nil {
	if ierr, ok := err.(*IgnoredError); ok {
		// Delete ignored, do nothing and hope another provisioner will delete it.
		glog.Infof(logOperation(operation, "volume deletion ignored: %v", ierr))
		return nil
	}
	// Delete failed, emit an event.
	glog.Errorf(logOperation(operation, "volume deletion failed: %v", err))
	ctrl.eventRecorder.Event(volume, v1.EventTypeWarning, "VolumeFailedDelete", err.Error())
	return err
}
```

3、删除k8s中的PV对象。

```go
// Delete the volume
if err = ctrl.client.CoreV1().PersistentVolumes().Delete(volume.Name, nil); err != nil {
	// Oops, could not delete the volume and therefore the controller will
	// try to delete the volume again on next update.
	glog.Infof(logOperation(operation, "failed to delete persistentvolume: %v", err))
	return err
}
```

# 4. 总结

1. `Provisioner`接口包含`Provision`和`Delete`两个方法，自定义的`provisioner`需要实现这两个方法，这两个方法只是处理了跟存储类型相关的事项，并没有针对`PV`、`PVC`对象的增删等操作。
2. `Provision`方法主要用来构造PV对象，不同类型的`Provisioner`的，一般是`PersistentVolumeSource`类型和参数不同，例如`nfs-provisioner`对应的`PersistentVolumeSource`为`NFS`，并且需要传入`NFS`相关的参数：`Server`，`Path`等。
3. `Delete`方法主要针对对应的存储类型，做数据存档（备份）或删除的处理。
4. `StorageClass`对象需要单独创建，用来指定具体的`provisioner`来执行相关逻辑。
5. `provisionClaimOperation`和`deleteVolumeOperation`具体执行了k8s中`PV`对象的创建和删除操作，同时调用了具体`provisioner`的`Provision`和`Delete`两个方法来对存储数据做处理。



参考文章

- https://github.com/kubernetes-incubator/external-storage/tree/master/docs/demo/hostpath-provisioner
- https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client
- https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go
- https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/volume.go

