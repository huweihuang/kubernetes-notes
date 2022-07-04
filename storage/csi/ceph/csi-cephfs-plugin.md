# 1. 编译CSI CephFS plugin

CSI CephFS plugin用来提供CephFS存储卷和挂载存储卷，源码参考：<https://github.com/ceph/ceph-csi> 。

## 1.1. 编译二进制
```bash
$ make cephfsplugin
```

## 1.2. 编译Docker镜像

```bash
$ make image-cephfsplugin
```

# 2. 配置项

## 2.1. 命令行参数

| Option            | Default value         | Description                                                  |
| ----------------- | --------------------- | ------------------------------------------------------------ |
| `--endpoint`      | `unix://tmp/csi.sock` | CSI endpoint, must be a UNIX socket                          |
| `--drivername`    | `csi-cephfsplugin`    | name of the driver (Kubernetes: `provisioner` field in StorageClass must correspond to this value) |
| `--nodeid`        | *empty*               | This node’s ID                                               |
| `--volumemounter` | *empty*               | default volume mounter. Available options are `kernel` and `fuse`. This is the mount method used if volume parameters don’t specify otherwise. If left unspecified, the driver will first probe for `ceph-fuse` in system’s path and will choose Ceph kernel client if probing failed. |

## 2.2. volume参数

| Parameter                                                    | Required                    | Description                                                  |
| ------------------------------------------------------------ | --------------------------- | ------------------------------------------------------------ |
| `monitors`                                                   | yes                         | Comma separated list of Ceph monitors (e.g. `192.168.100.1:6789,192.168.100.2:6789,192.168.100.3:6789`) |
| `mounter`                                                    | no                          | Mount method to be used for this volume. Available options are `kernel` for Ceph kernel client and `fuse` for Ceph FUSE driver. Defaults to “default mounter”, see command line arguments. |
| `provisionVolume`                                            | yes                         | Mode of operation. BOOL value. If `true`, a new CephFS volume will be provisioned. If `false`, an existing CephFS will be used. |
| `pool`                                                       | for `provisionVolume=true`  | Ceph pool into which the volume shall be created             |
| `rootPath`                                                   | for `provisionVolume=false` | Root path of an existing CephFS volume                       |
| `csiProvisionerSecretName`, `csiNodeStageSecretName`         | for Kubernetes              | name of the Kubernetes Secret object containing Ceph client credentials. Both parameters should have the same value |
| `csiProvisionerSecretNamespace`, `csiNodeStageSecretNamespace` | for Kubernetes              | namespaces of the above Secret objects                       |

## 2.3. provisionVolume

### 2.3.1. 管理员密钥认证

当**provisionVolume=true**时，必要的管理员认证参数如下：

- `adminID`: ID of an admin client
- `adminKey`: key of the admin client

### 2.3.2. 普通用户密钥认证

当**provisionVolume=false**时，必要的用户认证参数如下：

- `userID`: ID of a user client
- `userKey`: key of a user client

参考文章：

- https://github.com/ceph/ceph-csi/blob/master/docs/deploy-cephfs.md
