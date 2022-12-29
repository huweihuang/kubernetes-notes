---
title: "kubectl命令别名"
weight: 3
catalog: true
date: 2019-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---


# 1. kubectl-aliases

[kubectl-aliases](https://github.com/ahmetb/kubectl-aliases)开源工具是由[脚本](https://github.com/ahmetb/kubectl-aliases/blob/master/generate_aliases.py)通过拼接各种kubectl相关元素组成的[alias命令别名列表](https://github.com/ahmetb/kubectl-aliases/blob/master/.kubectl_aliases)，其中命令别名拼接元素如下：

| base      | [system?]        | [operation]                                                  | [resource]                                                   | [flags]                                                      |
| :-------- | :--------------- | :--------------- | :-------------- | :---------- |
| `k`ubectl | -n=kube-`sys`tem | `g`et<br /> `d`escribe <br />`rm`:delete<br /> `lo`gs<br /> `ex`ec<br /> `a`pply | `po`ds<br /> `dep`loyment<br /> `sec`ret<br /> `ing`ress<br /> `no`de <br />`svc`<br /> `ns` <br />`cm` | `oyaml` <br />`ojson`<br /> `owide` <br />`all`<br /> `w`atch<br /> `f`ile<br /> `l` |

- `k`=kubectl
  - **sys**=`--namespace kube-system`
- commands:
  - **g**=`get`
  - **d**=`describe`
  - **rm**=`delete`
  - **a**:`apply -f`
  - **ex**: `exec -i -t`
  - **lo**: `logs -f`
- resources:
  - **po**=`pod`
  - **dep**=`deployment`
  - **ing**=`ingress`
  - **svc**=`service`
  - **cm**=`configmap`
  - **sec**=`secret`
  - **ns**=`namespace`
  - **no**=`node`
- flags:
  - output format: **oyaml**, **ojson**, **owide**
  - **all**: `--all` or `--all-namespaces` depending on the command
  - **sl**: `--show-labels`
  - **w**=`-w/--watch`
- value flags (should be at the end):
  - **f**=`-f/--filename`
  - **l**=`-l/--selector`

# 2. 示例

```bash
# 示例1
kd → kubectl describe

# 示例2
kgdepallw → kubectl get deployment —all-namespaces —watch
```

**alias get示例：**

```bash
alias k='kubectl'
alias kg='kubectl get'
alias kgpo='kubectl get pods'
alias kgpoojson='kubectl get pods -o=json'
alias kgpon='kubectl get pods --namespace'
alias ksysgpooyamll='kubectl --namespace=kube-system get pods -o=yaml -l'
```

# 3. 安装

```bash
# 将 .kubectl_aliases下载到 home 目录
cd ~ && wget https://raw.githubusercontent.com/ahmetb/kubectl-aliases/master/.kubectl_aliases

# 将以下内容添加到 .bashrc中，并执行 source .bashrc
[ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases
function kubectl() { command kubectl $@; }

# 如果需要提示别名的完整命令，则将以下内容添加到 .bashrc中，并执行 source .bashrc
[ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases
function kubectl() { echo "+ kubectl $@"; command kubectl $@; }
```



参考：

- https://ahmet.im/blog/kubectl-aliases/
- https://github.com/ahmetb/kubectl-aliases



