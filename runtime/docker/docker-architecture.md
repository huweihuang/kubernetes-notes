# 1. Docker的总架构图 

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577966/article/docker/dockerArch/docker-architecture.jpg" width="60%"/>

docker是一个C/S模式的架构，后端是一个松耦合架构，模块各司其职。

1. 用户是使用Docker Client与Docker Daemon建立通信，并发送请求给后者。
2. Docker Daemon作为Docker架构中的主体部分，首先提供Server的功能使其可以接受Docker Client的请求；
3. Engine执行Docker内部的一系列工作，每一项工作都是以一个Job的形式的存在。
4. Job的运行过程中，当需要容器镜像时，则从Docker Registry中下载镜像，并通过镜像管理驱动graphdriver将下载镜像以Graph的形式存储；
5. 当需要为Docker创建网络环境时，通过网络管理驱动networkdriver创建并配置Docker容器网络环境；
6. 当需要限制Docker容器运行资源或执行用户指令等操作时，则通过execdriver来完成。
7. libcontainer是一项独立的容器管理包，networkdriver以及execdriver都是通过libcontainer来实现具体对容器进行的操作。

# 2. Docker各模块组件分析

## 2.1. Docker Client[发起请求]

1. Docker Client是和Docker Daemon建立通信的客户端。用户使用的可执行文件为docker（类似可执行脚本的命令），docker命令后接参数的形式来实现一个完整的请求命令（例如docker images，docker为命令不可变，images为参数可变）。
2. Docker Client可以通过以下三种方式和Docker Daemon建立通信：tcp://host:port，unix://path_to_socket和fd://socketfd。
3. Docker Client发送容器管理请求后，由Docker Daemon接受并处理请求，当Docker Client接收到返回的请求相应并简单处理后，Docker Client一次完整的生命周期就结束了。[一次完整的请求：发送请求→处理请求→返回结果]，与传统的C/S架构请求流程并无不同。

## 2.2. Docker Daemon[后台守护进程]

**Docker Daemon的架构图**

  <img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577967/article/docker/dockerArch/docker-daemon.jpg" width="60%"/>

### 2.2.1. Docker Server[调度分发请求]

**Docker Server的架构图**

   <img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577967/article/docker/dockerArch/docker-server.jpg" width="60%"/>

   1. Docker Server相当于C/S架构的服务端。功能为接受并调度分发Docker Client发送的请求。接受请求后，Server通过路由与分发调度，找到相应的Handler来执行请求。
   2. 在Docker的启动过程中，通过包gorilla/mux，创建了一个mux.Router，提供请求的路由功能。在Golang中，gorilla/mux是一个强大的URL路由器以及调度分发器。该mux.Router中添加了众多的路由项，每一个路由项由HTTP请求方法（PUT、POST、GET或DELETE）、URL、Handler三部分组成。
   3. 创建完mux.Router之后，Docker将Server的监听地址以及mux.Router作为参数，创建一个httpSrv=http.Server{}，最终执行httpSrv.Serve()为请求服务。
   4. 在Server的服务过程中，Server在listener上接受Docker Client的访问请求，并创建一个全新的goroutine来服务该请求。在goroutine中，首先读取请求内容，然后做解析工作，接着找到相应的路由项，随后调用相应的Handler来处理该请求，最后Handler处理完请求之后回复该请求。

### 2.2.2. Engine

   1. Engine是Docker架构中的运行引擎，同时也Docker运行的核心模块。它扮演Docker container存储仓库的角色，并且通过执行job的方式来操纵管理这些容器。
   2. 在Engine数据结构的设计与实现过程中，有一个handler对象。该handler对象存储的都是关于众多特定job的handler处理访问。举例说明，Engine的handler对象中有一项为：{"create": daemon.ContainerCreate,}，则说明当名为"create"的job在运行时，执行的是daemon.ContainerCreate的handler。

### 2.2.3. Job

   1. 一个Job可以认为是Docker架构中Engine内部最基本的工作执行单元。Docker可以做的每一项工作，都可以抽象为一个job。例如：在容器内部运行一个进程，这是一个job；创建一个新的容器，这是一个job。Docker Server的运行过程也是一个job，名为serveapi。
   2. Job的设计者，把Job设计得与Unix进程相仿。比如说：Job有一个名称，有参数，有环境变量，有标准的输入输出，有错误处理，有返回状态等。

