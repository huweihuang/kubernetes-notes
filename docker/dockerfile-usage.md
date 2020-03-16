# 1. Dockerfile的说明

dockerfile指令忽略大小写，建议大写，#作为注释，每行只支持一条指令，指令可以带多个参数。

dockerfile指令分为构建指令和设置指令。

1. 构建指令：用于构建image，其指定的操作不会在运行image的容器中执行。
2. 设置指令：用于设置image的属性，其指定的操作会在运行image的容器中执行。

# 2. Dockerfile指令说明

## 2.1. FROM（指定基础镜像）[构建指令]

该命令用来指定基础镜像，在基础镜像的基础上修改数据从而构建新的镜像。基础镜像可以是本地仓库也可以是远程仓库。

指令有两种格式：

1. FROM `image`   【默认为latest版本】
2. FROM `image`:`tag`     【指定版本】

## 2.2. MAINTAINER（镜像创建者信息）[构建指令]

将镜像制作者（维护者）的信息写入image中，执行docker inspect时会输出该信息。

格式：MAINTAINER `name`

MAINTAINER命令已废弃，可使用maintainer label的方式。

```
LABEL maintainer="SvenDowideit@home.org.au"
```

## 2.3. RUN（安装软件用）[构建指令]

RUN可以运行任何被基础镜像支持的命令（即在基础镜像上执行一个进程），可以使用多条RUN指令，指令较长可以使用\来换行。

指令有两种格式：

1. RUN `command` (the command is run in a shell - `/bin/sh -c`)
2. RUN ["executable", "param1", "param2" ... ] (exec form) 
   - 指定使用其他终端实现，使用exec执行。
   - 例子：RUN["/bin/bash","-c","echo hello"]

## 2.4. CMD（设置container启动时执行的操作）[设置指令]

用于容器启动时的指定操作，可以是自定义脚本或命令，只执行一次，多个默认执行最后一个。

指令有三种格式：

1. CMD ["executable","param1","param2"] (like an exec, this is the preferred form) 
   - 运行一个可执行文件并提供参数。
2. CMD command param1 param2 (as a shell) 
   - 直接执行shell命令，默认以/bin/sh -c执行。
3. CMD ["param1","param2"] (as default parameters to ENTRYPOINT) 
   - 和ENTRYPOINT配合使用，只作为完整命令的参数部分。

## 2.5. ENTRYPOINT（设置container启动时执行的操作）[设置指令]

指定容器启动时执行的命令，若多次设置只执行最后一次。

ENTRYPOINT翻译为“进入点”，它的功能可以让容器表现得像一个可执行程序一样。

例子：ENTRYPOINT ["/bin/echo"] ，那么docker build出来的镜像以后的容器功能就像一个/bin/echo程序，docker run -it imageecho “this is a test”，就会输出对应的字符串。这个imageecho镜像对应的容器表现出来的功能就像一个echo程序一样。

指令有两种格式：

1. ENTRYPOINT ["executable", "param1", "param2"] (like an exec, the preferred form)

   - 和CMD配合使用，CMD则作为完整命令的参数部分，ENTRYPOINT以JSON格式指定执行的命令部分。CMD可以为ENTRYPOINT提供可变参数，不需要变动的参数可以写在ENTRYPOINT里面。

   - 例子：

     ENTRYPOINT ["/usr/bin/ls","-a"]

     CMD ["-l"] 

2. ENTRYPOINT command param1 param2 (as a shell)

   - 独自使用，即和CMD类似，如果CMD也是个完整命令[CMD command param1 param2 (as a shell) ]，那么会相互覆盖，只执行最后一个CMD或ENTRYPOINT。
   - 例子：ENTRYPOINT ls -l

## 2.6. USER（设置container容器启动的登录用户）[设置指令]

设置启动容器的用户，默认为root用户。

格式：USER daemon

## 2.7. EXPOSE（指定容器需要映射到宿主机的端口）[设置指令]

该指令会将容器中的端口映射为宿主机中的端口[确保宿主机的端口号没有被使用]。通过宿主机IP和映射后的端口即可访问容器[避免每次运行容器时IP随机生成不固定的问题]。前提是EXPOSE设置映射端口，运行容器时加上-p参数指定EXPOSE设置的端口。EXPOSE可以设置多个端口号，相应地运行容器配套多次使用-p参数。可以通过docker port +容器需要映射的端口号和容器ID来参考宿主机的映射端口。

格式：EXPOSE `port` [`port`...]

## 2.8. ENV（用于设置环境变量）[构建指令]

在image中设置环境变量[以键值对的形式]，设置之后RUN命令可以使用该环境变量，在容器启动后也可以通过docker inspect查看环境变量或者通过 docker run --env key=value设置或修改环境变量。

格式：ENV `key` `value` 

例子：ENV JAVA_HOME /path/to/java/dirent

## 2.9. ARG（用于设置变量）[构建指令]

ARG定义一个默认参数，可以在dockerfile中引用。构建阶段可以通过docker build --build-arg <varname>=<value>参数向dockerfile文件中传入参数。

```bash
ARG <arg_name>[=<default value>]
# 可以搭配ENV使用
ENV env_name ${arg_name}
```

示例：

```bash
docker build --build-arg user=what_user .
```

## 2.10. ADD（从src复制文件到container的dest路径）[构建指令]

复制指定的src到容器中的dest，其中src是相对被构建的源目录的相对路径，可以是文件或目录的路径，也可以是一个远程的文件url。`dest` 是container中的绝对路径。所有拷贝到container中的文件和文件夹权限为0755，uid和gid为0。

