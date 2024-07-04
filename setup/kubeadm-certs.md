---
title: "kubeadm管理证书"
weight: 4
catalog: true
date: 2019-6-23 16:22:24
subtitle:
header-img:
tags:
- kubeadm
catagories:
- kubeadm
---

通过kubeadm搭建的集群**默认的证书时间是1年**（由于官方期望每年更新一次k8s的版本，在更新的时候会默认更新证书），当你执行命令出现以下报错，说明你的证书已经到期了，则需要手动更新证书。

```bash
# kubectl get node
Unable to connect to the server: x509: certificate has expired or is not yet valid: current time 2023-08-03T18:06:23+08:00 is after 2023-07-04T06:30:54Z

# 或者出现以下报错
You must be logged in to the server(unauthorized)
```

以下说明手动更新证书的流程。

具体可以参考：[使用 kubeadm 进行证书管理 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

# 1. 检查证书是否过期

```bash
kubeadm certs check-expiration
```

会输出以下的内容：

```bash
CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Dec 30, 2020 23:36 UTC   364d                                    no
apiserver                  Dec 30, 2020 23:36 UTC   364d            ca                      no
apiserver-etcd-client      Dec 30, 2020 23:36 UTC   364d            etcd-ca                 no
apiserver-kubelet-client   Dec 30, 2020 23:36 UTC   364d            ca                      no
controller-manager.conf    Dec 30, 2020 23:36 UTC   364d                                    no
etcd-healthcheck-client    Dec 30, 2020 23:36 UTC   364d            etcd-ca                 no
etcd-peer                  Dec 30, 2020 23:36 UTC   364d            etcd-ca                 no
etcd-server                Dec 30, 2020 23:36 UTC   364d            etcd-ca                 no
front-proxy-client         Dec 30, 2020 23:36 UTC   364d            front-proxy-ca          no
scheduler.conf             Dec 30, 2020 23:36 UTC   364d                                    no

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Dec 28, 2029 23:36 UTC   9y              no
etcd-ca                 Dec 28, 2029 23:36 UTC   9y              no
front-proxy-ca          Dec 28, 2029 23:36 UTC   9y              no
```

# 2. 手动更新过期的证书

分别在`master节点`执行以下命令。

## 2.1. 备份`/etc/kubernetes`目录

```bash
cp -fr /etc/kubernetes /etc/kubernetes.bak
cp -fr ~/.kube ~/.kube.bak
```

## 2.2. 执行更新证书命令

```bash
kubeadm certs renew all
```

输出如下：

```bash
# kubeadm certs renew all
[renew] Reading configuration from the cluster...
[renew] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
[renew] Error reading configuration from the Cluster. Falling back to default configuration

certificate embedded in the kubeconfig file for the admin to use and for kubeadm itself renewed
certificate for serving the Kubernetes API renewed
certificate the apiserver uses to access etcd renewed
certificate for the API server to connect to kubelet renewed
certificate embedded in the kubeconfig file for the controller manager to use renewed
certificate for liveness probes to healthcheck etcd renewed
certificate for etcd nodes to communicate with each other renewed
certificate for serving etcd renewed
certificate for the front proxy client renewed
certificate embedded in the kubeconfig file for the scheduler manager to use renewed

Done renewing certificates. You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd, so that they can use the new certificates.
```

## 2.3. 重启k8s组件

**先重启etcd**

**注意事项：需要将三个master节点的证书都重新更新后，然后三个master的etcd服务一起重启，使得etcd集群使用新的证书可以正常运行，否则会导致kube-apiserver也启动失败。**

```bash
crictl ps |grep "etcd"|awk '{print $1}'|xargs crictl stop 
```

再重启kube-apiserver、kube-controller、kube-scheduler容器。

```bash
crictl ps |egrep "kube-apiserver|kube-scheduler|kube-controller"|awk '{print $1}'|xargs crictl stop 
```

## 2.4. 更新默认的kubeconfig文件

```bash
cp -fr /etc/kubernetes/admin.conf $HOME/.kube/config
```

## 2.5. 配置kubelet证书轮转

由于kubelet默认支持证书轮转，当证书过期时，可以自动生成新的密钥，并从 Kubernetes API 申请新的证书。可以查看kubelet的配置检查是否已经开启。

```bash
# cat /var/lib/kubelet/config.yaml |grep rotate
rotateCertificates: true
```

# 3. 修改kubeadm源码证书时间

由于社区不允许用户配置超过1年的证书，因此自定义证书时间的参数不被允许开发。

相关issue如下：

- https://github.com/kubernetes/kubernetes/issues/119350

如果要实现自定义参数设置证书时间，可参考一下pr：

- https://github.com/kubernetes/kubernetes/pull/100907/files

如果需要修改kubeadm源码证书可以参考如下代码修改。

kubeadm中跟证书相关的代码有：

## 3.1. ca文件的有效期（默认为10年）

代码文件：`./staging/src/k8s.io/client-go/util/cert/cert.go` 中 `NewSelfSignedCACert` 函数的NotAfter字段

代码如下：

```go
// NewSelfSignedCACert creates a CA certificate
func NewSelfSignedCACert(cfg Config, key crypto.Signer) (*x509.Certificate, error) {
    now := time.Now()
    // returns a uniform random value in [0, max-1), then add 1 to serial to make it a uniform random value in [1, max).
    serial, err := cryptorand.Int(cryptorand.Reader, new(big.Int).SetInt64(math.MaxInt64-1))
    if err != nil {
        return nil, err
    }
    serial = new(big.Int).Add(serial, big.NewInt(1))
    notBefore := now.UTC()
    if !cfg.NotBefore.IsZero() {
        notBefore = cfg.NotBefore.UTC()
    }
    tmpl := x509.Certificate{
        SerialNumber: serial,
        Subject: pkix.Name{
            CommonName:   cfg.CommonName,
            Organization: cfg.Organization,
        },
        DNSNames:              []string{cfg.CommonName},
        NotBefore:             notBefore,
        NotAfter:              now.Add(duration365d * 10).UTC(),   # 默认为10年
        KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
        BasicConstraintsValid: true,
        IsCA:                  true,
    }

    certDERBytes, err := x509.CreateCertificate(cryptorand.Reader, &tmpl, &tmpl, key.Public(), key)
    if err != nil {
        return nil, err
    }
    return x509.ParseCertificate(certDERBytes)
}
```

## 3.2. 证书文件的有效期（默认为1年）

代码文件：`cmd/kubeadm/app/util/pkiutil/pki_helpers.go`中 `NewSignedCert` 函数的 notAfter 字段

- 常量参数kubeadmconstants.`CertificateValidity` ： /cmd/kubeadm/app/constants/constants.go

代码如下：

```go
// NewSignedCert creates a signed certificate using the given CA certificate and key
func NewSignedCert(cfg *CertConfig, key crypto.Signer, caCert *x509.Certificate, caKey crypto.Signer, isCA bool) (*x509.Certificate, error) {
    // returns a uniform random value in [0, max-1), then add 1 to serial to make it a uniform random value in [1, max).
    serial, err := cryptorand.Int(cryptorand.Reader, new(big.Int).SetInt64(math.MaxInt64-1))
    if err != nil {
        return nil, err
    }
    serial = new(big.Int).Add(serial, big.NewInt(1))
    if len(cfg.CommonName) == 0 {
        return nil, errors.New("must specify a CommonName")
    }

    keyUsage := x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature
    if isCA {
        keyUsage |= x509.KeyUsageCertSign
    }

    RemoveDuplicateAltNames(&cfg.AltNames)

    # 此处引用了一个常量
    notAfter := time.Now().Add(kubeadmconstants.CertificateValidity).UTC()
    if cfg.NotAfter != nil {
        notAfter = *cfg.NotAfter
    }

    certTmpl := x509.Certificate{
        Subject: pkix.Name{
            CommonName:   cfg.CommonName,
            Organization: cfg.Organization,
        },
        DNSNames:              cfg.AltNames.DNSNames,
        IPAddresses:           cfg.AltNames.IPs,
        SerialNumber:          serial,
        NotBefore:             caCert.NotBefore,
        NotAfter:              notAfter,
        KeyUsage:              keyUsage,
        ExtKeyUsage:           cfg.Usages,
        BasicConstraintsValid: true,
        IsCA:                  isCA,
    }
    certDERBytes, err := x509.CreateCertificate(cryptorand.Reader, &certTmpl, caCert, key.Public(), caKey)
    if err != nil {
        return nil, err
    }
    return x509.ParseCertificate(certDERBytes)
}
```

其中常量文件为：

- /cmd/kubeadm/app/constants/constants.go

代码如下：

```go
    # 常量默认证书为1年。
    // CertificateValidity defines the validity for all the signed certificates generated by kubeadm
    CertificateValidity = time.Hour * 24 * 365  
```

可以修改此处常量的值10年，例如：

```go
    # 常量默认证书为1年。
    // CertificateValidity defines the validity for all the signed certificates generated by kubeadm
    CertificateValidity = time.Hour * 24 * 365 * 10
```

修改源码后，就可以重新编译kubeadm二进制。生成10年的证书文件。

参考：

- [使用 kubeadm 进行证书管理 | Kubernetes](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

- [Kubernetes v1.25 编译 kubeadm 修改证书有效期到 100 年](https://sysin.org/blog/kubernetes-kubeadm-cert-100y/)
