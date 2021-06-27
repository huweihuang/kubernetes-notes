# 1. 基本概念

## 1.1. image layer（镜像层）

镜像可以看成是由多个镜像层叠加起来的一个文件系统，镜像层也可以简单理解为一个基本的镜像，而每个镜像层之间通过指针的形式进行叠加。

![1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578327/article/docker/commands/1.png)

根据上图，镜像层的主要组成部分包括镜像层id，镜像层指针【指向父层】，元数据【layer metadata】包含了docker构建和运行的信息还有父层的层次信息。

只读层和读写层【top layer】的组成部分基本一致。同时读写层可以转换成只读层【docker commit操作实现】

## 1.2. image（镜像）---【只读层的集合】

1、镜像是一堆只读层的统一视角，除了最底层没有指向外，每一层都指向它的父层，统一文件系统（union file system）技术能够将不同的层整合成一个文件系统，为这些层提供了一个统一的视角，这样就隐藏了多层的存在，在用户的角度看来，只存在一个文件系统。而每一层都是不可写的，就是只读层。

![2.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578328/article/docker/commands/2.1.png)

## 1.3. container（容器）---【一层读写层+多层只读层】

1、容器和镜像的区别在于容器的最上面一层是读写层【top layer】，而这边并没有区分容器是否在运行。运行状态的容器【running container】即一个可读写的文件系统【静态容器】+隔离的进程空间和其中的进程。

 ![3.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578329/article/docker/commands/3.1.png)

隔离的进程空间中的进程可以对该读写层进行增删改，其运行状态容器的进程操作都作用在该读写层上。每个容器只能有一个进程隔离空间。

![3.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578328/article/docker/commands/3.2.png)


# 2. Docker常用命令原理图概览：

<img src="http://res.cloudinary.com/dqxtn0ick/image/upload/v1510578333/article/docker/commands/dockerCommands.jpg" width="70%">

# 3.  Docker常用命令说明

## 3.1. 标识说明

### 3.1.1. image---（统一只读文件系统）

![4.1.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578329/article/docker/commands/4.1.1.png)

### 3.1.2. 静态容器【未运行的容器】---（统一可读写文件系统）

![4.1.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578329/article/docker/commands/4.1.2.png)

### 3.1.3. 动态容器【running container】---（进程空间（包括进程）+统一可读写文件系统）

![4.1.3](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578330/article/docker/commands/4.1.3.png)

## 3.2. 命令说明

### 3.2.1. docker生命周期相关命令:

#### 3.2.1.1. docker create {image-id}

![4.2.1.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578330/article/docker/commands/4.2.1.1.png)

即为只读文件系统添加一层可读写层【top layer】，生成可读写文件系统，该命令状态下容器为静态容器，并没有运行。

#### 3.2.1.2. docker start（restart） {container-id}      

docker stop即为docker start的逆过程

![4.2.1.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578330/article/docker/commands/4.2.1.2.png)

即为可读写文件系统添加一个进程空间【包括进程】，生成动态容器【running container】

#### 3.2.1.3. docker run {image-id}

![4.2.1.3](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578330/article/docker/commands/4.2.1.3.png)

docker run=docker create+docker start

类似流程如下 ：

![4.2.1.3.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578329/article/docker/commands/4.2.1.3.1.png)

#### 3.2.1.4. docker stop {container-id}

![4.2.1.4](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578330/article/docker/commands/4.2.1.4.png)

向运行的容器中发一个SIGTERM的信号，然后停止所有的进程。即为docker start的逆过程。

#### 3.2.1.5. docker kill {container-id}

![4.2.1.5](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.1.5.png)

docker kill向容器发送不友好的SIGKILL的信号，相当于快速强制关闭容器，与docker stop的区别在于docker stop是正常关闭，先发SIGTERM信号，清理进程，再发SIGKILL信号退出。

#### 3.2.1.6. docker pause {container-id}    

docker unpause为逆过程---比较少使用

![4.2.1.6](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578330/article/docker/commands/4.2.1.6.png)

暂停容器中的所有进程，使用cgroup的freezer顺序暂停容器里的所有进程，docker unpause为逆过程即恢复所有进程。比较少使用。

#### 3.2.1.7. docker commit {container-id}

![4.2.1.7](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.1.7.png)

![4.2.1.7.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.1.7.2.png)

把容器的可读写层转化成只读层，即从容器状态【可读写文件系统】变为镜像状态【只读文件系统】，可理解为【固化】。

#### 3.2.1.8. docker build

![4.2.1.8.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.1.8.1.png)

![4.2.1.8.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.1.8.2.png)

**docker build=docker run【运行容器】+【进程修改数据】+docker commit【固化数据】，不断循环直至生成所需镜像。**

循环一次便会形成新的层（镜像）【原镜像层+已固化的可读写层】

docker build 一般作用在dockerfile文件上。


### 3.2.2. docker查询类命令

查询对象：①image，②container，③image/container中的数据，④系统信息[容器数，镜像数及其他]

#### 3.2.2.1. Image

#### 1、docker images

![4.2.2.1.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.2.1.1.png)

docker images 列出当前镜像【以顶层镜像id来表示整个完整镜像】，每个顶层镜像下面隐藏多个镜像层。

#### 2、docker images -a

![4.2.2.1.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578332/article/docker/commands/4.2.2.1.2.png)

docker images -a列出所有镜像层【排序以每个顶层镜像id为首后接该镜像下的所有镜像层】，依次列出每个镜像的所有镜像层。

#### 3、docker history {image-id}

![4.2.2.1.3](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.2.1.3.png)

docker history 列出该镜像id下的所有历史镜像。

#### 3.2.2.2. Container

#### 1、docker ps

![4.2.2.2.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578331/article/docker/commands/4.2.2.2.1.png)

列出所有运行的容器【running container】

#### 2、docker ps -a 

![4.2.2.2.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578332/article/docker/commands/4.2.2.2.2.png)

列出所有容器，包括静态容器【未运行的容器】和动态容器【running container】

#### 3.2.2.3. Info

#### 1、docker inspect {container-id} or {image-id}

![4.2.2.3.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578332/article/docker/commands/4.2.2.3.1.png)

提取出容器或镜像最顶层的元数据。

#### 2、docker info

显示 Docker 系统信息，包括镜像和容器数。

### 3.2.3. docker操作类命令：

#### 3.2.3.1. docker rm {container-id}

![4.2.3.1](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578332/article/docker/commands/4.2.3.1.png)

docker rm会移除镜像，该命令只能对静态容器【非运行状态】进行操作。

通过docker rm -f {container-id}的-f （force）参数可以强制删除运行状态的容器【running container】。

#### 3.2.3.2. docker rmi {image-id}

![4.2.3.2](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578332/article/docker/commands/4.2.3.2.png)

#### 3.2.3.3. docker exec {running-container-id}

![4.2.3.3](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578332/article/docker/commands/4.2.3.3.png)

docker exec会在运行状态的容器中执行一个新的进程。

#### 3.2.3.4. docker export {container-id}

![4.2.3.4](https://res.cloudinary.com/dqxtn0ick/image/upload/v1510578333/article/docker/commands/4.2.3.4.png)

docker export命令创建一个tar文件，并且移除了元数据和不必要的层，将多个层整合成了一个层，只保存了当前统一视角看到的内容。

 
参考文章：

- http://merrigrove.blogspot.com/2015/10/visualizing-docker-containers-and-images.html
