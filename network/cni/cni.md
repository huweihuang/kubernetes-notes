# 1. CNI（Container Network Interface）

CNI（Container Network Interface）即容器网络接口，通过约定统一的容器网络接口，从而kubelet可以通过这个标准的API来调用不同的网络插件实现不同的网络功能。

kubelet启动参数--network-plugin=cni来指定CNI插件，kubelet从`--cni-conf-dir` （默认是 `/etc/cni/net.d`） 读取文件并使用 该文件中的 CNI 配置来设置各个 Pod 的网络。 CNI 配置文件必须与 [CNI 规约](https://github.com/containernetworking/cni/blob/master/SPEC.md#network-configuration) 匹配，并且配置所引用的所有所需的 CNI 插件都应存在于 `--cni-bin-dir`（默认是 `/opt/cni/bin`）下。如果有多个CNI配置文件，kubelet 将会使用按文件名的字典顺序排列 的第一个作为配置文件。

CNI规范定义：

- 网络配置文件的格式

- 容器runtime与CNI插件的通信协议

- 基于提供的配置执行网络插件的步骤

- 网络插件调用其他功能插件的步骤

- 插件返回给runtime结果的数据格式

# 2. CNI配置文件格式

CNI配置文件的格式为JSON格式，配置文件的默认路径：/etc/cni/net.d。插件二进制默认的路径为：/opt/cni/bin。

## 2.1. 主配置的字段

- `cniVersion` (string)：CNI规范使用的版本，例如版本为0.4.0。

- `name` (string)：目标网络的名称。

- `disableCheck` (boolean)：关闭CHECK操作。

- `plugins` (list)：CNI插件列表及插件配置。

## 2.2. 插件配置字段

根据不同的插件，插件配置所需的字段不同。

必选字段：

- `type` (string)：节点上插件二进制的名称，比如bridge，sriov，macvlan等。

可选字段：

- `capabilities` (dictionary)

- `ipMasq` (boolean)：为目标网络配上Outbound Masquerade(地址伪装)，即：由容器内部通过网关向外发送数据包时，对数据包的源IP地址进行修改。
  
  当我们的容器以宿主机作为网关时，这个参数是必须要设置的。否则，从容器内部发出的数据包就没有办法通过网关路由到其他网段。因为容器内部的IP地址无法被目标网段识别，所以这些数据包最终会被丢弃掉。

- `ipam` (dictionary)：IPAM(IP Adderss Management)即IP地址管理，提供了一系列方法用于对IP和路由进行管理。它对应的是由CNI提供的一组标准IPAM插件，比如像host-local，dhcp，static等。比如文中用到的bridge插件，会调用我们所指定的IPAM插件，实现对网络设备IP地址的分配和管理。**如果是自己开发的ipam插件，则相关的入参可以自己定义和实现。
  
  以下以host-local为例说明。
  
  - type：指定所用IPAM插件的名称，在我们的例子里，用的是host-local。
  - subnet：为目标网络分配网段，包括网络ID和子网掩码，以CIDR形式标记。在我们的例子里为`10.15.10.0/24`，也就是目标网段为`10.15.10.0`，子网掩码为`255.255.255.0`。
  - routes：用于指定路由规则，插件会为我们在容器的路由表里生成相应的规则。其中，dst表示希望到达的目标网段，以CIDR形式标记。gw对应网关的IP地址，也就是要到达目标网段所要经过的“next hop(下一跳)”。如果省略gw的话，那么插件会自动帮我们选择默认网关。在我们的例子里，gw选择的是默认网关，而dst为`0.0.0.0/0`则代表“任何网络”，表示数据包将通过默认网关发往任何网络。实际上，这对应的是一条默认路由规则，即：当所有其他路由规则都不匹配时，将选择该路由。
  - rangeStart：允许分配的IP地址范围的起始值
  - rangeEnd：允许分配的IP地址范围的结束值
  - gateway：为网关（也就是我们将要在宿主机上创建的bridge）指定的IP地址。如果省略的话，那么插件会自动从允许分配的IP地址范围内选择起始值作为网关的IP地址。

- `dns` (dictionary, optional)：dns配置
  
  - `nameservers` (list of strings, optional)
  
  - `domain` (string, optional)
  
  - `search` (list of strings, optional)
  
  - `options` (list of strings, optional)

## 2.3. 配置文件示例

```json
$ mkdir -p /etc/cni/net.d
$ cat >/etc/cni/net.d/10-mynet.conf <<EOF
{
  "cniVersion": "1.0.0",
  "name": "dbnet",
  "plugins": [
    {
      "type": "bridge",
      // plugin specific parameters
      "bridge": "cni0",
      "keyA": ["some more", "plugin specific", "configuration"],

      "ipam": {
        "type": "host-local",
        // ipam specific
        "subnet": "10.1.0.0/16",
        "gateway": "10.1.0.1",
        "routes": [
            {"dst": "0.0.0.0/0"}
        ]
      },
      "dns": {
        "nameservers": [ "10.1.0.1" ]
      }
    },
    {
      "type": "tuning",
      "capabilities": {
        "mac": true
      },
      "sysctl": {
        "net.core.somaxconn": "500"
      }
    },
    {
        "type": "portmap",
        "capabilities": {"portMappings": true}
    }
  ]
}
```

# 3. CNI插件

## 3.1. 安装插件

安装CNI二进制插件，插件下载地：https://github.com/containernetworking/plugins/releases

```bash
# 下载二进制
wget https://github.com/containernetworking/plugins/releases/download/v1.1.0/cni-plugins-linux-amd64-v1.1.0.tgz

# 解压文件
tar -zvxf cni-plugins-linux-amd64-v1.1.0.tgz -C /opt/cni/bin/

# 查看解压文件
# ll -h
总用量 63M
-rwxr-xr-x 1 root root 3.7M 2月  24 01:01 bandwidth
-rwxr-xr-x 1 root root 4.1M 2月  24 01:01 bridge
-rwxr-xr-x 1 root root 9.3M 2月  24 01:01 dhcp
-rwxr-xr-x 1 root root 4.2M 2月  24 01:01 firewall
-rwxr-xr-x 1 root root 3.7M 2月  24 01:01 host-device
-rwxr-xr-x 1 root root 3.1M 2月  24 01:01 host-local
-rwxr-xr-x 1 root root 3.8M 2月  24 01:01 ipvlan
-rwxr-xr-x 1 root root 3.2M 2月  24 01:01 loopback
-rwxr-xr-x 1 root root 3.8M 2月  24 01:01 macvlan
-rwxr-xr-x 1 root root 3.6M 2月  24 01:01 portmap
-rwxr-xr-x 1 root root 4.0M 2月  24 01:01 ptp
-rwxr-xr-x 1 root root 3.4M 2月  24 01:01 sbr
-rwxr-xr-x 1 root root 2.7M 2月  24 01:01 static
-rwxr-xr-x 1 root root 3.3M 2月  24 01:01 tuning
-rwxr-xr-x 1 root root 3.8M 2月  24 01:01 vlan
-rwxr-xr-x 1 root root 3.4M 2月  24 01:01 vrf
```

## 3.2. 插件分类

参考：https://www.cni.dev/plugins/current/

| 分类   | 插件                                                                   | 说明                                                                                                     |
| ---- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| main | bridge                                                               | Creates a bridge, adds the host and the container to it                                                |
|      | ipvlan                                                               | Adds an ipvlan interface in the container                                                              |
|      | **macvlan**                                                          | Creates a new MAC address, forwards all traffic to that to the container                               |
|      | ptp                                                                  | Creates a veth pair                                                                                    |
|      | [host-device](https://www.cni.dev/plugins/current/main/host-device/) | Moves an already-existing device into a container                                                      |
|      | vlan                                                                 | Creates a vlan interface off a master                                                                  |
| IPAM | dhcp                                                                 | Runs a daemon on the host to make DHCP requests on behalf of a container                               |
|      | host-local                                                           | Maintains a local database of allocated IPs                                                            |
|      | static                                                               | Allocates static IPv4/IPv6 addresses to containers                                                     |
| meta | tuning                                                               | Changes sysctl parameters of an existing interface                                                     |
|      | portmap                                                              | An iptables-based portmapping plugin. Maps ports from the host’s address space to the container        |
|      | **bandwidth**                                                        | Allows bandwidth-limiting through use of traffic control tbf (ingress/egress)                          |
|      | sbr                                                                  | A plugin that configures source based routing for an interface (from which it is chained)              |
|      | firewall                                                             | A firewall plugin which uses iptables or firewalld to add rules to allow traffic to/from the container |

# 4. CNI插件接口

具体可参考：https://github.com/containernetworking/cni/blob/master/SPEC.md#cni-operations

CNI定义的接口操作有：

- `ADD`：添加容器网络，在容器启动时调用。
- `DEL`：删除容器网络，在容器删除时调用。
- `CHECK`：检查容器网络是否正常。
- `VERSION`：显示插件版本。

这些操作通过`CNI_COMMAND`环境变量来传递给CNI插件二进制。

其中环境变量包括：

- `CNI_COMMAND`：命令操作，包括 `ADD`, `DEL`, `CHECK`, or `VERSION`。

- `CNI_CONTAINERID`:容器的ID，有runtime分配，不为空。

- `CNI_NETNS`:容器的网络命名空间，命名空间路径，例如：/run/netns/[nsname]

- `CNI_IFNAME`:容器内的网卡名称。

- `CNI_ARGS`:其他参数。

- `CNI_PATH`:CNI插件二进制的路径。

## 4.1. ADD接口：添加容器网络

在容器的网络命名空间`CNI_NETNS`中创建`CNI_IFNAME`网卡设备，或者调整网卡配置。

必选参数：

- `CNI_COMMAND`
- `CNI_CONTAINERID`
- `CNI_NETNS`
- `CNI_IFNAME`

可选参数：

- `CNI_ARGS`
- `CNI_PATH`

## 4.2. DEL接口：删除容器网络

删除容器网络命名空间`CNI_NETNS`中的容器网卡`CNI_IFNAME`，或者撤销ADD修改操作。

必选参数：

- `CNI_COMMAND`
- `CNI_CONTAINERID`
- `CNI_IFNAME`

可选参数：

- `CNI_NETNS`
- `CNI_ARGS`
- `CNI_PATH`

## 4.3. CHECK接口：检查容器网络

## 4.4. VERSION接口：输出CNI的版本







参考：

- https://www.cni.dev/docs/spec/
- https://github.com/containernetworking/cni
- https://github.com/containernetworking/cni/blob/spec-v0.4.0/SPEC.md
- https://kubernetes.io/zh/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/
- https://github.com/containernetworking/plugins/tree/master/plugins
- https://www.cni.dev/plugins/current/
- https://cloud.tencent.com/developer/news/600713
- [配置CNI插件](https://morningspace.github.io/tech/k8s-net-cni/#%E9%85%8D%E7%BD%AEcni%E6%8F%92%E4%BB%B6)
