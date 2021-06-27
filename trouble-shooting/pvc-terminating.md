# 问题描述

```
pvc terminating
```

pvc在删除时，卡在terminating中。

# 解决方法

```bash
kubectl patch pvc {PVC_NAME} -p '{"metadata":{"finalizers":null}}'
```
