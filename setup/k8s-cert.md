# 1. 证书分类

- 服务器证书：server cert，用于客户端验证服务端的身份。

- 客户端证书：client cert，用于服务端验证客户端的身份。

- 对等证书：peer cert（既是`server cert`又是`client cert`），用户成员之间的身份验证，例如 etcd。

## 1.1. k8s集群的证书分类

- `etcd节点`：需要标识自己服务的`server cert`，也需要`client cert`与`etcd`集群其他节点交互，因此需要一个对等证书。
- `master节点`：需要标识 apiserver服务的`server cert`，也需要`client cert`连接`etcd`集群，也需要一个对等证书。
- `kubelet`：需要标识自己服务的`server cert`，也需要`client cert`请求`apiserver`，也使用一个对等证书。
- `kubectl、kube-proxy、calico`：需要client证书。

# 2. CA证书及秘钥

目录：`/etc/kubernetes/ssl`

| 分类       | 证书/秘钥          | 说明 | 组件 |
| ---------- | ------------------ | ---- | ---- |
| ca         | ca-key.pem         |      |      |
|            | ca.pem             |      |      |
|            | ca.csr             |      |      |
| Kubernetes | kubernetes-key.pem |      |      |
|            | kubernetes.pem     |      |      |
|            | kubernetes.csr     |      |      |
| Admin      | admin-key.pem      |      |      |
|            | admin.pem          |      |      |
|            | admin.csr          |      |      |
| Kubelet    | kubelet.crt        |      |      |
|            | kubelet.key        |      |      |

配置文件

| 分类       | 证书/秘钥           | 说明 |
| ---------- | ------------------- | ---- |
| ca         | ca-config.json      |      |
|            | ca-csr.json         |      |
| Kubernetes | kubernetes-csr.json |      |
| Admin      | admin-csr.json      |      |
| Kube-proxy | kube-proxy-csr.json |      |

# 3. cfssl工具

安装cfssl：

```bash
# 下载cfssl
$ curl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o /usr/local/bin/cfssl
$ curl https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o /usr/local/bin/cfssljson
$ curl https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -o /usr/local/bin/cfssl-certinfo

# 添加可执行权限
$ chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson /usr/local/bin/cfssl-certinfo
```

# 4. 创建 CA (Certificate Authority)

## 4.1. 配置源文件

**创建 CA 配置文件**

**ca-config.json**

```json
cat << EOF > ca-config.json
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF
```

**参数说明**

- `ca-config.json`：可以定义多个 profiles，分别指定不同的过期时间、使用场景等参数；后续在签名证书时使用某个 profile；
- `signing`：表示该证书可用于签名其它证书；生成的 ca.pem 证书中 `CA=TRUE`；
- `server auth`：表示client可以用该 CA 对server提供的证书进行验证；
- `client auth`：表示server可以用该CA对client提供的证书进行验证；

**创建 CA 证书签名请求**

**ca-csr.json**

```bash
cat << EOF > ca-csr.json
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShenZhen",
      "L": "ShenZhen",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
```

**参数说明**

ca-csr.json的参数

- CN：`Common Name`，kube-apiserver 从证书中提取该字段作为请求的用户名 (User Name)；浏览器使用该字段验证网站是否合法；

names中的字段：

- C : country，国家
- ST: state，州或省份
- L：location，城市
- O：organization，组织，kube-apiserver 从证书中提取该字段作为请求用户所属的组 (Group)
- OU：organization unit

## 4.2. 执行命令

