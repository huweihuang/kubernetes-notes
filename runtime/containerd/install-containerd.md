# Ubuntu安装containerd

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
# 生成默认配置
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





参考：

- https://github.com/containerd/containerd

- https://github.com/containerd/containerd/blob/main/docs/getting-started.md

- https://docs.docker.com/engine/install/ubuntu/

- https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd