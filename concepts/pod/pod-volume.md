---
title: "Pod存储卷"
weight: 5
catalog: true
date: 2017-08-13 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# Pod Volume

同一个Pod中的多个容器可以共享Pod级别的存储卷Volume,Volume可以定义为各种类型，多个容器各自进行挂载，将Pod的Volume挂载为容器内部需要的目录。

例如：Pod级别的Volume:"app-logs",用于tomcat向其中写日志文件，busybox读日志文件。

![这里写图片描述](http://res.cloudinary.com/dqxtn0ick/image/upload/v1512804287/article/kubernetes/pod/pod_volume.png)

**pod-volumes-applogs.yaml**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-pod
spec:
  containers:
  - name: tomcat
    image: tomcat
    ports:
    - containerPort: 8080
    volumeMounts:
    - name: app-logs
      mountPath: /usr/local/tomcat/logs
  - name: busybox
    image: busybox
    command: ["sh","-c","tailf /logs/catalina*.log"]
    volumeMounts:
    - name: app-logs
      mountPath: /logs
  volumes:
  - name: app-logs
    emptuDir: {}
```

**查看日志**

1. kubectl logs `<pod_name>` -c `<container_name>`
2. kubectl exec -it `<pod_name>` -c `<container_name>` – tail /usr/local/tomcat/logs/catalina.xx.log


参考文章

- 《Kubernetes权威指南》  
