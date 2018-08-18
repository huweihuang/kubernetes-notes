---
title: "[Kubernetes] Influxdb介绍"
catalog: true
date: 2017-08-13 10:50:57
type: "categories"
subtitle:
header-img: 
tags:
- Kubernetes
catagories:
- Kubernetes
---

## 1. InfluxDB简介

InfluxDB是一个当下比较流行的时序数据库，InfluxDB使用 Go 语言编写，无需外部依赖，安装配置非常方便，适合构建大型分布式系统的监控系统。

主要特色功能：

1）基于时间序列，支持与时间有关的相关函数（如最大，最小，求和等）

2）可度量性：你可以实时对大量数据进行计算

3）基于事件：它支持任意的事件数据

## 2. InfluxDB安装

### 1）安装

wget [https://dl.influxdata.com/influxdb/releases/influxdb-0.13.0.x86_64.rpm](https://dl.influxdata.com/influxdb/releases/influxdb-0.13.0.x86_64.rpm)

yum localinstall influxdb-0.13.0.armhf.rpm

### 2）启动

service influxdb start

### 3）访问

http://服务器IP:8083

### 4）docker image方式安装

docker pull influxdb

docker run -d -p 8083:8083 -p 8086:8086 --expose 8090 --expose 8099 --volume=/opt/data/influxdb:/data --name influxsrv influxdb:latest

## 3. InfluxDB的基本概念

### 3.1. 与传统数据库中的名词做比较

| influxDB中的名词 | 传统数据库中的概念 |
| ------------ | --------- |
| database     | 数据库       |
| measurement  | 数据库中的表    |
| points       | 表里面的一行数据  |

### 3.2. InfluxDB中独有的概念

#### 3.2.1. Point

Point由时间戳（time）、数据（field）、标签（tags）组成。

Point相当于传统数据库里的一行数据，如下表所示：

| Point属性 | 传统数据库中的概念                    |
| ------- | ---------------------------- |
| time    | 每个数据记录时间，是数据库中的主索引(会自动生成)    |
| fields  | 各种记录值（没有索引的属性）也就是记录的值：温度， 湿度 |
| tags    | 各种有索引的属性：地区，海拔               |

#### 3.2.2. series

所有在数据库中的数据，都需要通过图表来展示，而这个series表示这个表里面的数据，可以在图表上画成几条线：通过tags排列组合算出来

show series from cpu

## 4. InfluxDB的基本操作

InfluxDB提供三种操作方式：

1）客户端命令行方式

2）HTTP API接口

3）各语言API库

### 4.1. InfluxDB数据库操作

| 操作      | 命令                        |
| ------- | ------------------------- |
| 显示数据库   | show databases            |
| 创建数据库   | create database `db_name` |
| 删除数据库   | drop database `db_name`   |
| 使用某个数据库 | use `db_name`             |

### 4.2. InfluxDB数据表操作

| 操作       | 命令                                       | 说明                                       |
| -------- | ---------------------------------------- | ---------------------------------------- |
| 显示所有表    | SHOW MEASUREMENTS                        |                                          |
| 创建数据表    | insert `table_name`,hostname=server01 value=442221834240i 1435362189575692182 | 其中 disk_free 就是表名，hostname是索引，value=xx是记录值，记录值可以有多个，最后是指定的时间 |
| 删除数据表    | drop measurement `table_name`            |                                          |
| 查看表内容    | select * from `table_name`               |                                          |
| 查看series | show series from `table_name`            | series表示这个表里面的数据，可以在图表上画成几条线，series主要通过tags排列组合算出来 |
