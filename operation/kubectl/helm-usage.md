---
title: "helm的使用"
weight: 5
catalog: true
date: 2022-12-24 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 1. 安装helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

# 2. 基本概念

Helm是用来管理k8s集群上的软件包。

- `Chart`:代表helm软件包

- `Repository`：软件包的存放仓库

- `Release`:运行在k8s上的一个发布实例。

# 3. helm命令

```bash
Usage:
  helm [command]

Available Commands:
  completion  generate autocompletion scripts for the specified shell
  create      create a new chart with the given name
  dependency  manage a chart's dependencies
  env         helm client environment information
  get         download extended information of a named release
  help        Help about any command
  history     fetch release history
  install     install a chart
  lint        examine a chart for possible issues
  list        list releases
  package     package a chart directory into a chart archive
  plugin      install, list, or uninstall Helm plugins
  pull        download a chart from a repository and (optionally) unpack it in local directory
  push        push a chart to remote
  registry    login to or logout from a registry
  repo        add, list, remove, update, and index chart repositories
  rollback    roll back a release to a previous revision
  search      search for a keyword in charts
  show        show information of a chart
  status      display the status of the named release
  template    locally render templates
  test        run tests for a release
  uninstall   uninstall a release
  upgrade     upgrade a release
  verify      verify that a chart at the given path has been signed and is valid
  version     print the client version information
```

# 4. 常用命令

## 4.1. helm search

- helm search hub：从 [Artifact Hub](https://artifacthub.io/) 中查找并列出 helm charts。支持模糊匹配。

```bash
helm search hub wordpress
```

- helm search repo：基于指定仓库进行搜索。

```bash
helm repo add brigade https://brigadecore.github.io/charts
helm search repo brigade

# 列出所有版本
helm search repo apisix -l
```

## 4.2. helm install/uninstall

```bash
helm install <release_name> <chart_name>
# 示例
helm install happy-panda bitnami/wordpress -

# uninstall
helm uninstall RELEASE_NAME
```

安装自定义chart

```bash
helm install -f values.yaml bitnami/wordpress --generate-name

# 本地 chart 压缩包
helm install foo foo-0.1.1.tgz
# 解压后的 chart 目录
helm install foo path/to/foo
# 完整的 URL
helm install foo https://example.com/charts/foo-1.2.3.tgz
```

## 4.3. helm upgrade

```bash
helm upgrade happy-panda bitnami/wordpress
```

## 4.4. helm rollback

```bash
helm rollback <RELEASE> [REVISION] [flags]
```

## 4.5. helm repo

```bash
helm repo add dev https://example.com/dev-charts
helm repo list
helm repo remove
```

## 4.6. helm pull

从仓库下载并（可选）在本地目录解压。

```bash
helm pull [chart URL | repo/chartname]


helm pull [chart URL | repo/chartname] --version 
```

# 5. 新建一个chart

```bash
 helm create mychart
```

查看生成的文件目录：

```bash
mychart
|-- charts
|-- Chart.yaml
|-- templates
|   |-- deployment.yaml
|   |-- _helpers.tpl
|   |-- hpa.yaml
|   |-- ingress.yaml
|   |-- NOTES.txt
|   |-- serviceaccount.yaml
|   |-- service.yaml
|   `-- tests
|       `-- test-connection.yaml
`-- values.yaml
```

参考：

- [Helm | 安装Helm](https://helm.sh/zh/docs/intro/install/)
- [Helm | 使用Helm](https://helm.sh/zh/docs/intro/using_helm/)