```bash
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

输出如下：

```bash
# cfssl gencert -initca ca-csr.json | cfssljson -bare ca
2019/12/13 14:35:52 [INFO] generating a new CA key and certificate from CSR
2019/12/13 14:35:52 [INFO] generate received request
2019/12/13 14:35:52 [INFO] received CSR
2019/12/13 14:35:52 [INFO] generating key: rsa-2048
2019/12/13 14:35:52 [INFO] encoded CSR
2019/12/13 14:35:52 [INFO] signed certificate with serial number 248379771349454958117219047414671162179070747780
```

生成以下文件：

```bash
# 生成文件
-rw-r--r-- 1 root root 1005 12月 13 11:32 ca.csr
-rw------- 1 root root 1675 12月 13 11:32 ca-key.pem
-rw-r--r-- 1 root root 1363 12月 13 11:32 ca.pem
# 配置源文件
-rw-r--r-- 1 root root  293 12月 13 11:31 ca-config.json
-rw-r--r-- 1 root root  210 12月 13 11:31 ca-csr.json
```

# 5. 创建 kubernetes 证书

## 5.1. 配置源文件

创建 kubernetes 证书签名请求文件kubernetes-csr.json。

```yaml
cat << EOF > kubernetes-csr.json
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "<MASTER_IP>",
    "<MASTER_CLUSTER_IP>", 
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
    "C": "<country>",
    "ST": "<state>",
    "L": "<city>",
    "O": "<organization>",
    "OU": "<organization unit>"
  }]
}
EOF
```

参数说明：

- `MASTER_IP`：master节点的IP或域名
- `MASTER_CLUSTER_IP`：`kube-apiserver` 指定的 `service-cluster-ip-range` 网段的第一个IP，例如（10.254.0.1）。

## 5.2. 执行命令

```bash
$ cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
```

输出如下：

```bash
# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
2019/12/13 14:40:28 [INFO] generate received request
2019/12/13 14:40:28 [INFO] received CSR
2019/12/13 14:40:28 [INFO] generating key: rsa-2048
2019/12/13 14:40:28 [INFO] encoded CSR
2019/12/13 14:40:28 [INFO] signed certificate with serial number 392795299385191732458211386861696542628305189374
2019/12/13 14:40:28 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
```

生成以下文件：

```bash
# 生成文件
-rw-r--r-- 1 root root 1269 12月 13 14:40 kubernetes.csr
-rw------- 1 root root 1679 12月 13 14:40 kubernetes-key.pem
-rw-r--r-- 1 root root 1643 12月 13 14:40 kubernetes.pem
# 配置源文件
-rw-r--r-- 1 root root  580 12月 13 14:40 kubernetes-csr.json
```

# 6. 创建 admin 证书

## 6.1. 配置源文件

创建 admin 证书签名请求文件 `admin-csr.json`：

```bash
cat << EOF > admin-csr.json
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShenZhen",
      "L": "ShenZhen",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
