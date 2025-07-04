---
title: "kine的使用"
weight: 1
catalog: true
date: 2025-6-10 10:50:57
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

# 创建kine的数据表

如果kine连接MySQL使用的用户有创建表的权限，则会自动创建表名为kine的数据表，如果MySQL用户没有创建表的权限，则需要手动创建数据表，建表语句如下：

```bash
CREATE TABLE `kine` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(630) CHARACTER SET ascii DEFAULT NULL,
  `created` int(11) DEFAULT NULL,
  `deleted` int(11) DEFAULT NULL,
  `create_revision` bigint(20) unsigned DEFAULT NULL,
  `prev_revision` bigint(20) unsigned DEFAULT NULL,
  `lease` int(11) DEFAULT NULL,
  `value` mediumblob,
  `old_value` mediumblob,
  PRIMARY KEY (`id`),
  UNIQUE KEY `kine_name_prev_revision_uindex` (`name`,`prev_revision`),
  KEY `kine_name_index` (`name`),
  KEY `kine_name_id_index` (`name`,`id`),
  KEY `kine_id_deleted_index` (`id`,`deleted`),
  KEY `kine_prev_revision_index` (`prev_revision`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4;
```

# FAQ

## 问题1：converting NULL to int64 is unsupported

报错详情：

```bash
F0124 18:01:40.316896    44 controller.go:161] Unable to perform initial IP allocation check: unable to refresh the service IP block: rpc error: code = Unknown desc = sql: Scan error on column index 0, name "prev_revision": converting NULL to int64 is unsupported
```

原因：

mysql没有开启auto commit

```bash
SHOW VARIABLES LIKE 'autocommit';
```

解决方案：

开启mysql的autocommit配置。
