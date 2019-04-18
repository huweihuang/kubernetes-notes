# kube-controller-manager源码分析（三）之 Informer机制

> 以下代码分析基于 `kubernetes v1.12.0` 版本。

本文主要分析k8s中各个核心组件经常使用到的`Informer`机制(即List-Watch)。该部分的代码主要位于`client-go`这个第三方包中。

此部分的逻辑主要位于`/vendor/k8s.io/client-go/tools/cache`包中，代码目录结构如下：

```bash
cache
├── controller.go  # 包含：Config、Run、processLoop、NewInformer、NewIndexerInformer
├── delta_fifo.go  # 包含：NewDeltaFIFO、DeltaFIFO、AddIfNotPresent
├── expiration_cache.go
├── expiration_cache_fakes.go
├── fake_custom_store.go
├── fifo.go   # 包含：Queue、FIFO、NewFIFO
├── heap.go
├── index.go    # 包含：Indexer、MetaNamespaceIndexFunc
├── listers.go
├── listwatch.go   # 包含：ListerWatcher、ListWatch、List、Watch
├── mutation_cache.go
├── mutation_detector.go
├── reflector.go   # 包含：Reflector、NewReflector、Run、ListAndWatch
├── reflector_metrics.go
├── shared_informer.go  # 包含：NewSharedInformer、WaitForCacheSync、Run、HasSynced
├── store.go  # 包含：Store、MetaNamespaceKeyFunc、SplitMetaNamespaceKey
├── testing
│   ├── fake_controller_source.go
├── thread_safe_store.go  # 包含：ThreadSafeStore、threadSafeMap
├── undelta_store.go
```

# 0. 原理示意图