```

## 6.2. 执行命令

```bash
$ cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
```

输出如下：

```bash
# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
2019/12/13 14:52:37 [INFO] generate received request
2019/12/13 14:52:37 [INFO] received CSR
2019/12/13 14:52:37 [INFO] generating key: rsa-2048
2019/12/13 14:52:37 [INFO] encoded CSR
2019/12/13 14:52:37 [INFO] signed certificate with serial number 465422983473444224050765004141217688748259757371
2019/12/13 14:52:37 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
```

生成文件

```bash
# 生成文件
-rw-r--r-- 1 root root 1013 12月 13 14:52 admin.csr
-rw------- 1 root root 1675 12月 13 14:52 admin-key.pem
-rw-r--r-- 1 root root 1407 12月 13 14:52 admin.pem
# 配置源文件
-rw-r--r-- 1 root root  231 12月 13 14:49 admin-csr.json
```

# 7. 创建 kube-proxy 证书

## 7.1. 配置源文件

创建 kube-proxy 证书签名请求文件 `kube-proxy-csr.json`：

```yaml
cat << EOF > kube-proxy-csr.json
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
```

## 7.2. 执行命令

```bash
$ cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
```

输出如下：

```bash
# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
2019/12/13 19:37:48 [INFO] generate received request
2019/12/13 19:37:48 [INFO] received CSR
2019/12/13 19:37:48 [INFO] generating key: rsa-2048
2019/12/13 19:37:48 [INFO] encoded CSR
2019/12/13 19:37:48 [INFO] signed certificate with serial number 526712749765692443642491255093816136154324531741
2019/12/13 19:37:48 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
```

生成文件：

```bash
# 生成文件
-rw-r--r-- 1 root root 1009 12月 13 19:37 kube-proxy.csr
-rw------- 1 root root 1675 12月 13 19:37 kube-proxy-key.pem
-rw-r--r-- 1 root root 1407 12月 13 19:37 kube-proxy.pem
# 配置源文件
-rw-r--r-- 1 root root  230 12月 13 19:37 kube-proxy-csr.json
```

# 8. 校验证书

```bash
openssl x509  -noout -text -in  kubernetes.pem
```

输出如下：

```bash
# openssl x509  -noout -text -in  kubernetes.pem
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            44:cd:8c:e6:a4:60:ff:3f:09:af:02:e7:68:5e:f2:0f:e6:a0:39:fe
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=CN, ST=ShenZhen, L=ShenZhen, O=k8s, OU=System, CN=kubernetes
        Validity
            Not Before: Dec 13 06:35:00 2019 GMT
            Not After : Nov 19 06:35:00 2119 GMT
        Subject: C=CN, ST=ShenZhen, L=ShenZhen, O=k8s, OU=System, CN=kubernetes
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                Public-Key: (2048 bit)
                Modulus:
                    00:d7:91:4f:90:56:fb:ab:a9:de:c4:98:9e:d7:e6:
                    45:db:5a:14:9a:76:78:6a:4c:db:3c:47:3c:e7:1c:
                    3c:37:4e:8a:cf:9c:a1:8a:4c:51:4c:cd:45:b0:03:
                    87:06:b9:20:2c:3a:51:f9:21:55:1c:90:7c:f8:93:
                    bc:6a:48:05:3d:8b:74:fd:f2:f1:e6:5e:ad:b4:a8:
                    f6:6d:f9:63:9e:e4:b4:cc:68:9e:90:d7:ef:de:ce:
                    c1:1d:1b:68:59:68:5e:5f:7d:5c:f3:49:4f:18:72:
                    be:b5:c8:af:e2:8d:34:9c:d2:68:b7:8c:26:69:cc:
                    a5:f4:ca:69:2d:d7:21:f5:19:2e:b2:b5:97:16:87:
                    9f:9c:fd:01:97:c2:0e:20:b4:88:27:9a:37:9a:af:
                    0a:cf:82:4f:26:24:cb:07:ac:8c:b1:34:20:42:22:
                    00:b2:b0:98:c5:53:01:fb:32:aa:15:1b:7e:39:44:
                    ae:af:6e:c3:65:96:f6:38:7a:87:37:d0:31:63:d8:
                    a4:15:13:f2:56:da:e6:09:45:2b:46:2c:cb:63:db:
                    f7:ba:7f:44:0a:36:39:7c:cc:5b:42:e5:56:c7:7f:
                    dd:64:5c:f2:4a:af:d3:a9:d1:6e:06:27:57:09:4d:
                    db:08:62:87:66:c8:2c:36:00:41:f1:90:f6:5f:68:
                    20:3d
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature, Key Encipherment
            X509v3 Extended Key Usage:
                TLS Web Server Authentication, TLS Web Client Authentication
            X509v3 Basic Constraints: critical
                CA:FALSE
            X509v3 Subject Key Identifier:
                3D:3F:FA:B8:36:D7:FE:B1:59:BE:B1:F5:C1:5D:88:3D:BC:78:9F:87
            X509v3 Authority Key Identifier:
                keyid:40:A2:D4:30:22:12:2E:C2:FB:A2:55:2C:CB:F0:F6:3E:4D:B8:02:03

            X509v3 Subject Alternative Name:
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster, DNS:kubernetes.default.svc.cluster.local, IP Address:127.0.0.1, IP Address:172.20.0.112, IP Address:172.20.0.113, IP Address:172.20.0.114, IP Address:172.20.0.115, IP Address:10.254.0.1
    Signature Algorithm: sha256WithRSAEncryption
         63:50:f6:2a:03:c7:35:dd:e9:10:8d:2f:b3:27:9a:64:f3:e1:
         11:8a:18:1e:fa:6d:85:30:11:b4:59:a3:6c:86:cd:2b:5c:67:
         17:4f:aa:0d:bb:4c:ee:c8:af:e7:3d:61:6d:03:9d:14:6f:00:
         48:56:59:b5:76:13:a9:30:23:e0:b2:d2:12:64:0c:60:0d:76:
         ec:c6:4f:b1:bc:24:01:7a:48:c6:fd:9e:5d:68:da:b9:a1:ad:
         30:7a:ba:90:e2:e3:4e:b4:92:1b:c5:f2:8c:c1:b0:3d:fc:14:
         d2:46:e8:f8:22:8f:d9:4d:85:4f:58:6b:0f:84:78:06:b4:b9:
         92:b9:0d:bd:1d:95:e9:0d:42:d3:fd:dd:2a:59:60:3f:63:35:
         eb:07:25:d2:ea:0d:19:a6:f3:dc:92:8e:ee:73:04:15:5e:97:
         e8:da:51:c3:69:49:96:36:c7:cc:5b:e5:e5:cb:e5:ce:9f:21:
         6f:6b:56:16:bf:85:ad:1c:8c:91:c1:91:0a:90:18:e2:4a:b0:
         32:58:33:ef:55:8e:8f:4a:e3:0f:b8:f7:41:04:65:89:e1:1b:
         d8:41:28:6e:84:c3:1c:8e:a9:a0:8a:42:e4:fe:d7:fe:0e:24:
         dc:74:37:fa:5e:be:20:69:c5:9a:5a:e6:83:1c:0b:9e:e1:43:
         ef:4f:7a:37
```

字段说明：

- 确认 `Issuer` 字段的内容和 `ca-csr.json` 一致；
- 确认 `Subject` 字段的内容和 `kubernetes-csr.json` 一致；
- 确认 `X509v3 Subject Alternative Name` 字段的内容和 `kubernetes-csr.json` 一致；
- 确认 `X509v3 Key Usage、Extended Key Usage` 字段的内容和 `ca-config.json` 中 `kubernetes` profile 一致；

# 9. 分发证书

将生成的证书和秘钥文件（后缀名为`.pem`）拷贝到所有机器的 `/etc/kubernetes/ssl` 目录下。

```bash
mkdir -p /etc/kubernetes/ssl
cp *.pem /etc/kubernetes/ssl
```





参考文章：

- https://kubernetes.io/docs/concepts/cluster-administration/certificates/
- https://coreos.com/os/docs/latest/generate-self-signed-certificates.html
- https://jimmysong.io/kubernetes-handbook/practice/create-tls-and-secret-key.html