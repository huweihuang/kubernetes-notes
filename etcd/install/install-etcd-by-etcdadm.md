---
title: "使用etcdadm部署Etcd集群"
date: 2021-6-23 16:22:24
weight: 1
---

## 1. 安装etcdadm

在[Releases · kubernetes-sigs/etcdadm · GitHub](https://github.com/kubernetes-sigs/etcdadm/releases)中选择需要部署的版本，示例如下：

```bash
wget https://github.com/kubernetes-sigs/etcdadm/releases/download/v0.1.5/etcdadm-linux-amd64
mv etcdadm-linux-amd64 /usr/bin/etcdadm
chmod +x /usr/bin/etcdadm
```

## 2. 部署etcd集群

### 2.1. init

etcd的版本可以在 [Releases · etcd-io/etcd · GitHub](https://github.com/etcd-io/etcd/releases) 中查询。

```bash
etcdadm init --name <node1> --version=3.5.4
```

### 2.2. 上传证书到其他机器

```bash
# 登录node2 node3
mkdir -p /etc/etcd/pki

# 将node1的/etc/etcd/pki/ca.* 拷贝到node2 node3 /etc/etcd/pki/
scp /etc/etcd/pki/ca.* node2:/etc/etcd/pki/
```

### 2.3. join

```bash
etcdadm join https://<node1>:2379 --name=<node2> --version=3.5.4
etcdadm join https://<node1>:2379 --name=<node3> --version=3.5.4
```

## 3. 查看集群状态

设置etcdctl环境变量

```bash
# 添加endpoint
cat >> /etc/etcd/etcdctl.env << EOF
export ETCDCTL_ENDPOINTS=node1:2379,node2:2379,node2:2379
EOF

# 拷贝命令脚本到/usr/bin/
cp /opt/bin/etcdctl /opt/bin/etcdctl.sh /usr/bin/
```

查看集群状态

```bash
$ etcdctl.sh endpoint status -w table
+--------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|      ENDPOINT      |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+--------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| node1:2379 | 5fe84cb4a0ef4e69 |   3.5.4 |   20 kB |      true |      false |         3 |         13 |                 13 |        |
| node2:2379 | cb8d48da0ea9b8c0 |   3.5.4 |   20 kB |     false |      false |         3 |         13 |                 13 |        |
| node3:2379 | fafa80c55eebeffa |   3.5.4 |   20 kB |     false |      false |         3 |         13 |                 13 |        |
+--------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
```

## 4. Etcd启动配置文件

systemd service

```bash
# cat /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos/etcd
Conflicts=etcd-member.service
Conflicts=etcd2.service

[Service]
EnvironmentFile=/etc/etcd/etcd.env
ExecStart=/opt/bin/etcd

Type=notify
TimeoutStartSec=0
Restart=on-failure
RestartSec=5s

LimitNOFILE=65536
Nice=-10
IOSchedulingClass=best-effort
IOSchedulingPriority=2
MemoryLow=200M

[Install]
WantedBy=multi-user.target
```

/etc/etcd/etcd.env

```bash
ETCD_NAME=etcd01

# Initial cluster configuration
ETCD_INITIAL_CLUSTER=etcd01=https://node1:2380
ETCD_INITIAL_CLUSTER_TOKEN=88ad6def
ETCD_INITIAL_CLUSTER_STATE=new

# Peer configuration
ETCD_INITIAL_ADVERTISE_PEER_URLS=https://node1:2380
ETCD_LISTEN_PEER_URLS=https://node1:2380

ETCD_CLIENT_CERT_AUTH=true
ETCD_PEER_CERT_FILE=/etc/etcd/pki/peer.crt
ETCD_PEER_KEY_FILE=/etc/etcd/pki/peer.key
ETCD_PEER_TRUSTED_CA_FILE=/etc/etcd/pki/ca.crt

# Client/server configuration
ETCD_ADVERTISE_CLIENT_URLS=https://node1:2379
ETCD_LISTEN_CLIENT_URLS=https://node1:2379,https://127.0.0.1:2379

ETCD_PEER_CLIENT_CERT_AUTH=true
ETCD_CERT_FILE=/etc/etcd/pki/server.crt
ETCD_KEY_FILE=/etc/etcd/pki/server.key
ETCD_TRUSTED_CA_FILE=/etc/etcd/pki/ca.crt

# Other
ETCD_DATA_DIR=/var/lib/etcd
ETCD_STRICT_RECONFIG_CHECK=true
GOMAXPROCS=48
```

参考：

- [GitHub - kubernetes-sigs/etcdadm](https://github.com/kubernetes-sigs/etcdadm)

- [Clustering Guide | etcd](https://etcd.io/docs/v3.5/op-guide/clustering/)
