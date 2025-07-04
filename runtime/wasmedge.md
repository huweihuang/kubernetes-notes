---
title: "WasmEdge介绍"
weight: 7
catalog: true
date: 2021-09-17 21:02:24
subtitle:
header-img: "https://res.cloudinary.com/dqxtn0ick/image/upload/v1508253812/header/cow.jpg"
tags:
- Kubernetes
- Runtime
catagories:
- Kubernetes
---

# 1. Wasm（WebAssembly）是什么

Wasm，全称为WebAssembly，是基于堆栈的虚拟机的**二进制指令格式**。Wasm被设计为编程语言的可移植编译目标，支持在Web上部署客户端和服务器应用程序。

WebAssembly的主要目标是提供一种**可移植、高效、安全的执行环境**，以在Web浏览器中运行各种编程语言的代码。**它不依赖于特定的硬件或操作系统**，WebAssembly允许开发人员使用多种编程语言，例如C、C++、Rust等，通过编译成Wasm字节码来在Web上运行。

Wasm的特点：

1. **高效性能**：Wasm被设计为高效执行，并且与底层系统硬件紧密关联，使其在Web浏览器中可以获得接近本机代码的性能。

2. **安全性**：Wasm是一种隔离的执行环境，它运行在浏览器的沙箱中，具有严格的安全性措施，确保Wasm代码不能直接访问Web浏览器的敏感资源和功能。

3. **可移植性**：由于Wasm是一种独立于平台的中间表示，因此可以在各种设备和操作系统上运行，从桌面计算机到移动设备。

4. **语言无关性**：Wasm允许使用多种编程语言编写代码，而不仅限于JavaScript。这为开发人员提供了更多的灵活性，使得在Web上运行高性能应用程序变得更加容易。

一句话来概括：

**Wasm是一种可移植、高效、安全、跨语言的二进制编码格式。它支持在客户端（浏览器）和服务端运行应用程序。**

# 2. WasmEdge是什么

**WasmEdge 是一个轻量级、高性能和可扩展的 WebAssembly 运行时**。它是当今最快的Wasm VM。适用于云原生、边缘和去中心化应用程序。它为serverless应用程序、嵌入式功能、微服务、智能合约和 IoT 设备提供支持。

# 3. 如何将golang编译成wasm并运行

代码如下：

```go
package main

func main() {
  println("Hello TinyGo from WasmEdge!")
}
```

## 3.1. 编译wasm二进制

**使用tinygo编译**

安装tinygo

> ubuntu系统

```bash
wget https://github.com/tinygo-org/tinygo/releases/download/v0.28.1/tinygo_0.28.1_amd64.deb
sudo dpkg -i tinygo_0.28.1_amd64.deb
```

tinygo编译

```go
tinygo build -o hello.wasm -target wasm main.go
```

## 3.2. 运行wasm二进制

安装wasmedge，参考：https://wasmedge.org/docs/start/install

```bash
wget -qO- https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash -s -- -p /usr/local
```

运行wasm二进制

参考：

[Go - WasmEdge Runtime]([Go - WasmEdge Runtime](https://wasmedge.org/book/zh/dev/go.html))

```bash
# wasmedge hello.wasm
Hello TinyGo from WasmEdge!
```

## 3.3. 性能提升

要为这些应用程序达到原生 Go 性能，你可以使用 `wasmedgec` 命令来 AOT 编译 `wasm` 程序，然后使用 `wasmedge` 命令运行它。

```bash
$ wasmedgec hello.wasm hello.wasm

$ wasmedge hello.wasm
Hello TinyGo from WasmEdge!
```

# 4. 如何构建wasm的容器镜像

安装buildah，参考：https://github.com/containers/buildah/blob/main/install.md

```bash
sudo apt-get -y update
sudo apt-get -y install buildah
```

步骤如下：

1. 编译wasm二进制

2. 编写dockerfile，例如：
   
   ```
   FROM scratch
   
   COPY hello.wasm /
   
   CMD ["/hello.wasm"]
   ```

3. 使用buildah构建和发布镜像。
   
   ```bash
   buildah build --annotation "module.wasm.image/variant=compat-smart" -t wasm-hello .
   ```



参考：

- https://webassembly.org/

- https://github.com/WasmEdge/WasmEdge

- https://github.com/second-state/wasmedge-containers-examples

- https://github.com/second-state/wasmedge-containers-examples/blob/main/simple_wasi_app-zh.md

- https://wasmedge.org/docs/develop/deploy/cri-runtime/containerd-crun

- https://wasmedge.org/docs/develop/go/hello_world

- [Manage WebAssembly Apps Using Container and Kubernetes Tools](https://www.secondstate.io/articles/manage-webassembly-apps-in-wasmedge-using-docker-tools/)