- 如果src是一个目录，那么会将该目录下的所有文件添加到container中，不包括目录；
- 如果src文件是可识别的压缩格式，则docker会帮忙解压缩（注意压缩格式）；
- 如果`src`是文件且`dest`中不使用斜杠结束，则会将`dest`视为文件，`src`的内容会写入`dest`；
- 如果`src`是文件且`dest`中使用斜杠结束，则会`src`文件拷贝到`dest`目录下。

格式：ADD `src` `dest` 

> 为避免 ADD命令带来的未知风险和复杂性，可以使用COPY命令替代ADD命令

## 2.11. COPY（复制文件）

复制本地主机的src为容器中的dest，目标路径不存在时会自动创建。

格式：COPY `src` `dest`

## 2.12. VOLUME（指定挂载点）[设置指令]

创建一个可以从本地主机或其他容器挂载的挂载点，使容器中的一个目录具有持久化存储数据的功能，该目录可以被容器本身使用也可以被其他容器使用。

格式：VOLUME ["`mountpoint`"] 

其他容器使用共享数据卷：docker run -t -i -rm -volumes-from container1 image2 bash [container1为第一个容器的ID，image2为第二个容器运行image的名字。]

## 2.13. WORKDIR（切换目录）[设置指令]

相当于cd命令，可以多次切换目录，为RUN,CMD,ENTRYPOINT配置工作目录。可以使用多个WORKDIR的命令，后续命令如果是相对路径则是在上一级路径的基础上执行[类似cd的功能]。

格式：WORKDIR /path/to/workdir

## 2.14. ONBUILD（在子镜像中执行）

当所创建的镜像作为其他新创建镜像的基础镜像时执行的操作命令，即在创建本镜像时不运行，当作为别人的基础镜像时再在构建时运行（可认为基础镜像为父镜像，而该命令即在它的子镜像构建时运行，相当于在子镜像构建时多加了一些命令）。

格式：ONBUILD `Dockerfile关键字` 

# 3. dockerfile示例

**最佳实践**

- 镜像可以分为三层：系统基础镜像、业务基础镜像、业务镜像。
- 尽量将不变的镜像操作放dockerfile前面。
- 一类RUN命令操作可以通过`\`和`&&`方式组合成一条RUN命令。
- dockerfile尽量清晰简洁。

**文件目录**

```bash
./
|-- Dockerfile
|-- docker-entrypoint.sh
|-- dumb-init
|-- conf    # 配置文件路径
|   `-- app_conf.py  
|-- pkg   # 安装包路径
|   `-- install.tar.gz
|-- run.sh  # 启动脚本
```

**dockerfile示例**

```
FROM centos:latest
LABEL maintainer="xxx@xxx.com"

ARG APP=appname
ENV APP ${APP}

# copy and install app 
COPY conf/app_conf.py /usr/local/app/app_conf/app_conf.py
COPY pkg/${APP}-*-install.tar.gz /data/${APP}-install.tar.gz
RUN mkdir -p /data/${APP} \
    && tar -zxvf /data/${APP}-install.tar.gz -C /data/${APP} \
    && cd /data/${APP}/${APP}* \
    && ./install.sh

WORKDIR /usr/local/app/

# init
COPY dumb-init /usr/bin/dumb-init
COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/usr/bin/dumb-init", "--","/docker-entrypoint.sh"]

COPY run.sh /run.sh
RUN chmod +x /run.sh
CMD ["/run.sh"]
```

# 4. docker build

指定dockerfile文件构建

> 默认不指定dockerfile文件名，则读取指定路径的Dockerfile

```bash
docker build -t <image_name> -f <dockerfile_name> <dockerfile_path>
```

**docker build --help**

```bash
docker build --help

Usage:	docker build [OPTIONS] PATH | URL | -

Build an image from a Dockerfile

Options:
      --add-host list           Add a custom host-to-IP mapping (host:ip)
      --build-arg list          Set build-time variables
      --cache-from strings      Images to consider as cache sources
      --cgroup-parent string    Optional parent cgroup for the container
      --compress                Compress the build context using gzip
      --cpu-period int          Limit the CPU CFS (Completely Fair Scheduler) period
      --cpu-quota int           Limit the CPU CFS (Completely Fair Scheduler) quota
  -c, --cpu-shares int          CPU shares (relative weight)
      --cpuset-cpus string      CPUs in which to allow execution (0-3, 0,1)
      --cpuset-mems string      MEMs in which to allow execution (0-3, 0,1)
      --disable-content-trust   Skip image verification (default true)
  -f, --file string             Name of the Dockerfile (Default is 'PATH/Dockerfile')
      --force-rm                Always remove intermediate containers
      --iidfile string          Write the image ID to the file
      --isolation string        Container isolation technology
      --label list              Set metadata for an image
  -m, --memory bytes            Memory limit
      --memory-swap bytes       Swap limit equal to memory plus swap: '-1' to enable unlimited swap
      --network string          Set the networking mode for the RUN instructions during build (default "default")
      --no-cache                Do not use cache when building the image
      --pull                    Always attempt to pull a newer version of the image
  -q, --quiet                   Suppress the build output and print image ID on success
      --rm                      Remove intermediate containers after a successful build (default true)
      --security-opt strings    Security options
      --shm-size bytes          Size of /dev/shm
  -t, --tag list                Name and optionally a tag in the 'name:tag' format
      --target string           Set the target build stage to build.
      --ulimit ulimit           Ulimit options (default [])
```

参考：

- https://docs.docker.com/engine/reference/builder/