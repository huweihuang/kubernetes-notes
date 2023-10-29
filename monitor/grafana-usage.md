---
title: "Grafana部署"
weight: 6
catalog: true
date: 2023-05-18 10:50:57
subtitle:
header-img: 
tags:
- Monitor
catagories:
- Monitor
---

# Docker部署

```bash
docker run -d -p 3000:3000 grafana/grafana:latest
```

# K8S部署

helm部署

```bash
helm repo add grafana https://grafana.github.io/helm-charts

helm search repo grafana
```



参考：

- [Install Grafana | Grafana documentation](https://grafana.com/docs/grafana/latest/setup-grafana/installation/)

- [Deploy Grafana on Kubernetes | Grafana documentation](https://grafana.com/docs/grafana/latest/setup-grafana/installation/kubernetes/)

- [GitHub - grafana/helm-charts](https://github.com/grafana/helm-charts)


