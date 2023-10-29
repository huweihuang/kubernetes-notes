---
title: "如何开发一个Operator"
weight: 2
catalog: true
date: 2023-07-23 10:50:57
subtitle:
header-img: 
tags:
- Operator
catagories:
- Operator
---

开发一个k8s operator组件主要会用到以下几个仓库或工具：

- [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder)/[operator-sdk](https://github.com/operator-framework/operator-sdk)：主要用于创建CRD对象。

- [controller-manager](https://github.com/kubernetes-sigs/controller-runtime)：主要用于实现operator的controller逻辑。

本文以kubebuilder的工具和[controller-manager example](https://github.com/kubernetes-sigs/controller-runtime/blob/main/examples/crd/main.go)为例。

# 1. 准备工具环境及创建项目

安装kubebuilder工具

```bash
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/
```

创建operator项目目录

```bash
$ kubebuilder init --domain example.com --license apache2 --owner "Your Name" --repo github.com/example/my-operator
```

将 `example.com` 替换为你的域名，`Your Name` 替换为你的名字，`github.com/example/my-operator` 替换为你的 GitHub 仓库。

# 2. 创建CRD对象

```bash
$ kubebuilder create api --group mygroup --version v1alpha1 --kind MyResource
```

这将在 `api/v1alpha1` 文件夹中创建一个名为 `myresource_types.go` 的文件，其中定义了 `MyResource` 资源的规范和状态。

编辑 `api/v1alpha1/myresource_types.go` 文件，添加自定义资源的规范和状态字段。

# 3. 实现控制器逻辑

在 `controllers/myresource_controller.go` 文件中实现控制器逻辑。该部分是不同的CRD实现自定义逻辑的核心部分。

主要包含以下几个部分：

1. **定义ReconcileMyResource结构体。**

2. **实现`func (r *ReconcileMyResource) Reconcile(ctx context.Context, request reconcile.Request) (reconcile.Result, error)`函数接口。**

3. **定义finalizer逻辑。**

4. **定义reconcile逻辑。**

```go
package controllers

import (
  "context"
  "github.com/go-logr/logr"
  "sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
  "sigs.k8s.io/controller-runtime/pkg/controller/inject"
  "sigs.k8s.io/controller-runtime/pkg/reconcile"

  myv1alpha1 "github.com/example/my-operator/api/v1alpha1"
  corev1 "k8s.io/api/core/v1"
  "k8s.io/apimachinery/pkg/api/errors"
  "k8s.io/apimachinery/pkg/runtime"
  "sigs.k8s.io/controller-runtime/pkg/client"
  "sigs.k8s.io/controller-runtime/pkg/controller"
  logf "sigs.k8s.io/controller-runtime/pkg/log"
  "sigs.k8s.io/controller-runtime/pkg/log/zap"
  "sigs.k8s.io/controller-runtime/pkg/manager"
  "sigs.k8s.io/controller-runtime/pkg/reconcile"
  "sigs.k8s.io/controller-runtime/pkg/source"
)

var log = logf.Log.WithName("controller_myresource")

// Add creates a new MyResource Controller and adds it to the Manager. The Manager will set fields on the Controller
// and Start it when the Manager is Started.
func Add(mgr manager.Manager) error {
  return add(mgr, newReconciler(mgr))
}

// newReconciler returns a new reconcile.Reconciler
func newReconciler(mgr manager.Manager) reconcile.Reconciler {
  return &ReconcileMyResource{client: mgr.GetClient(), scheme: mgr.GetScheme()}
}

// blank assignment to verify that ReconcileMyResource implements reconcile.Reconciler
var _ reconcile.Reconciler = &ReconcileMyResource{}

// ReconcileMyResource reconciles a MyResource object
type ReconcileMyResource struct {
  client client.Client
  scheme *runtime.Scheme
}

// Reconcile reads that state of the cluster for a MyResource object and makes changes based on the state read
// and what is in the MyResource.Spec
func (r *ReconcileMyResource) Reconcile(ctx context.Context, request reconcile.Request) (reconcile.Result, error) {
  reqLogger := log.WithValues("Namespace", request.Namespace, "Name", request.Name)
  reqLogger.Info("Reconciling MyResource")

  // Fetch the MyResource instance
  myresource := &myv1alpha1.MyResource{}
  err := r.client.Get(ctx, request.NamespacedName, myresource)
  if err != nil {
    if errors.IsNotFound(err) {
      // Request object not found, could have been deleted after reconcile request.
      // Owned objects are automatically garbage collected. For additional cleanup logic use finalizers.
      // Return and don't requeue
      return reconcile.Result{}, nil
    }
    // Error reading the object - requeue the request.
    return reconcile.Result{}, err
  }

  // Add finalizer logic here

  // Add reconcile logic here

  return reconcile.Result{}, nil
}
```

# 4. 注册控制器

在 `main.go` 文件中注册控制器，主要包含以下几个步骤

1. **ctrl.SetLogger(zap.New())：注册日志工具**

2. **ctrl.NewManager：创建一个manager，必要时可设置选主逻辑。**

3. **ctrl.NewControllerManagedBy(mgr)：预计mgr创建manager controller并注册Reconciler。**

4. **mgr.Start(ctrl.SetupSignalHandler()): 运行mgr。**

```go
func main() {
    // set logger
    ctrl.SetLogger(zap.New())

    // Set up a Manager
    mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
      Scheme:             myv1alpha1.SchemeBuilder.Scheme,
      MetricsBindAddress: *metricsHost,
      Port:               9443,
      LeaderElection:     *enableLeaderElection,
      LeaderElectionID:   "my-operator-lock",
    })
    if err != nil {
        setupLog.Error(err, "unable to start manager")
        os.Exit(1)
    }

    // in a real controller, we'd create a new scheme for this
    err = api.AddToScheme(mgr.GetScheme())
    if err != nil {
        setupLog.Error(err, "unable to add scheme")
        os.Exit(1)
    }

    // Create a new Reconciler
    r := &ReconcileMyResource{
      client: m.GetClient(),
      scheme: m.GetScheme(),
    }

    // Create a new Controller and register the Reconciler
    err = ctrl.NewControllerManagedBy(mgr).
        For(&myv1alpha1.MyResource{}).     // 自定义crd
        Complete(r)                        // 注册Reconciler
    if err != nil {
        setupLog.Error(err, "unable to create controller")
        os.Exit(1)
    }

    err = ctrl.NewWebhookManagedBy(mgr).
        For(&api.ChaosPod{}).
        Complete()
    if err != nil {
        setupLog.Error(err, "unable to create webhook")
        os.Exit(1)
    }

    setupLog.Info("starting manager")
    if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
        setupLog.Error(err, "problem running manager")
        os.Exit(1)
    }
}
```

参考：

- [Implementing a controller - The Kubebuilder Book](https://book.kubebuilder.io/cronjob-tutorial/controller-implementation.html)

- [controller-runtime源码分析 | 李乾坤的博客](https://qiankunli.github.io/2020/08/10/controller_runtime.html)

- [Kubebuilder - SDK for building Kubernetes APIs using CRDs](https://github.com/kubernetes-sigs/kubebuilder)

- [operator-framework/operator-sdk: SDK for building Kubernetes applications.](https://github.com/operator-framework/operator-sdk)

- https://blog.hdls.me/16500403497126.html

- [kubebuilder-cronjob_controller](https://github.com/kubernetes-sigs/kubebuilder/blob/master/docs/book/src/multiversion-tutorial/testdata/project/controllers/cronjob_controller.go)


