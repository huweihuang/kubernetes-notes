# 1. Ubuntu安装containerd

以下以Ubuntu为例

> 说明：安装containerd与安装docker流程基本一致，差别在于不需要安装docker-ce
> 
> - `containerd`: apt-get install -y containerd.io
> - `docker`: apt-get install docker-ce docker-ce-cli containerd.io

## 1. 卸载旧版本

```bash
 sudo apt-get remove docker docker-engine docker.io containerd runc
```

如果需要删除镜像及容器数据则执行以下命令

```bash
 sudo rm -rf /var/lib/docker
 sudo rm -rf /var/lib/containerd
```

## 2. 准备包环境

1、更新apt，允许使用https。

```bash
 sudo apt-get update
 sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```

2、添加docker官方GPG key。

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

3、设置软件仓库源

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

## 3. 安装containerd

```bash
# 安装containerd
sudo apt-get update
sudo apt-get install -y containerd.io

# 如果是安装docker则执行：
sudo apt-get install docker-ce docker-ce-cli containerd.io

# 查看运行状态
systemctl enable containerd
systemctl status containerd
```

安装指定版本

```bash
# 查看版本
apt-cache madison containerd

# sudo apt-get install containerd=<VERSION>
```

## 4. 修改配置

在 Linux 上，containerd 的默认 CRI 套接字是 `/run/containerd/containerd.sock`。

1、生成默认配置

```bash
containerd config default > /etc/containerd/config.toml
```

2、修改CgroupDriver为systemd

k8s官方推荐使用systemd类型的CgroupDriver。

```bash
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```

3、重启containerd

```bash
systemctl restart containerd
```

# 2. 离线二进制安装containerd

把`containerd`、`runc`、`cni-plugins`、`nerdctl`二进制下载到本地，再上传到对应服务器，解压文件到对应目录，修改containerd配置文件，启动containerd。

```bash
#!/bin/bash
set -e

ContainerdVersion=$1
ContainerdVersion=${ContainerdVersion:-1.6.6}

RuncVersion=$2
RuncVersion=${RuncVersion:-1.1.3}

CniVersion=$3
CniVersion=${CniVersion:-1.1.1}

NerdctlVersion=$4
NerdctlVersion=${NerdctlVersion:-0.21.0}

CrictlVersion=$5
CrictlVersion=${CrictlVersion:-1.24.2}

echo "--------------install containerd--------------"
wget https://github.com/containerd/containerd/releases/download/v${ContainerdVersion}/containerd-${ContainerdVersion}-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-${ContainerdVersion}-linux-amd64.tar.gz

echo "--------------install containerd service--------------"
wget https://raw.githubusercontent.com/containerd/containerd/681aaf68b7dcbe08a51c3372cbb8f813fb4466e0/containerd.service
mv containerd.service /lib/systemd/system/

mkdir -p /etc/containerd/
containerd config default > /etc/containerd/config.toml

echo "--------------install runc--------------"
wget https://github.com/opencontainers/runc/releases/download/v${RuncVersion}/runc.amd64
chmod +x runc.amd64
mv runc.amd64 /usr/local/bin/runc

echo "--------------install cni plugins--------------"
wget https://github.com/containernetworking/plugins/releases/download/v${CniVersion}/cni-plugins-linux-amd64-v${CniVersion}.tgz
rm -fr /opt/cni/bin
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v${CniVersion}.tgz

echo "--------------install nerdctl--------------"
wget https://github.com/containerd/nerdctl/releases/download/v${NerdctlVersion}/nerdctl-${NerdctlVersion}-linux-amd64.tar.gz
tar Cxzvf /usr/local/bin nerdctl-${NerdctlVersion}-linux-amd64.tar.gz

echo "--------------install crictl--------------"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CrictlVersion}/crictl-v${CrictlVersion}-linux-amd64.tar.gz
tar Cxzvf /usr/local/bin crictl-v${CrictlVersion}-linux-amd64.tar.gz

# 启动containerd服务
systemctl daemon-reload
systemctl restart contaienrd
```

参考：

- https://github.com/containerd/containerd

- https://github.com/containerd/containerd/blob/main/docs/getting-started.md

- https://docs.docker.com/engine/install/ubuntu/

- https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

- [containerd/containerd.service at main · containerd/containerd · GitHub](https://github.com/containerd/containerd/blob/main/containerd.service)

- [GitHub - containerd/nerdctl: containerd ctl ](https://github.com/containerd/nerdctl)

- [GitHub - kubernetes-sigs/cri-tools: CLI and validation tools for Kubelet Container Runtime Interface (CRI) .](https://github.com/kubernetes-sigs/cri-tools)