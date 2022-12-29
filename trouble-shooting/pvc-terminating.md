---
title: "PVC Terminating"
weight: 4
catalog: true
date: 2019-6-23 16:22:24
subtitle:
header-img:
tags:
- 问题排查
catagories:
- 问题排查
---

# 问题描述

```
pvc terminating
```

pvc在删除时，卡在terminating中。

# 解决方法

```bash
kubectl patch pvc {PVC_NAME} -p '{"metadata":{"finalizers":null}}'
```
