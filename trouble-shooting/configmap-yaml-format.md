---
title: "ConfigMap多行格式"
weight: 5
catalog: true
date: 2022-6-23 16:22:24
subtitle:
header-img:
tags:
- 问题排查
catagories:
- 问题排查
---

## 问题

configmap出现多行文本无法正常显示换行格式，而是以`\n`连接文本，查看和编辑时可读性很差。

```yaml
apiVersion: v1
data:
  config.yaml: "# log options\nlog_level: \"info\"\nlog_output: \"stderr\"\ncert_file:
    \"/etc/webhook/certs/cert.pem\"\nkey_file: \"/etc/webhook/certs/key.pem\"\nhttp_listen:
    \":8080\"\nhttps_listen: \":8443\"\ningress_publish_service: \nenable_profiling:
    true\nkubernetes:\n  kubeconfig: \"\"\n  resync_interval: \"6h\"\n  app_namespaces:\n
    \ - \"*\"\n  namespace_selector:\n  - \"\"\n  election_id: \"ingress-apisix-leader\"\n
    \ ingress_class: \"ph-apisix\"\n  ingress_version: \"networking/v1\"\n  watch_endpointslices:
    false\n  apisix_route_version: \"apisix.apache.org/v2beta3\"\n  enable_gateway_api:
    false\napisix:\n  default_cluster_base_url: http://apisix-admin.apisix.svc.cluster.local:9180/apisix/admin\n
    \ default_cluster_admin_key: \"edd1c9f034335f136f87ad84b625c8f1\"\n  default_cluster_name:
    \"default\""
kind: ConfigMap
```

## 解决方案

如果要保持多行输入和输出的格式，则需要符合以下情况：

- 文本不要以空格结尾
- 不要换行前再带个空格
- 不要在文本中添加不可见特殊字符

将文本拷贝并格式化yaml文本。可使用在线格式化工具：[YAML在线格式化](https://verytoolz.com/yaml-formatter.html)。

将格式化的文本拷贝到configmap文件，并检查上述三个问题。一般是因以`空格结尾`导致，搜索空格并去除行末的空格。

```yaml
apiVersion: v1
data:
  config.yaml: |-
    # log options
    log_level: "info"
    log_output: "stderr"
    cert_file: "/etc/webhook/certs/cert.pem"
    key_file: "/etc/webhook/certs/key.pem"
    http_listen: ":8080"
    https_listen: ":8443"
    ingress_publish_service:
    enable_profiling: true
```

参考：

- https://kennylong.io/fix-yaml-multi-line-format/