[示意图1](https://www.kubernetes.org.cn/1283.html)：

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1555472372/article/code-analysis/informer/client-go.png" width="100%">

[示意图2](https://github.com/kubernetes/sample-controller/blob/master/docs/controller-client-go.md)：

<img src="https://res.cloudinary.com/dqxtn0ick/image/upload/v1555479782/article/code-analysis/informer/client-go-controller-interaction.jpg" width="100%">

## 0.1. client-go组件

- `Reflector`：reflector用来watch特定的k8s API资源。具体的实现是通过`ListAndWatch`的方法，watch可以是k8s内建的资源或者是自定义的资源。当reflector通过watch API接收到有关新资源实例存在的通知时，它使用相应的列表API获取新创建的对象，并将其放入watchHandler函数内的Delta Fifo队列中。

- `Informer`：informer从Delta Fifo队列中弹出对象。执行此操作的功能是processLoop。base controller的作用是保存对象以供以后检索，并调用我们的控制器将对象传递给它。

- `Indexer`：索引器提供对象的索引功能。典型的索引用例是基于对象标签创建索引。 Indexer可以根据多个索引函数维护索引。Indexer使用线程安全的数据存储来存储对象及其键。 在Store中定义了一个名为`MetaNamespaceKeyFunc`的默认函数，该函数生成对象的键作为该对象的`<namespace> / <name>`组合。

## 0.2. 自定义controller组件

- `Informer reference`：指的是Informer实例的引用，定义如何使用自定义资源对象。 自定义控制器代码需要创建对应的Informer。

- `Indexer reference`: 自定义控制器对Indexer实例的引用。自定义控制器需要创建对应的Indexser。

> client-go中提供`NewIndexerInformer`函数可以创建Informer 和 Indexer。

- `Resource Event Handlers`：资源事件回调函数，当它想要将对象传递给控制器时，它将被调用。 编写这些函数的典型模式是获取调度对象的key，并将该key排入工作队列以进行进一步处理。

- `Work queue`：任务队列。 编写资源事件处理程序函数以提取传递的对象的key并将其添加到任务队列。

- `Process Item`：处理任务队列中对象的函数， 这些函数通常使用Indexer引用或Listing包装器来重试与该key对应的对象。

# 1. sharedInformerFactory.Start

在controller-manager的Run函数部分调用了InformerFactory.Start的方法。

> 此部分代码位于/cmd/kube-controller-manager/app/controllermanager.go

```go
// Run runs the KubeControllerManagerOptions.  This should never exit.
func Run(c *config.CompletedConfig, stopCh <-chan struct{}) error {
    ...
		controllerContext.InformerFactory.Start(controllerContext.Stop)
		close(controllerContext.InformersStarted)
    ...
}
```

InformerFactory是一个`SharedInformerFactory`的接口，接口定义如下：

> 此部分代码位于vendor/k8s.io/client-go/informers/internalinterfaces/factory_interfaces.go

```go
// SharedInformerFactory a small interface to allow for adding an informer without an import cycle
type SharedInformerFactory interface {
	Start(stopCh <-chan struct{})
	InformerFor(obj runtime.Object, newFunc NewInformerFunc) cache.SharedIndexInformer
}

```

Start方法初始化各种类型的informer，并且每个类型起了个informer.Run的goroutine。

> 此部分代码位于vendor/k8s.io/client-go/informers/factory.go

```go
// Start initializes all requested informers.
func (f *sharedInformerFactory) Start(stopCh <-chan struct{}) {
	f.lock.Lock()
	defer f.lock.Unlock()

	for informerType, informer := range f.informers {
		if !f.startedInformers[informerType] {
			go informer.Run(stopCh)
			f.startedInformers[informerType] = true
		}
	}
}
```

# 2. sharedIndexInformer.Run

> 此部分的代码位于/vendor/k8s.io/client-go/tools/cache/shared_informer.go

```go
func (s *sharedIndexInformer) Run(stopCh <-chan struct{}) {
	defer utilruntime.HandleCrash()

	fifo := NewDeltaFIFO(MetaNamespaceKeyFunc, nil, s.indexer)

	cfg := &Config{
		Queue:            fifo,
		ListerWatcher:    s.listerWatcher,
		ObjectType:       s.objectType,
		FullResyncPeriod: s.resyncCheckPeriod,
		RetryOnError:     false,
		ShouldResync:     s.processor.shouldResync,

		Process: s.HandleDeltas,
	}

	func() {
		s.startedLock.Lock()
		defer s.startedLock.Unlock()

		s.controller = New(cfg)
		s.controller.(*controller).clock = s.clock
		s.started = true
	}()

	// Separate stop channel because Processor should be stopped strictly after controller
	processorStopCh := make(chan struct{})
	var wg wait.Group
	defer wg.Wait()              // Wait for Processor to stop
	defer close(processorStopCh) // Tell Processor to stop
	wg.StartWithChannel(processorStopCh, s.cacheMutationDetector.Run)
	wg.StartWithChannel(processorStopCh, s.processor.run)

	defer func() {
		s.startedLock.Lock()
		defer s.startedLock.Unlock()
		s.stopped = true // Don't want any new listeners
	}()
	s.controller.Run(stopCh)
}
```

## 2.1. NewDeltaFIFO

DeltaFIFO是一个对象变化的存储队列，依据先进先出的原则，process的函数接收该队列的Pop方法的输出对象来处理相关功能。

```go
fifo := NewDeltaFIFO(MetaNamespaceKeyFunc, nil, s.indexer)
```

## 2.2. Config

构造controller的配置文件，构造process，即HandleDeltas，该函数为后面使用到的process函数。

```go
cfg := &Config{
	Queue:            fifo,
	ListerWatcher:    s.listerWatcher,
	ObjectType:       s.objectType,
	FullResyncPeriod: s.resyncCheckPeriod,
	RetryOnError:     false,
	ShouldResync:     s.processor.shouldResync,

	Process: s.HandleDeltas,
}
```

## 2.3. controller

调用New(cfg)，构建sharedIndexInformer的controller。

```go
func() {
	s.startedLock.Lock()
	defer s.startedLock.Unlock()

	s.controller = New(cfg)
	s.controller.(*controller).clock = s.clock
	s.started = true
}()
```

## 2.4. cacheMutationDetector.Run

调用s.cacheMutationDetector.Run，检查缓存对象是否变化。

```go
wg.StartWithChannel(processorStopCh, s.cacheMutationDetector.Run)
```

**defaultCacheMutationDetector.Run**

```go
func (d *defaultCacheMutationDetector) Run(stopCh <-chan struct{}) {
	// we DON'T want protection from panics.  If we're running this code, we want to die
	for {
		d.CompareObjects()

		select {
		case <-stopCh:
			return
		case <-time.After(d.period):
		}
	}
}
```

**CompareObjects**

```go
func (d *defaultCacheMutationDetector) CompareObjects() {
	d.lock.Lock()
	defer d.lock.Unlock()

	altered := false
	for i, obj := range d.cachedObjs {
		if !reflect.DeepEqual(obj.cached, obj.copied) {
			fmt.Printf("CACHE %s[%d] ALTERED!\n%v\n", d.name, i, diff.ObjectDiff(obj.cached, obj.copied))
			altered = true
		}
	}

	if altered {
		msg := fmt.Sprintf("cache %s modified", d.name)
		if d.failureFunc != nil {
			d.failureFunc(msg)
			return
		}
		panic(msg)
	}
}
```

## 2.5. processor.run

调用s.processor.run，将调用sharedProcessor.run，会调用Listener.run和Listener.pop,执行处理queue的函数。

```go
wg.StartWithChannel(processorStopCh, s.processor.run)
```

**sharedProcessor.Run**

```go
func (p *sharedProcessor) run(stopCh <-chan struct{}) {
	func() {
		p.listenersLock.RLock()
		defer p.listenersLock.RUnlock()
		for _, listener := range p.listeners {
			p.wg.Start(listener.run)
			p.wg.Start(listener.pop)
		}
	}()
	<-stopCh
	p.listenersLock.RLock()
	defer p.listenersLock.RUnlock()
	for _, listener := range p.listeners {
		close(listener.addCh) // Tell .pop() to stop. .pop() will tell .run() to stop
	}
	p.wg.Wait() // Wait for all .pop() and .run() to stop
}
```

该部分逻辑待后面分析。

## 2.6. controller.Run

调用s.controller.Run，构建Reflector，进行对etcd的缓存

```go
defer func() {
	s.startedLock.Lock()
	defer s.startedLock.Unlock()
	s.stopped = true // Don't want any new listeners
}()
s.controller.Run(stopCh)
```

controller.Run

> 此部分代码位于/vendor/k8s.io/client-go/tools/cache/controller.go

```go
// Run begins processing items, and will continue until a value is sent down stopCh.
// It's an error to call Run more than once.
// Run blocks; call via go.
func (c *controller) Run(stopCh <-chan struct{}) {
	defer utilruntime.HandleCrash()
	go func() {
		<-stopCh
		c.config.Queue.Close()
	}()
	r := NewReflector(
		c.config.ListerWatcher,
		c.config.ObjectType,
		c.config.Queue,
		c.config.FullResyncPeriod,
	)
	r.ShouldResync = c.config.ShouldResync
	r.clock = c.clock

	c.reflectorMutex.Lock()
	c.reflector = r
	c.reflectorMutex.Unlock()

	var wg wait.Group
	defer wg.Wait()

	wg.StartWithChannel(stopCh, r.Run)

	wait.Until(c.processLoop, time.Second, stopCh)
}
```

核心代码：

```go
// 构建Reflector
r := NewReflector(
	c.config.ListerWatcher,
	c.config.ObjectType,
	c.config.Queue,
	c.config.FullResyncPeriod,
)
// 运行Reflector
wg.StartWithChannel(stopCh, r.Run)
// 执行processLoop
wait.Until(c.processLoop, time.Second, stopCh)
```

# 3. Reflector

## 3.1. Reflector

`Reflector`的主要作用是watch指定的k8s资源，并将变化同步到本地是`store`中。`Reflector`只会放置指定的`expectedType`类型的资源到`store`中，除非`expectedType`为nil。如果`resyncPeriod`不为零，那么`Reflector`为以`resyncPeriod`为周期定期执行list的操作，这样就可以使用`Reflector`来定期处理所有的对象，也可以逐步处理变化的对象。

常用属性说明：

- expectedType：期望放入缓存store的资源类型。
- store：watch的资源对应的本地缓存。
- listerWatcher：list和watch的接口。
- period：watch的周期，默认为1秒。
- resyncPeriod：resync的周期，当非零的时候，会按该周期执行list。
- lastSyncResourceVersion：最新一次看到的资源的版本号，主要在watch时候使用。

```go
// Reflector watches a specified resource and causes all changes to be reflected in the given store.
type Reflector struct {
	// name identifies this reflector. By default it will be a file:line if possible.
	name string
	// metrics tracks basic metric information about the reflector
	metrics *reflectorMetrics

	// The type of object we expect to place in the store.
	expectedType reflect.Type
	// The destination to sync up with the watch source
	store Store
	// listerWatcher is used to perform lists and watches.
	listerWatcher ListerWatcher
	// period controls timing between one watch ending and
	// the beginning of the next one.
	period       time.Duration
	resyncPeriod time.Duration
	ShouldResync func() bool
	// clock allows tests to manipulate time
	clock clock.Clock
	// lastSyncResourceVersion is the resource version token last
	// observed when doing a sync with the underlying store
	// it is thread safe, but not synchronized with the underlying store
	lastSyncResourceVersion string
	// lastSyncResourceVersionMutex guards read/write access to lastSyncResourceVersion
	lastSyncResourceVersionMutex sync.RWMutex
}
```

## 3.2. NewReflector

NewReflector主要用来构建Reflector的结构体。

> 此部分的代码位于/vendor/k8s.io/client-go/tools/cache/reflector.go

```go
// NewReflector creates a new Reflector object which will keep the given store up to
// date with the server's contents for the given resource. Reflector promises to
// only put things in the store that have the type of expectedType, unless expectedType
// is nil. If resyncPeriod is non-zero, then lists will be executed after every
// resyncPeriod, so that you can use reflectors to periodically process everything as
// well as incrementally processing the things that change.
func NewReflector(lw ListerWatcher, expectedType interface{}, store Store, resyncPeriod time.Duration) *Reflector {
	return NewNamedReflector(getDefaultReflectorName(internalPackages...), lw, expectedType, store, resyncPeriod)
}

// reflectorDisambiguator is used to disambiguate started reflectors.
// initialized to an unstable value to ensure meaning isn't attributed to the suffix.
var reflectorDisambiguator = int64(time.Now().UnixNano() % 12345)

// NewNamedReflector same as NewReflector, but with a specified name for logging
func NewNamedReflector(name string, lw ListerWatcher, expectedType interface{}, store Store, resyncPeriod time.Duration) *Reflector {
	reflectorSuffix := atomic.AddInt64(&reflectorDisambiguator, 1)
	r := &Reflector{
		name: name,
		// we need this to be unique per process (some names are still the same)but obvious who it belongs to
		metrics:       newReflectorMetrics(makeValidPromethusMetricLabel(fmt.Sprintf("reflector_"+name+"_%d", reflectorSuffix))),
		listerWatcher: lw,
		store:         store,
		expectedType:  reflect.TypeOf(expectedType),
		period:        time.Second,
		resyncPeriod:  resyncPeriod,
		clock:         &clock.RealClock{},
	}
	return r
}
```

## 3.3. Reflector.Run

Reflector.Run主要执行了`ListAndWatch`的方法。

```go
// Run starts a watch and handles watch events. Will restart the watch if it is closed.
// Run will exit when stopCh is closed.
func (r *Reflector) Run(stopCh <-chan struct{}) {
	glog.V(3).Infof("Starting reflector %v (%s) from %s", r.expectedType, r.resyncPeriod, r.name)
	wait.Until(func() {
		if err := r.ListAndWatch(stopCh); err != nil {
			utilruntime.HandleError(err)
		}
	}, r.period, stopCh)
}
```

## 3.4. ListAndWatch

ListAndWatch第一次会列出所有的对象，并获取资源对象的版本号，然后watch资源对象的版本号来查看是否有被变更。首先会将资源版本号设置为0，`list()`可能会导致本地的缓存相对于etcd里面的内容存在延迟，`Reflector`会通过`watch`的方法将延迟的部分补充上，使得本地的缓存数据与etcd的数据保持一致。

### 3.4.1. List

```go
// ListAndWatch first lists all items and get the resource version at the moment of call,
// and then use the resource version to watch.
// It returns error if ListAndWatch didn't even try to initialize watch.
func (r *Reflector) ListAndWatch(stopCh <-chan struct{}) error {
	glog.V(3).Infof("Listing and watching %v from %s", r.expectedType, r.name)
	var resourceVersion string

	// Explicitly set "0" as resource version - it's fine for the List()
	// to be served from cache and potentially be delayed relative to
	// etcd contents. Reflector framework will catch up via Watch() eventually.
	options := metav1.ListOptions{ResourceVersion: "0"}
	r.metrics.numberOfLists.Inc()
	start := r.clock.Now()
	list, err := r.listerWatcher.List(options)
	if err != nil {
		return fmt.Errorf("%s: Failed to list %v: %v", r.name, r.expectedType, err)
	}
	r.metrics.listDuration.Observe(time.Since(start).Seconds())
	listMetaInterface, err := meta.ListAccessor(list)
	if err != nil {
		return fmt.Errorf("%s: Unable to understand list result %#v: %v", r.name, list, err)
	}
	resourceVersion = listMetaInterface.GetResourceVersion()
	items, err := meta.ExtractList(list)
	if err != nil {
		return fmt.Errorf("%s: Unable to understand list result %#v (%v)", r.name, list, err)
	}
	r.metrics.numberOfItemsInList.Observe(float64(len(items)))
	if err := r.syncWith(items, resourceVersion); err != nil {
		return fmt.Errorf("%s: Unable to sync list result: %v", r.name, err)
	}
	r.setLastSyncResourceVersion(resourceVersion)
    ...
}    
```

首先将资源的版本号设置为0，然后调用`listerWatcher.List(options)`，列出所有list的内容。

```go
// 版本号设置为0
options := metav1.ListOptions{ResourceVersion: "0"}
// list接口
list, err := r.listerWatcher.List(options)
```

获取资源版本号，并将list的内容提取成对象列表。

```go
// 获取版本号
resourceVersion = listMetaInterface.GetResourceVersion()
// 将list的内容提取成对象列表
items, err := meta.ExtractList(list)
```

将list中对象列表的内容和版本号存储到本地的缓存store中，并全量替换已有的store的内容。

```go
err := r.syncWith(items, resourceVersion)
```

syncWith调用了store的Replace的方法来替换原来store中的数据。

```go
// syncWith replaces the store's items with the given list.
func (r *Reflector) syncWith(items []runtime.Object, resourceVersion string) error {
	found := make([]interface{}, 0, len(items))
	for _, item := range items {
		found = append(found, item)
	}
	return r.store.Replace(found, resourceVersion)
}
```

Store.Replace方法定义如下：

```go
type Store interface {
	...
	// Replace will delete the contents of the store, using instead the
	// given list. Store takes ownership of the list, you should not reference
	// it after calling this function.
	Replace([]interface{}, string) error
    ...
}
```

最后设置最新的资源版本号。

```go
r.setLastSyncResourceVersion(resourceVersion)
```

setLastSyncResourceVersion:

```go
func (r *Reflector) setLastSyncResourceVersion(v string) {
	r.lastSyncResourceVersionMutex.Lock()
	defer r.lastSyncResourceVersionMutex.Unlock()
	r.lastSyncResourceVersion = v

	rv, err := strconv.Atoi(v)
	if err == nil {
		r.metrics.lastResourceVersion.Set(float64(rv))
	}
}
```

### 3.4.2. store.Resync

```go
resyncerrc := make(chan error, 1)
cancelCh := make(chan struct{})
defer close(cancelCh)
go func() {
	resyncCh, cleanup := r.resyncChan()
	defer func() {
		cleanup() // Call the last one written into cleanup
	}()
	for {
		select {
		case <-resyncCh:
		case <-stopCh:
			return
		case <-cancelCh:
			return
		}
		if r.ShouldResync == nil || r.ShouldResync() {
			glog.V(4).Infof("%s: forcing resync", r.name)
			if err := r.store.Resync(); err != nil {
				resyncerrc <- err
				return
			}
		}
		cleanup()
		resyncCh, cleanup = r.resyncChan()
	}
}()
```

核心代码：

```go
err := r.store.Resync()
```

store的具体对象为`DeltaFIFO`，即调用DeltaFIFO.Resync

```go
// Resync will send a sync event for each item
func (f *DeltaFIFO) Resync() error {
	f.lock.Lock()
	defer f.lock.Unlock()

	if f.knownObjects == nil {
		return nil
	}

	keys := f.knownObjects.ListKeys()
	for _, k := range keys {
		if err := f.syncKeyLocked(k); err != nil {
			return err
		}
	}
	return nil
}
```

### 3.4.3. Watch

```go
for {
	// give the stopCh a chance to stop the loop, even in case of continue statements further down on errors
	select {
	case <-stopCh:
		return nil
	default:
	}

	timemoutseconds := int64(minWatchTimeout.Seconds() * (rand.Float64() + 1.0))
	options = metav1.ListOptions{
		ResourceVersion: resourceVersion,
		// We want to avoid situations of hanging watchers. Stop any wachers that do not
		// receive any events within the timeout window.
		TimeoutSeconds: &timemoutseconds,
	}

	r.metrics.numberOfWatches.Inc()
	w, err := r.listerWatcher.Watch(options)
	if err != nil {
		switch err {
		case io.EOF:
			// watch closed normally
		case io.ErrUnexpectedEOF:
			glog.V(1).Infof("%s: Watch for %v closed with unexpected EOF: %v", r.name, r.expectedType, err)
		default:
			utilruntime.HandleError(fmt.Errorf("%s: Failed to watch %v: %v", r.name, r.expectedType, err))
		}
		// If this is "connection refused" error, it means that most likely apiserver is not responsive.
		// It doesn't make sense to re-list all objects because most likely we will be able to restart
		// watch where we ended.
		// If that's the case wait and resend watch request.
		if urlError, ok := err.(*url.Error); ok {
			if opError, ok := urlError.Err.(*net.OpError); ok {
				if errno, ok := opError.Err.(syscall.Errno); ok && errno == syscall.ECONNREFUSED {
					time.Sleep(time.Second)
					continue
				}
			}
		}
		return nil
	}

	if err := r.watchHandler(w, &resourceVersion, resyncerrc, stopCh); err != nil {
		if err != errorStopRequested {
			glog.Warningf("%s: watch of %v ended with: %v", r.name, r.expectedType, err)
		}
		return nil
	}
}
```

设置watch的超时时间，默认为5分钟。

```go
timemoutseconds := int64(minWatchTimeout.Seconds() * (rand.Float64() + 1.0))
options = metav1.ListOptions{
	ResourceVersion: resourceVersion,
	// We want to avoid situations of hanging watchers. Stop any wachers that do not
	// receive any events within the timeout window.
	TimeoutSeconds: &timemoutseconds,
}
```

执行listerWatcher.Watch(options)。

```go
w, err := r.listerWatcher.Watch(options)
```

执行watchHandler。

```go
err := r.watchHandler(w, &resourceVersion, resyncerrc, stopCh)
```

### 3.4.4. watchHandler

watchHandler主要是通过watch的方式保证当前的资源版本是最新的。

```go
// watchHandler watches w and keeps *resourceVersion up to date.
func (r *Reflector) watchHandler(w watch.Interface, resourceVersion *string, errc chan error, stopCh <-chan struct{}) error {
	start := r.clock.Now()
	eventCount := 0

	// Stopping the watcher should be idempotent and if we return from this function there's no way
	// we're coming back in with the same watch interface.
	defer w.Stop()
	// update metrics
	defer func() {
		r.metrics.numberOfItemsInWatch.Observe(float64(eventCount))
		r.metrics.watchDuration.Observe(time.Since(start).Seconds())
	}()

loop:
	for {
		select {
		case <-stopCh:
			return errorStopRequested
		case err := <-errc:
			return err
		case event, ok := <-w.ResultChan():
			if !ok {
				break loop
			}
			if event.Type == watch.Error {
				return apierrs.FromObject(event.Object)
			}
			if e, a := r.expectedType, reflect.TypeOf(event.Object); e != nil && e != a {
				utilruntime.HandleError(fmt.Errorf("%s: expected type %v, but watch event object had type %v", r.name, e, a))
				continue
			}
			meta, err := meta.Accessor(event.Object)
			if err != nil {
				utilruntime.HandleError(fmt.Errorf("%s: unable to understand watch event %#v", r.name, event))
				continue
			}
			newResourceVersion := meta.GetResourceVersion()
			switch event.Type {
			case watch.Added:
				err := r.store.Add(event.Object)
				if err != nil {
					utilruntime.HandleError(fmt.Errorf("%s: unable to add watch event object (%#v) to store: %v", r.name, event.Object, err))
				}
			case watch.Modified:
				err := r.store.Update(event.Object)
				if err != nil {
					utilruntime.HandleError(fmt.Errorf("%s: unable to update watch event object (%#v) to store: %v", r.name, event.Object, err))
				}
			case watch.Deleted:
				// TODO: Will any consumers need access to the "last known
				// state", which is passed in event.Object? If so, may need
				// to change this.
				err := r.store.Delete(event.Object)
				if err != nil {
					utilruntime.HandleError(fmt.Errorf("%s: unable to delete watch event object (%#v) from store: %v", r.name, event.Object, err))
				}
			default:
				utilruntime.HandleError(fmt.Errorf("%s: unable to understand watch event %#v", r.name, event))
			}
			*resourceVersion = newResourceVersion
			r.setLastSyncResourceVersion(newResourceVersion)
			eventCount++
		}
	}

	watchDuration := r.clock.Now().Sub(start)
	if watchDuration < 1*time.Second && eventCount == 0 {
		r.metrics.numberOfShortWatches.Inc()
		return fmt.Errorf("very short watch: %s: Unexpected watch close - watch lasted less than a second and no items received", r.name)
	}
	glog.V(4).Infof("%s: Watch close - %v total %v items received", r.name, r.expectedType, eventCount)
	return nil
}
```

获取watch接口中的事件的channel，来获取事件的内容。

```go
for {
	select {
	...
	case event, ok := <-w.ResultChan():
    ...
}        
```

当获得添加、更新、删除的事件时，将对应的对象更新到本地缓存store中。

```go
switch event.Type {
case watch.Added:
	err := r.store.Add(event.Object)
	if err != nil {
		utilruntime.HandleError(fmt.Errorf("%s: unable to add watch event object (%#v) to store: %v", r.name, event.Object, err))
	}
case watch.Modified:
	err := r.store.Update(event.Object)
	if err != nil {
		utilruntime.HandleError(fmt.Errorf("%s: unable to update watch event object (%#v) to store: %v", r.name, event.Object, err))
	}
case watch.Deleted:
	// TODO: Will any consumers need access to the "last known
	// state", which is passed in event.Object? If so, may need
	// to change this.
	err := r.store.Delete(event.Object)
	if err != nil {
		utilruntime.HandleError(fmt.Errorf("%s: unable to delete watch event object (%#v) from store: %v", r.name, event.Object, err))
	}
default:
	utilruntime.HandleError(fmt.Errorf("%s: unable to understand watch event %#v", r.name, event))
}
```

更新当前的最新版本号。

```go
newResourceVersion := meta.GetResourceVersion()
*resourceVersion = newResourceVersion
r.setLastSyncResourceVersion(newResourceVersion)
```

通过对Reflector模块的分析，可以看到多次使用到本地缓存store模块，而store的数据由DeltaFIFO赋值而来，以下针对DeltaFIFO和store做分析。

# 4. DeltaFIFO

DeltaFIFO由NewDeltaFIFO初始化，并赋值给config.Queue。

```go
func (s *sharedIndexInformer) Run(stopCh <-chan struct{}) {
	fifo := NewDeltaFIFO(MetaNamespaceKeyFunc, nil, s.indexer)

	cfg := &Config{
		Queue:            fifo,
		...
	}
    ...
}    
```

## 4.1. NewDeltaFIFO

```go
// NewDeltaFIFO returns a Store which can be used process changes to items.
//
// keyFunc is used to figure out what key an object should have. (It's
// exposed in the returned DeltaFIFO's KeyOf() method, with bonus features.)
//
// 'compressor' may compress as many or as few items as it wants
// (including returning an empty slice), but it should do what it
// does quickly since it is called while the queue is locked.
// 'compressor' may be nil if you don't want any delta compression.
//
// 'keyLister' is expected to return a list of keys that the consumer of
// this queue "knows about". It is used to decide which items are missing
// when Replace() is called; 'Deleted' deltas are produced for these items.
// It may be nil if you don't need to detect all deletions.
// TODO: consider merging keyLister with this object, tracking a list of
//       "known" keys when Pop() is called. Have to think about how that
//       affects error retrying.
// TODO(lavalamp): I believe there is a possible race only when using an
//                 external known object source that the above TODO would
//                 fix.
//
// Also see the comment on DeltaFIFO.
func NewDeltaFIFO(keyFunc KeyFunc, compressor DeltaCompressor, knownObjects KeyListerGetter) *DeltaFIFO {
	f := &DeltaFIFO{
		items:           map[string]Deltas{},
		queue:           []string{},
		keyFunc:         keyFunc,
		deltaCompressor: compressor,
		knownObjects:    knownObjects,
	}
	f.cond.L = &f.lock
	return f
}
```

controller.Run的部分调用了NewReflector。

```go
func (c *controller) Run(stopCh <-chan struct{}) {
	...
	r := NewReflector(
		c.config.ListerWatcher,
		c.config.ObjectType,
		c.config.Queue,
		c.config.FullResyncPeriod,
	)
    ...
}    
```

NewReflector构造函数，将c.config.Queue赋值给Reflector.store的属性。

```go
func NewReflector(lw ListerWatcher, expectedType interface{}, store Store, resyncPeriod time.Duration) *Reflector {
	return NewNamedReflector(getDefaultReflectorName(internalPackages...), lw, expectedType, store, resyncPeriod)
}

// NewNamedReflector same as NewReflector, but with a specified name for logging
func NewNamedReflector(name string, lw ListerWatcher, expectedType interface{}, store Store, resyncPeriod time.Duration) *Reflector {
	reflectorSuffix := atomic.AddInt64(&reflectorDisambiguator, 1)
	r := &Reflector{
		name: name,
		// we need this to be unique per process (some names are still the same)but obvious who it belongs to
		metrics:       newReflectorMetrics(makeValidPromethusMetricLabel(fmt.Sprintf("reflector_"+name+"_%d", reflectorSuffix))),
		listerWatcher: lw,
		store:         store,
		expectedType:  reflect.TypeOf(expectedType),
		period:        time.Second,
		resyncPeriod:  resyncPeriod,
		clock:         &clock.RealClock{},
	}
	return r
}
```

## 4.2. DeltaFIFO

DeltaFIFO是一个生产者与消费者的队列，其中Reflector是生产者，消费者调用Pop()的方法。

DeltaFIFO主要用在以下场景：

- 希望对象变更最多处理一次
- 处理对象时，希望查看自上次处理对象以来发生的所有事情
- 要处理对象的删除
- 希望定期重新处理对象

```go
// DeltaFIFO is like FIFO, but allows you to process deletes.
//
// DeltaFIFO is a producer-consumer queue, where a Reflector is
// intended to be the producer, and the consumer is whatever calls
// the Pop() method.
//
// DeltaFIFO solves this use case:
//  * You want to process every object change (delta) at most once.
//  * When you process an object, you want to see everything
//    that's happened to it since you last processed it.
//  * You want to process the deletion of objects.
//  * You might want to periodically reprocess objects.
//
// DeltaFIFO's Pop(), Get(), and GetByKey() methods return
// interface{} to satisfy the Store/Queue interfaces, but it
// will always return an object of type Deltas.
//
// A note on threading: If you call Pop() in parallel from multiple
// threads, you could end up with multiple threads processing slightly
// different versions of the same object.
//
// A note on the KeyLister used by the DeltaFIFO: It's main purpose is
// to list keys that are "known", for the purpose of figuring out which
// items have been deleted when Replace() or Delete() are called. The deleted
// object will be included in the DeleteFinalStateUnknown markers. These objects
// could be stale.
//
// You may provide a function to compress deltas (e.g., represent a
// series of Updates as a single Update).
type DeltaFIFO struct {
	// lock/cond protects access to 'items' and 'queue'.
	lock sync.RWMutex
	cond sync.Cond

	// We depend on the property that items in the set are in
	// the queue and vice versa, and that all Deltas in this
	// map have at least one Delta.
	items map[string]Deltas
	queue []string

	// populated is true if the first batch of items inserted by Replace() has been populated
	// or Delete/Add/Update was called first.
	populated bool
	// initialPopulationCount is the number of items inserted by the first call of Replace()
	initialPopulationCount int

	// keyFunc is used to make the key used for queued item
	// insertion and retrieval, and should be deterministic.
	keyFunc KeyFunc

	// deltaCompressor tells us how to combine two or more
	// deltas. It may be nil.
	deltaCompressor DeltaCompressor

	// knownObjects list keys that are "known", for the
	// purpose of figuring out which items have been deleted
	// when Replace() or Delete() is called.
	knownObjects KeyListerGetter

	// Indication the queue is closed.
	// Used to indicate a queue is closed so a control loop can exit when a queue is empty.
	// Currently, not used to gate any of CRED operations.
	closed     bool
	closedLock sync.Mutex
}
```



## 4.3. Queue & Store

DeltaFIFO的类型是Queue接口，Reflector.store是Store接口，Queue接口是一个存储队列，Process的方法执行Queue.Pop出来的数据对象，

```go
// Queue is exactly like a Store, but has a Pop() method too.
type Queue interface {
	Store

	// Pop blocks until it has something to process.
	// It returns the object that was process and the result of processing.
	// The PopProcessFunc may return an ErrRequeue{...} to indicate the item
	// should be requeued before releasing the lock on the queue.
	Pop(PopProcessFunc) (interface{}, error)

	// AddIfNotPresent adds a value previously
	// returned by Pop back into the queue as long
	// as nothing else (presumably more recent)
	// has since been added.
	AddIfNotPresent(interface{}) error

	// Return true if the first batch of items has been popped
	HasSynced() bool

	// Close queue
	Close()
}
```

# 5. store

`Store`是一个通用的存储接口，Reflector通过watch server的方式更新数据到store中，store给Reflector提供本地的缓存，让Reflector可以像消息队列一样的工作。

`Store`实现的是一种可以准确的写入对象和获取对象的机制。

```go
// Store is a generic object storage interface. Reflector knows how to watch a server
// and update a store. A generic store is provided, which allows Reflector to be used
// as a local caching system, and an LRU store, which allows Reflector to work like a
// queue of items yet to be processed.
//
// Store makes no assumptions about stored object identity; it is the responsibility
// of a Store implementation to provide a mechanism to correctly key objects and to
// define the contract for obtaining objects by some arbitrary key type.
type Store interface {
	Add(obj interface{}) error
	Update(obj interface{}) error
	Delete(obj interface{}) error
	List() []interface{}
	ListKeys() []string
	Get(obj interface{}) (item interface{}, exists bool, err error)
	GetByKey(key string) (item interface{}, exists bool, err error)

	// Replace will delete the contents of the store, using instead the
	// given list. Store takes ownership of the list, you should not reference
	// it after calling this function.
	Replace([]interface{}, string) error
	Resync() error
}
```

其中`Replace`方法会删除原来store中的内容，并将新增的list的内容存入store中，即完全替换数据。

## 6.1.  cache

cache实现了store的接口，而cache的具体实现又是调用`ThreadSafeStore`接口来实现功能的。

cache的功能主要有以下两点：

- 通过keyFunc计算对象的key
- 调用ThreadSafeStorage接口的方法

```go
// cache responsibilities are limited to:
//	1. Computing keys for objects via keyFunc
//  2. Invoking methods of a ThreadSafeStorage interface
type cache struct {
	// cacheStorage bears the burden of thread safety for the cache
	cacheStorage ThreadSafeStore
	// keyFunc is used to make the key for objects stored in and retrieved from items, and
	// should be deterministic.
	keyFunc KeyFunc
}
```

其中ListAndWatch主要用到以下的方法：

**cache.Replace**

```go
// Replace will delete the contents of 'c', using instead the given list.
// 'c' takes ownership of the list, you should not reference the list again
// after calling this function.
func (c *cache) Replace(list []interface{}, resourceVersion string) error {
	items := map[string]interface{}{}
	for _, item := range list {
		key, err := c.keyFunc(item)
		if err != nil {
			return KeyError{item, err}
		}
		items[key] = item
	}
	c.cacheStorage.Replace(items, resourceVersion)
	return nil
}

```

**cache.Add**

```go
// Add inserts an item into the cache.
func (c *cache) Add(obj interface{}) error {
	key, err := c.keyFunc(obj)
	if err != nil {
		return KeyError{obj, err}
	}
	c.cacheStorage.Add(key, obj)
	return nil
}
```

**cache.Update**

```go
// Update sets an item in the cache to its updated state.
func (c *cache) Update(obj interface{}) error {
	key, err := c.keyFunc(obj)
	if err != nil {
		return KeyError{obj, err}
	}
	c.cacheStorage.Update(key, obj)
	return nil
}
```

**cache.Delete**

```go
// Delete removes an item from the cache.
func (c *cache) Delete(obj interface{}) error {
	key, err := c.keyFunc(obj)
	if err != nil {
		return KeyError{obj, err}
	}
	c.cacheStorage.Delete(key)
	return nil
}
```

## 6.2. ThreadSafeStore

cache的具体是调用`ThreadSafeStore`来实现的。

```go
// ThreadSafeStore is an interface that allows concurrent access to a storage backend.
// TL;DR caveats: you must not modify anything returned by Get or List as it will break
// the indexing feature in addition to not being thread safe.
//
// The guarantees of thread safety provided by List/Get are only valid if the caller
// treats returned items as read-only. For example, a pointer inserted in the store
// through `Add` will be returned as is by `Get`. Multiple clients might invoke `Get`
// on the same key and modify the pointer in a non-thread-safe way. Also note that
// modifying objects stored by the indexers (if any) will *not* automatically lead
// to a re-index. So it's not a good idea to directly modify the objects returned by
// Get/List, in general.
type ThreadSafeStore interface {
	Add(key string, obj interface{})
	Update(key string, obj interface{})
	Delete(key string)
	Get(key string) (item interface{}, exists bool)
	List() []interface{}
	ListKeys() []string
	Replace(map[string]interface{}, string)
	Index(indexName string, obj interface{}) ([]interface{}, error)
	IndexKeys(indexName, indexKey string) ([]string, error)
	ListIndexFuncValues(name string) []string
	ByIndex(indexName, indexKey string) ([]interface{}, error)
	GetIndexers() Indexers

	// AddIndexers adds more indexers to this store.  If you call this after you already have data
	// in the store, the results are undefined.
	AddIndexers(newIndexers Indexers) error
	Resync() error
}
```

**threadSafeMap**

```go
// threadSafeMap implements ThreadSafeStore
type threadSafeMap struct {
	lock  sync.RWMutex
	items map[string]interface{}

	// indexers maps a name to an IndexFunc
	indexers Indexers
	// indices maps a name to an Index
	indices Indices
}
```

# 6. processLoop

```go
func (c *controller) Run(stopCh <-chan struct{}) {
	...
	wait.Until(c.processLoop, time.Second, stopCh)
}
```

在controller.Run方法中会调用processLoop，以下分析`processLoop`的处理逻辑。

```go
// processLoop drains the work queue.
// TODO: Consider doing the processing in parallel. This will require a little thought
// to make sure that we don't end up processing the same object multiple times
// concurrently.
//
// TODO: Plumb through the stopCh here (and down to the queue) so that this can
// actually exit when the controller is stopped. Or just give up on this stuff
// ever being stoppable. Converting this whole package to use Context would
// also be helpful.
func (c *controller) processLoop() {
	for {
		obj, err := c.config.Queue.Pop(PopProcessFunc(c.config.Process))
		if err != nil {
			if err == FIFOClosedError {
				return
			}
			if c.config.RetryOnError {
				// This is the safe way to re-enqueue.
				c.config.Queue.AddIfNotPresent(obj)
			}
		}
	}
}
```

processLoop主要处理任务队列中的任务，其中处理逻辑是调用具体的`ProcessFunc`函数来实现，核心代码为：

```go
obj, err := c.config.Queue.Pop(PopProcessFunc(c.config.Process))
```

## 5.1. DeltaFIFO.Pop

Pop会阻塞住直到队列里面添加了新的对象，如果有多个对象，按照先进先出的原则处理，如果某个对象没有处理成功会重新被加入该队列中。

Pop中会调用具体的process函数来处理对象。

```go
// Pop blocks until an item is added to the queue, and then returns it.  If
// multiple items are ready, they are returned in the order in which they were
// added/updated. The item is removed from the queue (and the store) before it
// is returned, so if you don't successfully process it, you need to add it back
// with AddIfNotPresent().
// process function is called under lock, so it is safe update data structures
// in it that need to be in sync with the queue (e.g. knownKeys). The PopProcessFunc
// may return an instance of ErrRequeue with a nested error to indicate the current
// item should be requeued (equivalent to calling AddIfNotPresent under the lock).
//
// Pop returns a 'Deltas', which has a complete list of all the things
// that happened to the object (deltas) while it was sitting in the queue.
func (f *DeltaFIFO) Pop(process PopProcessFunc) (interface{}, error) {
	f.lock.Lock()
	defer f.lock.Unlock()
	for {
		for len(f.queue) == 0 {
			// When the queue is empty, invocation of Pop() is blocked until new item is enqueued.
			// When Close() is called, the f.closed is set and the condition is broadcasted.
			// Which causes this loop to continue and return from the Pop().
			if f.IsClosed() {
				return nil, FIFOClosedError
			}

			f.cond.Wait()
		}
		id := f.queue[0]
		f.queue = f.queue[1:]
		item, ok := f.items[id]
		if f.initialPopulationCount > 0 {
			f.initialPopulationCount--
		}
		if !ok {
			// Item may have been deleted subsequently.
			continue
		}
		delete(f.items, id)
		err := process(item)
		if e, ok := err.(ErrRequeue); ok {
			f.addIfNotPresent(id, item)
			err = e.Err
		}
		// Don't need to copyDeltas here, because we're transferring
		// ownership to the caller.
		return item, err
	}
}
```

核心代码：

```go
for {
	...
	item, ok := f.items[id]
	...
	err := process(item)
	if e, ok := err.(ErrRequeue); ok {
		f.addIfNotPresent(id, item)
		err = e.Err
	}
	// Don't need to copyDeltas here, because we're transferring
	// ownership to the caller.
	return item, err
}
```

## 5.2. HandleDeltas

```go
cfg := &Config{
	Queue:            fifo,
	ListerWatcher:    s.listerWatcher,
	ObjectType:       s.objectType,
	FullResyncPeriod: s.resyncCheckPeriod,
	RetryOnError:     false,
	ShouldResync:     s.processor.shouldResync,

	Process: s.HandleDeltas,
}
```

其中process函数就是在sharedIndexInformer.Run方法中，给config.Process赋值的`HandleDeltas`函数。

```go
func (s *sharedIndexInformer) HandleDeltas(obj interface{}) error {
	s.blockDeltas.Lock()
	defer s.blockDeltas.Unlock()

	// from oldest to newest
	for _, d := range obj.(Deltas) {
		switch d.Type {
		case Sync, Added, Updated:
			isSync := d.Type == Sync
			s.cacheMutationDetector.AddObject(d.Object)
			if old, exists, err := s.indexer.Get(d.Object); err == nil && exists {
				if err := s.indexer.Update(d.Object); err != nil {
					return err
				}
				s.processor.distribute(updateNotification{oldObj: old, newObj: d.Object}, isSync)
			} else {
				if err := s.indexer.Add(d.Object); err != nil {
					return err
				}
				s.processor.distribute(addNotification{newObj: d.Object}, isSync)
			}
		case Deleted:
			if err := s.indexer.Delete(d.Object); err != nil {
				return err
			}
			s.processor.distribute(deleteNotification{oldObj: d.Object}, false)
		}
	}
	return nil
}
```

核心代码：

```go
switch d.Type {
case Sync, Added, Updated:
	...
	if old, exists, err := s.indexer.Get(d.Object); err == nil && exists {
		...
		s.processor.distribute(updateNotification{oldObj: old, newObj: d.Object}, isSync)
	} else {
		...
		s.processor.distribute(addNotification{newObj: d.Object}, isSync)
	}
case Deleted:
	...
	s.processor.distribute(deleteNotification{oldObj: d.Object}, false)
}
```

根据不同的类型，调用`processor.distribute`方法，该方法将对象加入`processorListener`的channel中。

## 5.3. sharedProcessor.distribute

```go
func (p *sharedProcessor) distribute(obj interface{}, sync bool) {
	p.listenersLock.RLock()
	defer p.listenersLock.RUnlock()

	if sync {
		for _, listener := range p.syncingListeners {
			listener.add(obj)
		}
	} else {
		for _, listener := range p.listeners {
			listener.add(obj)
		}
	}
}
```

**processorListener.add:**

```go
func (p *processorListener) add(notification interface{}) {
	p.addCh <- notification
}
```

综合以上的分析，可以看出processLoop通过调用HandleDeltas，再调用distribute，processorListener.add最终将不同更新类型的对象加入`processorListener`的channel中，供processorListener.Run使用。以下分析processorListener.Run的部分。

# 7. processor

processor的主要功能就是记录了所有的回调函数实例(即 ResourceEventHandler 实例)，并负责触发这些函数。在sharedIndexInformer.Run部分会调用processor.run。

流程：

1. listenser的add函数负责将notify装进pendingNotifications。
2. pop函数取出pendingNotifications的第一个nofify,输出到nextCh channel。
3. run函数则负责取出notify，然后根据notify的类型(增加、删除、更新)触发相应的处理函数，这些函数是在不同的`NewXxxcontroller`实现中注册的。

```go
func (s *sharedIndexInformer) Run(stopCh <-chan struct{}) {
	...
	wg.StartWithChannel(processorStopCh, s.processor.run)
	...
}
```

## 7.1. sharedProcessor.Run

```go
func (p *sharedProcessor) run(stopCh <-chan struct{}) {
   func() {
      p.listenersLock.RLock()
      defer p.listenersLock.RUnlock()
      for _, listener := range p.listeners {
         p.wg.Start(listener.run)
         p.wg.Start(listener.pop)
      }
   }()
   <-stopCh
   p.listenersLock.RLock()
   defer p.listenersLock.RUnlock()
   for _, listener := range p.listeners {
      close(listener.addCh) // Tell .pop() to stop. .pop() will tell .run() to stop
   }
   p.wg.Wait() // Wait for all .pop() and .run() to stop
}
```

### 7.1.1. listener.pop

pop函数取出pendingNotifications的第一个nofify,输出到nextCh channel。

```go
func (p *processorListener) pop() {
	defer utilruntime.HandleCrash()
	defer close(p.nextCh) // Tell .run() to stop

	var nextCh chan<- interface{}
	var notification interface{}
	for {
		select {
		case nextCh <- notification:
			// Notification dispatched
			var ok bool
			notification, ok = p.pendingNotifications.ReadOne()
			if !ok { // Nothing to pop
				nextCh = nil // Disable this select case
			}
		case notificationToAdd, ok := <-p.addCh:
			if !ok {
				return
			}
			if notification == nil { // No notification to pop (and pendingNotifications is empty)
				// Optimize the case - skip adding to pendingNotifications
				notification = notificationToAdd
				nextCh = p.nextCh
			} else { // There is already a notification waiting to be dispatched
				p.pendingNotifications.WriteOne(notificationToAdd)
			}
		}
	}
}
```

### 7.1.2. listener.run

 listener.run部分根据不同的更新类型调用不同的处理函数。

```go
func (p *processorListener) run() {
	defer utilruntime.HandleCrash()

	for next := range p.nextCh {
		switch notification := next.(type) {
		case updateNotification:
			p.handler.OnUpdate(notification.oldObj, notification.newObj)
		case addNotification:
			p.handler.OnAdd(notification.newObj)
		case deleteNotification:
			p.handler.OnDelete(notification.oldObj)
		default:
			utilruntime.HandleError(fmt.Errorf("unrecognized notification: %#v", next))
		}
	}
}
```

其中具体的实现函数handler是在NewDeploymentController（其他不同类型的controller类似）中赋值的，而该handler是一个接口，具体如下：

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
```

## 7.2. ResourceEventHandler

以下以DeploymentController的处理逻辑为例。

在`NewDeploymentController`部分会注册deployment的事件函数，以下注册了三种类型的事件函数，其中包括：dInformer、rsInformer和podInformer。

```go
// NewDeploymentController creates a new DeploymentController.
func NewDeploymentController(dInformer extensionsinformers.DeploymentInformer, rsInformer extensionsinformers.ReplicaSetInformer, podInformer coreinformers.PodInformer, client clientset.Interface) (*DeploymentController, error) {
	...
	dInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc:    dc.addDeployment,
		UpdateFunc: dc.updateDeployment,
		// This will enter the sync loop and no-op, because the deployment has been deleted from the store.
		DeleteFunc: dc.deleteDeployment,
	})
	rsInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc:    dc.addReplicaSet,
		UpdateFunc: dc.updateReplicaSet,
		DeleteFunc: dc.deleteReplicaSet,
	})
	podInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		DeleteFunc: dc.deletePod,
	})
    ...
}    
```

### 7.2.1. addDeployment

以下以`addDeployment`为例，addDeployment主要是将对象加入到enqueueDeployment的队列中。

```go
func (dc *DeploymentController) addDeployment(obj interface{}) {
	d := obj.(*extensions.Deployment)
	glog.V(4).Infof("Adding deployment %s", d.Name)
	dc.enqueueDeployment(d)
}
```

enqueueDeployment的定义

```go
type DeploymentController struct {
	...
	enqueueDeployment func(deployment *extensions.Deployment)
    ...
}    
```

将dc.enqueue赋值给dc.enqueueDeployment

```go
dc.enqueueDeployment = dc.enqueue
```

dc.enqueue调用了dc.queue.Add(key)

```go
func (dc *DeploymentController) enqueue(deployment *extensions.Deployment) {
	key, err := controller.KeyFunc(deployment)
	if err != nil {
		utilruntime.HandleError(fmt.Errorf("Couldn't get key for object %#v: %v", deployment, err))
		return
	}

	dc.queue.Add(key)
}
```

dc.queue主要记录了需要被同步的deployment的对象，供syncDeployment使用。

```go
dc := &DeploymentController{
	...
	queue:         workqueue.NewNamedRateLimitingQueue(workqueue.DefaultControllerRateLimiter(), "deployment"),
}
```

NewNamedRateLimitingQueue

```go
func NewNamedRateLimitingQueue(rateLimiter RateLimiter, name string) RateLimitingInterface {
	return &rateLimitingType{
		DelayingInterface: NewNamedDelayingQueue(name),
		rateLimiter:       rateLimiter,
	}
}
```

通过以上分析，可以看出processor记录了不同类似的事件函数，其中事件函数在NewXxxController构造函数部分注册，具体事件函数的处理，一般是将需要处理的对象加入对应的controller的任务队列中，然后由类似syncDeployment的同步函数来维持期望状态的同步逻辑。

# 8. 总结

本文分析的部分主要是k8s的`informer`机制，即`List-Watch`机制。

## 8.1. Reflector

`Reflector`的主要作用是watch指定的k8s资源，并将变化同步到本地是`store`中。`Reflector`只会放置指定的`expectedType`类型的资源到`store`中，除非`expectedType`为nil。如果`resyncPeriod`不为零，那么`Reflector`为以`resyncPeriod`为周期定期执行list的操作，这样就可以使用`Reflector`来定期处理所有的对象，也可以逐步处理变化的对象。

## 8.2. ListAndWatch

`ListAndWatch`第一次会列出所有的对象，并获取资源对象的版本号，然后watch资源对象的版本号来查看是否有被变更。首先会将资源版本号设置为0，`list()`可能会导致本地的缓存相对于etcd里面的内容存在延迟，`Reflector`会通过`watch`的方法将延迟的部分补充上，使得本地的缓存数据与etcd的数据保持一致。

## 8.3. DeltaFIFO

`DeltaFIFO`是一个生产者与消费者的队列，其中Reflector是生产者，消费者调用Pop()的方法。

DeltaFIFO主要用在以下场景：

- 希望对象变更最多处理一次
- 处理对象时，希望查看自上次处理对象以来发生的所有事情
- 要处理对象的删除
- 希望定期重新处理对象

## 8.4. store

`Store`是一个通用的存储接口，Reflector通过watch server的方式更新数据到store中，store给Reflector提供本地的缓存，让Reflector可以像消息队列一样的工作。

`Store`实现的是一种可以准确的写入对象和获取对象的机制。

## 8.5. processor

`processor`的主要功能就是记录了所有的回调函数实例(即 ResourceEventHandler 实例)，并负责触发这些函数。在sharedIndexInformer.Run部分会调用processor.run。

流程：

1. listenser的add函数负责将notify装进pendingNotifications。
2. pop函数取出pendingNotifications的第一个nofify,输出到nextCh channel。
3. run函数则负责取出notify，然后根据notify的类型(增加、删除、更新)触发相应的处理函数，这些函数是在不同的`NewXxxcontroller`实现中注册的。

`processor`记录了不同类似的事件函数，其中事件函数在`NewXxxController`构造函数部分注册，具体事件函数的处理，一般是将需要处理的对象加入对应的controller的任务队列中，然后由类似`syncDeployment`的同步函数来维持期望状态的同步逻辑。

## 8.6. 主要步骤

1. 在controller-manager的Run函数部分调用了InformerFactory.Start的方法，Start方法初始化各种类型的informer，并且每个类型起了个informer.Run的goroutine。
2. informer.Run的部分先生成一个DeltaFIFO的队列来存储对象变化的数据。然后调用processor.Run和controller.Run函数。
3. controller.Run函数会生成一个Reflector，`Reflector`的主要作用是watch指定的k8s资源，并将变化同步到本地是`store`中。`Reflector`以`resyncPeriod`为周期定期执行list的操作，这样就可以使用`Reflector`来定期处理所有的对象，也可以逐步处理变化的对象。
4. Reflector接着执行ListAndWatch函数，ListAndWatch第一次会列出所有的对象，并获取资源对象的版本号，然后watch资源对象的版本号来查看是否有被变更。首先会将资源版本号设置为0，`list()`可能会导致本地的缓存相对于etcd里面的内容存在延迟，`Reflector`会通过`watch`的方法将延迟的部分补充上，使得本地的缓存数据与etcd的数据保持一致。
5. controller.Run函数还会调用processLoop函数，processLoop通过调用HandleDeltas，再调用distribute，processorListener.add最终将不同更新类型的对象加入`processorListener`的channel中，供processorListener.Run使用。
6. processor的主要功能就是记录了所有的回调函数实例(即 ResourceEventHandler 实例)，并负责触发这些函数。processor记录了不同类型的事件函数，其中事件函数在NewXxxController构造函数部分注册，具体事件函数的处理，一般是将需要处理的对象加入对应的controller的任务队列中，然后由类似syncDeployment的同步函数来维持期望状态的同步逻辑。



参考文章：

- <https://github.com/kubernetes/client-go/tree/master/tools/cache>

- <https://github.com/kubernetes/sample-controller/blob/master/docs/controller-client-go.md>
- <https://github.com/kubernetes/client-go/blob/master/examples/workqueue/main.go>
