---
title: "kubebuilder的使用"
weight: 1
catalog: true
date: 2021-08-13 10:50:57
subtitle:
header-img: 
tags:
- Operator
catagories:
- Operator
---

# 1. kubebuilder

## 1.1. 安装kubebuilder

```bash
# download kubebuilder and install locally.
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/
```

## 1.2. kubebuilder命令

```bash
Development kit for building Kubernetes extensions and tools.

Provides libraries and tools to create new projects, APIs and controllers.
Includes tools for packaging artifacts into an installer container.

Typical project lifecycle:

- initialize a project:

  kubebuilder init --domain example.com --license apache2 --owner "The Kubernetes authors"

- create one or more a new resource APIs and add your code to them:

  kubebuilder create api --group <group> --version <version> --kind <Kind>

Create resource will prompt the user for if it should scaffold the Resource and / or Controller. To only
scaffold a Controller for an existing Resource, select "n" for Resource. To only define
the schema for a Resource without writing a Controller, select "n" for Controller.

After the scaffold is written, api will run make on the project.

Usage:
  kubebuilder [command]

Available Commands:
  create      Scaffold a Kubernetes API or webhook.
  edit        This command will edit the project configuration
  help        Help about any command
  init        Initialize a new project
  version     Print the kubebuilder version

Flags:
  -h, --help   help for kubebuilder

Use "kubebuilder [command] --help" for more information about a command.
```

# 2. 操作步骤

## 2.1. 初始化

```bash
mkdir $GOPATH/src/github.com/huweihuang/operator-example
cd $GOPATH/src/github.com/huweihuang/operator-example

go mod init github.com/huweihuang/operator-example
```

## 2.2. 创建项目

```bash
# kubebuilder init --domain github.com --license apache2 --owner "Hu Weihuang"
Writing scaffold for you to edit...
Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.5.0
Update go.mod:
$ go mod tidy
Running make:
$ make
go: creating new go.mod: module tmp
go: finding sigs.k8s.io v0.2.5
go: finding sigs.k8s.io/controller-tools/cmd v0.2.5
go: finding sigs.k8s.io/controller-tools/cmd/controller-gen v0.2.5
/Users/weihuanghu/go/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
Next: define a resource with:
$ kubebuilder create api
```

查看生成文件：

```bash
./
├── Dockerfile
├── Makefile
├── PROJECT
├── bin
│   └── manager
├── config
│   ├── certmanager
│   │   ├── certificate.yaml
│   │   ├── kustomization.yaml
│   │   └── kustomizeconfig.yaml
│   ├── default
│   │   ├── kustomization.yaml
│   │   ├── manager_auth_proxy_patch.yaml
│   │   ├── manager_webhook_patch.yaml
│   │   └── webhookcainjection_patch.yaml
│   ├── manager
│   │   ├── kustomization.yaml
│   │   └── manager.yaml
│   ├── prometheus
│   │   ├── kustomization.yaml
│   │   └── monitor.yaml
│   ├── rbac
│   │   ├── auth_proxy_client_clusterrole.yaml
│   │   ├── auth_proxy_role.yaml
│   │   ├── auth_proxy_role_binding.yaml
│   │   ├── auth_proxy_service.yaml
│   │   ├── kustomization.yaml
│   │   ├── leader_election_role.yaml
│   │   ├── leader_election_role_binding.yaml
│   │   └── role_binding.yaml
│   └── webhook
│       ├── kustomization.yaml
│       ├── kustomizeconfig.yaml
│       └── service.yaml
├── go.mod
├── go.sum
├── hack
│   └── boilerplate.go.txt
└── main.go
```

## 2.3. 创建API

```bash
# kubebuilder create api --group webapp --version v1 --kind Guestbook
Create Resource [y/n]
y
Create Controller [y/n]
y
Writing scaffold for you to edit...
api/v1/guestbook_types.go
controllers/guestbook_controller.go
Running make:
$ make
go: creating new go.mod: module tmp
go: finding sigs.k8s.io/controller-tools/cmd v0.2.5
go: finding sigs.k8s.io/controller-tools/cmd/controller-gen v0.2.5
go: finding sigs.k8s.io v0.2.5
/Users/weihuanghu/go/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
```

查看创建文件

```bash
api
└── v1
    ├── groupversion_info.go
    ├── guestbook_types.go
    └── zz_generated.deepcopy.go
controllers
├── guestbook_controller.go
└── suite_test.go
```

查看api/v1/guestbook_types.go

```go
// GuestbookSpec defines the desired state of Guestbook
type GuestbookSpec struct {
    // INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
    // Important: Run "make" to regenerate code after modifying this file

    // Quantity of instances
    // +kubebuilder:validation:Minimum=1
    // +kubebuilder:validation:Maximum=10
    Size int32 `json:"size"`

    // Name of the ConfigMap for GuestbookSpec's configuration
    // +kubebuilder:validation:MaxLength=15
    // +kubebuilder:validation:MinLength=1
    ConfigMapName string `json:"configMapName"`

    // +kubebuilder:validation:Enum=Phone;Address;Name
    Type string `json:"alias,omitempty"`
}

// GuestbookStatus defines the observed state of Guestbook
type GuestbookStatus struct {
    // INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
    // Important: Run "make" to regenerate code after modifying this file

    // PodName of the active Guestbook node.
    Active string `json:"active"`

    // PodNames of the standby Guestbook nodes.
    Standby []string `json:"standby"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster

// Guestbook is the Schema for the guestbooks API
type Guestbook struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitempty"`

    Spec   GuestbookSpec   `json:"spec,omitempty"`
    Status GuestbookStatus `json:"status,omitempty"`
}
```

# 3. troubleshooting

## 3.1. controller-gen: No such file or directory

```bash
➜  operator-example kubebuilder init --domain github.com --license apache2 --owner "Hu Weihuang"
Writing scaffold for you to edit...
Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.5.0
Update go.mod:
$ go mod tidy
Running make:
$ make
go: creating new go.mod: module tmp
go: finding sigs.k8s.io v0.2.5
go: finding sigs.k8s.io/controller-tools/cmd v0.2.5
go: finding sigs.k8s.io/controller-tools/cmd/controller-gen v0.2.5
/Users/weihuanghu/go:/Users/weihuanghu/k8spath/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
/bin/sh: /Users/weihuanghu/go:/Users/weihuanghu/k8spath/bin/controller-gen: No such file or directory
make: *** [generate] Error 127
2020/04/13 14:34:47 failed to initialize project: exit status 2
```

由于本地存在多个GOPATH的目录，而获取了非当前项目下的GOPATH目录，因此将当前项目所在的GOPATH目录export到GOPATH环境变量中，就可以解决。

```bash
export GOPATH="/path/to/gopath"
```

参考：

- https://kubernetes.io/zh/docs/concepts/extend-kubernetes/operator/
- https://github.com/kubernetes-sigs/kubebuilder
- https://book.kubebuilder.io/quick-start.html
- https://operatorhub.io/
- https://devops.college/developing-kubernetes-operator-is-now-easy-with-operator-framework-d3194a7428ff
