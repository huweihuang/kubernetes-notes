常见镜像拉取问题排查

## 1. Pod状态为ErrImagePull或ImagePullBackOff

```bash
docker-hub-75d4dfb984-5hggg           0/1     ImagePullBackOff   0          14m     192.168.1.30   <node ip>   
docker-hub-75d4dfb984-9r57b           0/1     ErrImagePull       0          53s     192.168.0.42   <node ip>   
```

- ErrImagePull：表示pod已经调度到node节点，kubelet调用docker去拉取镜像失败。
- ImagePullBackOff：表示kubelet拉取镜像失败后，不断重试去拉取仍然失败。

## 2. 查看pod的事件

通过kubectl describe pod 命令查看pod事件，该事件的报错信息在kubelet或docker的日志中也会查看到。

### 2.1. http: server gave HTTP response to HTTPS client

如果遇到以下报错，尝试将该镜像仓库添加到docker可信任的镜像仓库配置中。

```bash
Error getting v2 registry: Get https://docker.com:8080/v2/: http: server gave HTTP response to HTTPS client"
```

具体操作是修改/etc/docker/daemon.json的insecure-registries参数

```bash
#cat /etc/docker/daemon.json
{
	...
  "insecure-registries": [
	...
    "docker.com:8080"
  ],
  ...
}
```

### 2.2. no basic auth credentials

如果遇到`no basic auth credentials`报错，说明kubelet调用docker接口去拉取镜像时，镜像仓库的认证信息失败。

```bash
  Normal   BackOff    18s               kubelet, 192.168.1.1  Back-off pulling image "docker.com:8080/public/2048:latest"
  Warning  Failed     18s               kubelet, 192.168.1.1  Error: ImagePullBackOff
  Normal   Pulling    5s (x2 over 18s)  kubelet, 192.168.1.1  Pulling image "docker.com:8080/public/2048:latest"
  Warning  Failed     5s (x2 over 18s)  kubelet, 192.168.1.1  Failed to pull image "docker.com:8080/public/2048:latest": rpc error: code = Unknown desc = Error response from daemon: Get http://docker.com:8080/v2/public/2048/manifests/latest: no basic auth credentials
  Warning  Failed     5s (x2 over 18s)  kubelet, 192.168.1.1  Error: ErrImagePull
```

具体操作，在拉取镜像失败的节点上登录该镜像仓库，认证信息会更新到` $HOME/.docker/config.json`文件中。将该文件拷贝到`/var/lib/kubelet/config.json`中。

