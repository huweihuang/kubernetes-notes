---
title: "kubectl进入node shell"
weight: 4
catalog: true
date: 2022-10-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

本文介绍如何通过kubectl进入节点的shell环境。

## 1. 安装krew node-shell

### 1.1. 安装krew

```bash
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
```

在`~/.bashrc`或`~/.zshrc`添加以下命令

```bash
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
```

### 1.2. 安装node-shell

node-shell的代码参考：[kubectl-node-shell/kubectl-node_shell at master · kvaps/kubectl-node-shell · GitHub](https://github.com/kvaps/kubectl-node-shell/blob/master/kubectl-node_shell)

```bash
kubectl krew install node-shell
```

示例：

```bash
# kubectl krew install node-shell
Updated the local copy of plugin index.
Installing plugin: node-shell
Installed plugin: node-shell
\
 | Use this plugin:
 |     kubectl node-shell
 | Documentation:
 |     https://github.com/kvaps/kubectl-node-shell
 | Caveats:
 | \
 |  | You need to be allowed to start privileged pods in the cluster
 | /
/
WARNING: You installed plugin "node-shell" from the krew-index plugin repository.
   These plugins are not audited for security by the Krew maintainers.
   Run them at your own risk.
```

## 2. 进入节点的shell

### 2.1. 登录node

创建一个临时的特权容器，登录容器即登录node shell。

```bash
kubectl node-shell <node-name>
```

示例：

```bash
# kubectl node-shell node1
spawning "nsenter-9yqytp" on "node1"
If you don't see a command prompt, try pressing enter.
groups: cannot find name for group ID 11
To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

root@node1:/#
```

### 2.2. 退出node

退出容器，容器会被自动删除。

```bash
# exit
logout
pod default/nsenter-9yqytp terminated (Error)
pod "nsenter-9yqytp" deleted
```

## 3. 原理

容器是弱隔离，共享节点的内核，通过cgroup和namespace来实现进程级别的隔离。那么通过在特权容器里执行`nsenter`的命令，则可以通过登录特权容器来实现登录node的shell环境。

创建一个特权容器，进入node shell的命令为：

```bash
nsenter --target 1 --mount --uts --ipc --net --pid -- bash -l
```

进入 node shell 的权限：

- `hostPID: true` 共享 host 的 pid

- `hostNetwork: true` 共享 host 的网络

- `privileged: true`: PSP 权限策略是 `privileged`, 即完全无限制。

### 3.1. Pod.yaml

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: nsenter-9yqytp
  name: nsenter-9yqytp
  namespace: default
spec:
  containers:
  - command:
    - nsenter
    - --target
    - "1"
    - --mount
    - --uts
    - --ipc
    - --net
    - --pid
    - --
    - bash
    - -l
    image: docker.io/library/alpine
    imagePullPolicy: Always
    name: nsenter
    resources:
      limits:
        cpu: 100m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 256Mi
    securityContext:
      privileged: true
    stdin: true
    stdinOnce: true
    tty: true
    volumeMounts:
    - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
      name: kube-api-access-4ktlf
      readOnly: true
  enableServiceLinks: true
  hostNetwork: true
  hostPID: true
  nodeName: node1
  preemptionPolicy: PreemptLowerPriority
  priority: 0
  restartPolicy: Never
  schedulerName: default-scheduler
  securityContext: {}
  serviceAccount: default
  serviceAccountName: default
  tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
  - effect: NoExecute
    operator: Exists
  volumes:
  - name: kube-api-access-4ktlf
    projected:
      defaultMode: 420
      sources:
      - serviceAccountToken:
          expirationSeconds: 3607
          path: token
      - configMap:
          items:
          - key: ca.crt
            path: ca.crt
          name: kube-root-ca.crt
      - downwardAPI:
          items:
          - fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
            path: namespace
```

创建完容器后，直接登录容器即可登录节点的shell

```bash
kubectl exec -it nsenter-9yqytp bash
```

参考：

- [如何通过 kubectl 进入 node shell - 东风微鸣技术博客](https://ewhisper.cn/posts/20749/)

- [GitHub - kvaps/kubectl-node-shell: Exec into node via kubectl](https://github.com/kvaps/kubectl-node-shell)

- https://krew.sigs.k8s.io/docs/user-guide/setup/install/