## 2.3. Docker Registry[镜像注册中心]

1. Docker Registry是一个存储容器镜像的仓库（注册中心），可理解为云端镜像仓库，按repository来分类，docker pull 按照[repository]:[tag]来精确定义一个image。
2. 在Docker的运行过程中，Docker Daemon会与Docker Registry通信，并实现搜索镜像、下载镜像、上传镜像三个功能，这三个功能对应的job名称分别为"search"，"pull" 与 "push"。
3. 可分为公有仓库（docker hub）和私有仓库。

## 2.4. Graph[docker内部数据库]

**Graph的架构图**

  <img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577968/article/docker/dockerArch/graph-architecture.jpg" width="60%"/>

### 2.4.1. Repository

   1. 已下载镜像的保管者（包括下载镜像和dockerfile构建的镜像）。
   2. 一个repository表示某类镜像的仓库（例如Ubuntu），同一个repository内的镜像用tag来区分（表示同一类镜像的不同标签或版本）。一个registry包含多个repository，一个repository包含同类型的多个image。
   3. 镜像的存储类型有aufs，devicemapper,Btrfs，Vfs等。其中centos系统使用devicemapper的存储类型。
   4. 同时在Graph的本地目录中，关于每一个的容器镜像，具体存储的信息有：该容器镜像的元数据，容器镜像的大小信息，以及该容器镜像所代表的具体rootfs。

### 2.4.2. GraphDB

   1. 已下载容器镜像之间关系的记录者。
   2. GraphDB是一个构建在SQLite之上的小型图数据库，实现了节点的命名以及节点之间关联关系的记录

## 2.5. Driver[执行部分]

Driver是Docker架构中的驱动模块。通过Driver驱动，Docker可以实现对Docker容器执行环境的定制。即Graph负责镜像的存储，Driver负责容器的执行。

### 2.5.1. graphdriver

**graphdriver架构图**

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577968/article/docker/dockerArch/graphdriver.jpg" width="60%"/>

   1. graphdriver主要用于完成容器镜像的管理，包括存储与获取。
   2. 存储：docker pull下载的镜像由graphdriver存储到本地的指定目录（Graph中）。
   3. 获取：docker run（create）用镜像来创建容器的时候由graphdriver到本地Graph中获取镜像。


### 2.5.2. networkdriver

**networkdriver的架构图**

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577968/article/docker/dockerArch/networkdriver.jpg" width="60%"/>

   1. networkdriver的用途是完成Docker容器网络环境的配置，其中包括
      - Docker启动时为Docker环境创建网桥；
      - Docker容器创建时为其创建专属虚拟网卡设备；
      - Docker容器分配IP、端口并与宿主机做端口映射，设置容器防火墙策略等。

### 2.5.3. execdriver

**execdriver的架构图**

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577967/article/docker/dockerArch/execdriver.jpg" width="55%"/>

   1. execdriver作为Docker容器的执行驱动，负责创建容器运行命名空间，负责容器资源使用的统计与限制，负责容器内部进程的真正运行等。
   2. 现在execdriver默认使用native驱动，不依赖于LXC。

## 2.6. libcontainer[函数库]

**libcontainer的架构图**

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577967/article/docker/dockerArch/libcontainer.jpg" width="60%"/>

1. libcontainer是Docker架构中一个使用Go语言设计实现的库，设计初衷是希望该库可以不依靠任何依赖，直接访问内核中与容器相关的API。
2. Docker可以直接调用libcontainer，而最终操纵容器的namespace、cgroups、apparmor、网络设备以及防火墙规则等。
3. libcontainer提供了一整套标准的接口来满足上层对容器管理的需求。或者说，libcontainer屏蔽了Docker上层对容器的直接管理。

## 2.7. docker container[服务交付的最终形式]

**container架构**

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510577966/article/docker/dockerArch/container.jpg" width="60%"/>

1. Docker container（Docker容器）是Docker架构中服务交付的最终体现形式。

2. Docker按照用户的需求与指令，订制相应的Docker容器：

3. - 用户通过指定容器镜像，使得Docker容器可以自定义rootfs等文件系统；
   - 用户通过指定计算资源的配额，使得Docker容器使用指定的计算资源；
   - 用户通过配置网络及其安全策略，使得Docker容器拥有独立且安全的网络环境；
   - 用户通过指定运行的命令，使得Docker容器执行指定的工作。


参考文章：
- 《Docker源码分析》
