> 本文主要分析`csi-provisioner`的源码，关于开发一个`Dynamic Provisioner`，具体可参考[nfs-client-provisioner的源码分析](https://www.huweihuang.com/kubernetes-notes/develop/nfs-client-provisioner.html)

# 1. Dynamic Provisioner

## 1.1. Provisioner Interface

开发`Dynamic Provisioner`需要实现[Provisioner](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/volume.go#L29)接口，该接口有两个方法，分别是：

- Provision：创建存储资源，并且返回一个PV对象。
- Delete：移除对应的存储资源，但并没有删除PV对象。

## 1.2. 开发provisioner的步骤

1. 写一个`provisioner`实现`Provisioner`接口（包含`Provision`和`Delete`的方法）。
2. 通过该`provisioner`构建`ProvisionController`。
3. 执行`ProvisionController`的`Run`方法。

# 2. CSI Provisioner

CSI Provisioner的源码可参考：https://github.com/kubernetes-csi/external-provisioner。

## 2.1. [Main 函数](https://github.com/kubernetes-csi/external-provisioner/blob/master/cmd/csi-provisioner/csi-provisioner.go)

### 2.1.1. 读取环境变量

源码如下：

```go
var (
	provisioner          = flag.String("provisioner", "", "Name of the provisioner. The provisioner will only provision volumes for claims that request a StorageClass with a provisioner field set equal to this name.")
	master               = flag.String("master", "", "Master URL to build a client config from. Either this or kubeconfig needs to be set if the provisioner is being run out of cluster.")
	kubeconfig           = flag.String("kubeconfig", "", "Absolute path to the kubeconfig file. Either this or master needs to be set if the provisioner is being run out of cluster.")
	csiEndpoint          = flag.String("csi-address", "/run/csi/socket", "The gRPC endpoint for Target CSI Volume")
	connectionTimeout    = flag.Duration("connection-timeout", 10*time.Second, "Timeout for waiting for CSI driver socket.")
	volumeNamePrefix     = flag.String("volume-name-prefix", "pvc", "Prefix to apply to the name of a created volume")
	volumeNameUUIDLength = flag.Int("volume-name-uuid-length", -1, "Truncates generated UUID of a created volume to this length. Defaults behavior is to NOT truncate.")
	showVersion          = flag.Bool("version", false, "Show version.")

	provisionController *controller.ProvisionController
	version             = "unknown"
)

func init() {
	var config *rest.Config
	var err error

	flag.Parse()
	flag.Set("logtostderr", "true")

	if *showVersion {
		fmt.Println(os.Args[0], version)
		os.Exit(0)
	}
	glog.Infof("Version: %s", version)
	...	
}	
```

通过`init函数`解析相关参数，其实`provisioner`指明为PVC提供PV的provisioner的名字，需要和`StorageClass`对象中的`provisioner`字段一致。

### 2.1.2. 获取clientset对象

源码如下：

```go
// get the KUBECONFIG from env if specified (useful for local/debug cluster)
kubeconfigEnv := os.Getenv("KUBECONFIG")
if kubeconfigEnv != "" {
	glog.Infof("Found KUBECONFIG environment variable set, using that..")
	kubeconfig = &kubeconfigEnv
}
if *master != "" || *kubeconfig != "" {
	glog.Infof("Either master or kubeconfig specified. building kube config from that..")
	config, err = clientcmd.BuildConfigFromFlags(*master, *kubeconfig)
} else {
	glog.Infof("Building kube configs for running in cluster...")
	config, err = rest.InClusterConfig()
}
if err != nil {
	glog.Fatalf("Failed to create config: %v", err)
}
clientset, err := kubernetes.NewForConfig(config)
if err != nil {
	glog.Fatalf("Failed to create client: %v", err)
}

// snapclientset.NewForConfig creates a new Clientset for VolumesnapshotV1alpha1Client
snapClient, err := snapclientset.NewForConfig(config)
if err != nil {
	glog.Fatalf("Failed to create snapshot client: %v", err)
}
csiAPIClient, err := csiclientset.NewForConfig(config)
if err != nil {
	glog.Fatalf("Failed to create CSI API client: %v", err)
}
```

通过读取对应的k8s的配置，创建`clientset`对象，用来执行k8s对应的API，其中主要包括对PV和PVC等对象的创建删除等操作。

### 2.1.3. k8s版本校验

```go
// The controller needs to know what the server version is because out-of-tree
// provisioners aren't officially supported until 1.5
serverVersion, err := clientset.Discovery().ServerVersion()
if err != nil {
	glog.Fatalf("Error getting server version: %v", err)
}
```

获取了k8s的版本信息，因为provisioners的功能在k8s 1.5及以上版本才支持。

### 2.1.4. 连接 csi socket

```go
// Generate a unique ID for this provisioner
timeStamp := time.Now().UnixNano() / int64(time.Millisecond)
identity := strconv.FormatInt(timeStamp, 10) + "-" + strconv.Itoa(rand.Intn(10000)) + "-" + *provisioner

// Provisioner will stay in Init until driver opens csi socket, once it's done
// controller will exit this loop and proceed normally.
socketDown := true
grpcClient := &grpc.ClientConn{}
for socketDown {
	grpcClient, err = ctrl.Connect(*csiEndpoint, *connectionTimeout)
	if err == nil {
		socketDown = false
		continue
	}
	time.Sleep(10 * time.Second)
}
```

在`Provisioner`会停留在初始化状态，直到`csi socket`连接成功才正常运行。如果连接失败，会暂停`10秒`后重试，其中涉及以下2个参数：

- csiEndpoint：CSI Volume的gRPC地址，默认通过为`/run/csi/socket`。
- connectionTimeout：连接CSI driver socket的超时时间，默认为10秒。

### 2.1.5. 构造csi-Provisioner对象

```go
// Create the provisioner: it implements the Provisioner interface expected by
// the controller
csiProvisioner := ctrl.NewCSIProvisioner(clientset, csiAPIClient, *csiEndpoint, *connectionTimeout, identity, *volumeNamePrefix, *volumeNameUUIDLength, grpcClient, snapClient)
provisionController = controller.NewProvisionController(
	clientset,
	*provisioner,
	csiProvisioner,
	serverVersion.GitVersion,
)
```

通过参数`clientset`,` csiAPIClient`, `csiEndpoint`, `connectionTimeout`, `identity`, `volumeNamePrefix`, `volumeNameUUIDLength`,` grpcClient`, `snapClient`构造csi-Provisioner对象。

通过`csiProvisioner`构造`ProvisionController`对象。

### 2.1.6. 运行ProvisionController

```go
func main() {
	provisionController.Run(wait.NeverStop)
}
```

`ProvisionController`实现了具体的PV和PVC的相关逻辑，`Run`方法以常驻进程的方式运行。

## 2.2. [Provision](https://github.com/kubernetes-csi/external-provisioner/blob/master/pkg/controller/controller.go#L336)和[Delete](https://github.com/kubernetes-csi/external-provisioner/blob/master/pkg/controller/controller.go#L606)方法

### 2.2.1. Provision方法

> `csiProvisioner`的`Provision`方法具体源码参考：https://github.com/kubernetes-csi/external-provisioner/blob/master/pkg/controller/controller.go#L336

`Provision`方法用来创建存储资源，并且返回一个`PV`对象。其中入参是`VolumeOptions`，用来指定`PV`对象的相关属性。

**1、构造PV相关属性**

```go
pvName, err := makeVolumeName(p.volumeNamePrefix, fmt.Sprintf("%s", options.PVC.ObjectMeta.UID), p.volumeNameUUIDLength)
if err != nil {
	return nil, err
}
```

**2、构造CSIPersistentVolumeSource相关属性**

```go
driverState, err := checkDriverState(p.grpcClient, p.timeout, needSnapshotSupport)
if err != nil {
	return nil, err
}

...
// Resolve controller publish, node stage, node publish secret references
controllerPublishSecretRef, err := getSecretReference(controllerPublishSecretNameKey, controllerPublishSecretNamespaceKey, options.Parameters, pvName, options.PVC)
if err != nil {
	return nil, err
}
nodeStageSecretRef, err := getSecretReference(nodeStageSecretNameKey, nodeStageSecretNamespaceKey, options.Parameters, pvName, options.PVC)
if err != nil {
	return nil, err
}
nodePublishSecretRef, err := getSecretReference(nodePublishSecretNameKey, nodePublishSecretNamespaceKey, options.Parameters, pvName, options.PVC)
if err != nil {
	return nil, err
}

...
volumeAttributes := map[string]string{provisionerIDKey: p.identity}
for k, v := range rep.Volume.Attributes {
	volumeAttributes[k] = v
}

...
fsType := ""
for k, v := range options.Parameters {
	switch strings.ToLower(k) {
	case "fstype":
		fsType = v
	}
}
if len(fsType) == 0 {
	fsType = defaultFSType
}
```

**3、创建CSI CreateVolumeRequest** 

```go
// Create a CSI CreateVolumeRequest and Response
req := csi.CreateVolumeRequest{
	Name:               pvName,
	Parameters:         options.Parameters,
	VolumeCapabilities: volumeCaps,
	CapacityRange: &csi.CapacityRange{
		RequiredBytes: int64(volSizeBytes),
	},
}
...
glog.V(5).Infof("CreateVolumeRequest %+v", req)

rep := &csi.CreateVolumeResponse{}
...
opts := wait.Backoff{Duration: backoffDuration, Factor: backoffFactor, Steps: backoffSteps}
err = wait.ExponentialBackoff(opts, func() (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), p.timeout)
	defer cancel()
	rep, err = p.csiClient.CreateVolume(ctx, &req)
	if err == nil {
		// CreateVolume has finished successfully
		return true, nil
	}

	if status, ok := status.FromError(err); ok {
		if status.Code() == codes.DeadlineExceeded {
			// CreateVolume timed out, give it another chance to complete
			glog.Warningf("CreateVolume timeout: %s has expired, operation will be retried", p.timeout.String())
			return false, nil
		}
	}
	// CreateVolume failed , no reason to retry, bailing from ExponentialBackoff
	return false, err
})

if err != nil {
	return nil, err
}

if rep.Volume != nil {
	glog.V(3).Infof("create volume rep: %+v", *rep.Volume)
}

respCap := rep.GetVolume().GetCapacityBytes()
if respCap < volSizeBytes {
	capErr := fmt.Errorf("created volume capacity %v less than requested capacity %v", respCap, volSizeBytes)
	delReq := &csi.DeleteVolumeRequest{
		VolumeId: rep.GetVolume().GetId(),
	}
	delReq.ControllerDeleteSecrets = provisionerCredentials
	ctx, cancel := context.WithTimeout(context.Background(), p.timeout)
	defer cancel()
	_, err := p.csiClient.DeleteVolume(ctx, delReq)
	if err != nil {
		capErr = fmt.Errorf("%v. Cleanup of volume %s failed, volume is orphaned: %v", capErr, pvName, err)
	}
	return nil, capErr
}
```

`Provison`方法核心功能是调用`p.csiClient.CreateVolume(ctx, &req)`。

**4、构造PV对象**

```go
pv := &v1.PersistentVolume{
	ObjectMeta: metav1.ObjectMeta{
		Name: pvName,
	},
	Spec: v1.PersistentVolumeSpec{
		PersistentVolumeReclaimPolicy: options.PersistentVolumeReclaimPolicy,
		AccessModes:                   options.PVC.Spec.AccessModes,
		Capacity: v1.ResourceList{
			v1.ResourceName(v1.ResourceStorage): bytesToGiQuantity(respCap),
		},
		// TODO wait for CSI VolumeSource API
		PersistentVolumeSource: v1.PersistentVolumeSource{
			CSI: &v1.CSIPersistentVolumeSource{
				Driver:                     driverState.driverName,
				VolumeHandle:               p.volumeIdToHandle(rep.Volume.Id),
				FSType:                     fsType,
				VolumeAttributes:           volumeAttributes,
				ControllerPublishSecretRef: controllerPublishSecretRef,
				NodeStageSecretRef:         nodeStageSecretRef,
				NodePublishSecretRef:       nodePublishSecretRef,
			},
		},
	},
}

if driverState.capabilities.Has(PluginCapability_ACCESSIBILITY_CONSTRAINTS) {
	pv.Spec.NodeAffinity = GenerateVolumeNodeAffinity(rep.Volume.AccessibleTopology)
}

glog.Infof("successfully created PV %+v", pv.Spec.PersistentVolumeSource)

return pv, nil
```

`Provision`方法只是通过`VolumeOptions`参数来构建`PV`对象，并没有执行具体`PV`的创建或删除的操作。

不同类型的`Provisioner`的，一般是`PersistentVolumeSource`类型和参数不同，例如`csi-provisioner`对应的`PersistentVolumeSource`为`CSI`，并且需要传入`CSI`相关的参数：

- `Driver`
- `VolumeHandle`
- `FSType`
- `VolumeAttributes`
- `ControllerPublishSecretRef`
- `NodeStageSecretRef`
- `NodePublishSecretRef`

### 2.2.2. Delete方法

> `csiProvisioner`的`delete`方法具体源码参考：https://github.com/kubernetes-csi/external-provisioner/blob/master/pkg/controller/controller.go#L606

```go
func (p *csiProvisioner) Delete(volume *v1.PersistentVolume) error {
	if volume == nil || volume.Spec.CSI == nil {
		return fmt.Errorf("invalid CSI PV")
	}
	volumeId := p.volumeHandleToId(volume.Spec.CSI.VolumeHandle)

	_, err := checkDriverState(p.grpcClient, p.timeout, false)
	if err != nil {
		return err
	}

	req := csi.DeleteVolumeRequest{
		VolumeId: volumeId,
	}
	// get secrets if StorageClass specifies it
	storageClassName := volume.Spec.StorageClassName
	if len(storageClassName) != 0 {
		if storageClass, err := p.client.StorageV1().StorageClasses().Get(storageClassName, metav1.GetOptions{}); err == nil {
			// Resolve provision secret credentials.
			// No PVC is provided when resolving provision/delete secret names, since the PVC may or may not exist at delete time.
			provisionerSecretRef, err := getSecretReference(provisionerSecretNameKey, provisionerSecretNamespaceKey, storageClass.Parameters, volume.Name, nil)
			if err != nil {
				return err
			}
			credentials, err := getCredentials(p.client, provisionerSecretRef)
			if err != nil {
				return err
			}
			req.ControllerDeleteSecrets = credentials
		}

	}
	ctx, cancel := context.WithTimeout(context.Background(), p.timeout)
	defer cancel()

	_, err = p.csiClient.DeleteVolume(ctx, &req)

	return err
}
```

`Delete`方法主要是调用了`p.csiClient.DeleteVolume(ctx, &req)`方法。

## 2.3. 总结

`csi provisioner`实现了`Provisioner`接口，其中包含`Provison`和`Delete`两个方法:

- `Provision`：调用`csiClient.CreateVolume`方法，同时构造并返回PV对象。
- `Delete`：调用`csiClient.DeleteVolume`方法。

`csi provisioner`的核心方法都调用了`csi-client`相关方法。

# 3. csi-client

> `csi client`的相关代码参考：https://github.com/container-storage-interface/spec/blob/master/lib/go/csi/v0/csi.pb.go

## 3.1. 构造csi-client

### 3.1.1. 构造grpcClient

```go
// Provisioner will stay in Init until driver opens csi socket, once it's done
// controller will exit this loop and proceed normally.
socketDown := true
grpcClient := &grpc.ClientConn{}
for socketDown {
	grpcClient, err = ctrl.Connect(*csiEndpoint, *connectionTimeout)
	if err == nil {
		socketDown = false
		continue
	}
	time.Sleep(10 * time.Second)
}
```

通过连接`csi socket`，连接成功才构造可用的`grpcClient`。

### 3.1.2. 构造csi-client

通过`grpcClient`构造`csi-client`。

```go
// Create the provisioner: it implements the Provisioner interface expected by
// the controller
csiProvisioner := ctrl.NewCSIProvisioner(clientset, csiAPIClient, *csiEndpoint, *connectionTimeout, identity, *volumeNamePrefix, *volumeNameUUIDLength, grpcClient, snapClient)
```

**NewCSIProvisioner**

```go
// NewCSIProvisioner creates new CSI provisioner
func NewCSIProvisioner(client kubernetes.Interface,
	csiAPIClient csiclientset.Interface,
	csiEndpoint string,
	connectionTimeout time.Duration,
	identity string,
	volumeNamePrefix string,
	volumeNameUUIDLength int,
	grpcClient *grpc.ClientConn,
	snapshotClient snapclientset.Interface) controller.Provisioner {

	csiClient := csi.NewControllerClient(grpcClient)
	provisioner := &csiProvisioner{
		client:               client,
		grpcClient:           grpcClient,
		csiClient:            csiClient,
		csiAPIClient:         csiAPIClient,
		snapshotClient:       snapshotClient,
		timeout:              connectionTimeout,
		identity:             identity,
		volumeNamePrefix:     volumeNamePrefix,
		volumeNameUUIDLength: volumeNameUUIDLength,
	}
	return provisioner
}
```

**[NewControllerClient](https://github.com/container-storage-interface/spec/blob/master/lib/go/csi/v0/csi.pb.go#L4353)**

```go
csiClient := csi.NewControllerClient(grpcClient)
...
type controllerClient struct {
	cc *grpc.ClientConn
}

func NewControllerClient(cc *grpc.ClientConn) ControllerClient {
	return &controllerClient{cc}
}
```

## 3.2. csiClient.CreateVolume

`csi provisoner`中调用`csiClient.CreateVolume`代码如下：

```go
opts := wait.Backoff{Duration: backoffDuration, Factor: backoffFactor, Steps: backoffSteps}
err = wait.ExponentialBackoff(opts, func() (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), p.timeout)
	defer cancel()
	rep, err = p.csiClient.CreateVolume(ctx, &req)
	if err == nil {
		// CreateVolume has finished successfully
		return true, nil
	}

	if status, ok := status.FromError(err); ok {
		if status.Code() == codes.DeadlineExceeded {
			// CreateVolume timed out, give it another chance to complete
			glog.Warningf("CreateVolume timeout: %s has expired, operation will be retried", p.timeout.String())
			return false, nil
		}
	}
	// CreateVolume failed , no reason to retry, bailing from ExponentialBackoff
	return false, err
})
```

**CreateVolumeRequest的构造：**

```go
// Create a CSI CreateVolumeRequest and Response
req := csi.CreateVolumeRequest{
	Name:               pvName,
	Parameters:         options.Parameters,
	VolumeCapabilities: volumeCaps,
	CapacityRange: &csi.CapacityRange{
		RequiredBytes: int64(volSizeBytes),
	},
}
...
req.VolumeContentSource = volumeContentSource
...
req.AccessibilityRequirements = requirements
...
req.ControllerCreateSecrets = provisionerCredentials
```

**具体的`Create`实现方法如下：**

> 其中`csiClient`是个接口类型

具体代码参考[controllerClient.CreateVolume](https://github.com/container-storage-interface/spec/blob/master/lib/go/csi/v0/csi.pb.go#L4357)

```go
func (c *controllerClient) CreateVolume(ctx context.Context, in *CreateVolumeRequest, opts ...grpc.CallOption) (*CreateVolumeResponse, error) {
	out := new(CreateVolumeResponse)
	err := grpc.Invoke(ctx, "/csi.v0.Controller/CreateVolume", in, out, c.cc, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}
```

## 3.3. csiClient.DeleteVolume

`csi provisoner`中调用`csiClient.DeleteVolume`代码如下：

```go
func (p *csiProvisioner) Delete(volume *v1.PersistentVolume) error {
	...
	req := csi.DeleteVolumeRequest{
		VolumeId: volumeId,
	}
	// get secrets if StorageClass specifies it
	...
    
	ctx, cancel := context.WithTimeout(context.Background(), p.timeout)
	defer cancel()

	_, err = p.csiClient.DeleteVolume(ctx, &req)

	return err
}
```

**DeleteVolumeRequest的构造：**

```go
req := csi.DeleteVolumeRequest{
	VolumeId: volumeId,
}
...
req.ControllerDeleteSecrets = credentials
```

将构造的`DeleteVolumeRequest`传给`DeleteVolume`方法。

**具体的`Delete`实现方法如下：**

具体代码参考：[controllerClient.DeleteVolume](https://github.com/container-storage-interface/spec/blob/master/lib/go/csi/v0/csi.pb.go#L4366)

```go
func (c *controllerClient) DeleteVolume(ctx context.Context, in *DeleteVolumeRequest, opts ...grpc.CallOption) (*DeleteVolumeResponse, error) {
	out := new(DeleteVolumeResponse)
	err := grpc.Invoke(ctx, "/csi.v0.Controller/DeleteVolume", in, out, c.cc, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}
```

# 4. [ProvisionController.Run](https://github.com/kubernetes-incubator/external-storage/blob/master/lib/controller/controller.go#L565)

自定义的`provisioner`实现了`Provisoner接口`的`Provision`和`Delete`方法，这两个方法主要对后端存储做创建和删除操作，并没有对PV对象进行创建和删除操作。

PV对象的相关操作具体由`ProvisionController`中的`provisionClaimOperation`和`deleteVolumeOperation`具体执行，同时调用了具体`provisioner`的`Provision`和`Delete`两个方法来对存储数据做处理。

```go
func main() {
	provisionController.Run(wait.NeverStop)
}
```

这块代码逻辑可参考：[nfs-client-provisioner 源码分析](https://www.huweihuang.com/kubernetes-notes/develop/nfs-client-provisioner.html#3-provisioncontroller)





参考文章：

- https://github.com/kubernetes-csi/external-provisioner
- https://github.com/container-storage-interface/spec
- https://github.com/kubernetes/community/blob/master/contributors/design-proposals/storage/container-storage-interface.md
- https://github.com/container-storage-interface/spec/blob/master/spec.md
