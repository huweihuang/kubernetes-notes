# 1. ETCD资源类型

There are three types of resources in etcd

- `permission resources`: users and roles in the user store
- `key-value resources`: key-value pairs in the key-value store
- `settings resources`: security settings, auth settings, and dynamic etcd cluster settings (election/heartbeat)

# 2. 权限资源

**Users**：user用来设置身份认证（user：passwd），一个用户可以拥有多个角色，每个角色被分配一定的权限（只读、只写、可读写），用户分为root用户和非root用户。

**Roles**：角色用来关联权限，角色主要三类：root角色。默认创建root用户时即创建了root角色，该角色拥有所有权限；guest角色，默认自动创建，主要用于非认证使用。普通角色，由root用户创建角色，并分配指定权限。

注意：如果没有指定任何验证方式，即没显示指定以什么用户进行访问，那么默认会设定为 guest 角色。默认情况下 guest 也是具有全局访问权限的。如果不希望未授权就获取或修改etcd的数据，则可收回guest角色的权限或删除该角色，etcdctl role revoke 。

**Permissions**:权限分为只读、只写、可读写三种权限，权限即对指定目录或key的读写权限。

# 3. ETCD访问控制

## 3.1. 访问控制相关命令

```bash
NAME:
   etcdctl - A simple command line client for etcd.
USAGE:
   etcdctl [global options] command [command options] [arguments...]
VERSION:
   2.2.0
COMMANDS:
   user         user add, grant and revoke subcommands
   role         role add, grant and revoke subcommands
   auth         overall auth controls  
GLOBAL OPTIONS:
   --peers, -C          a comma-delimited list of machine addresses in the cluster (default: "http://127.0.0.1:4001,http://127.0.0.1:2379")
   --endpoint           a comma-delimited list of machine addresses in the cluster (default: "http://127.0.0.1:4001,http://127.0.0.1:2379")
   --cert-file          identify HTTPS client using this SSL certificate file
   --key-file           identify HTTPS client using this SSL key file
   --ca-file            verify certificates of HTTPS-enabled servers using this CA bundle
   --username, -u       provide username[:password] and prompt if password is not supplied.
   --timeout '1s'       connection timeout per request
```

## 3.2. user相关命令

```bash
[root@localhost etcd]# etcdctl user --help
NAME:
   etcdctl user - user add, grant and revoke subcommands
USAGE:
   etcdctl user command [command options] [arguments...]
COMMANDS:
   add      add a new user for the etcd cluster
   get      get details for a user
   list     list all current users
   remove   remove a user for the etcd cluster
   grant    grant roles to an etcd user
   revoke   revoke roles for an etcd user
   passwd   change password for a user
   help, h  Shows a list of commands or help for one command
    
OPTIONS:
   --help, -h   show help
```

## 3.2.1. 添加root用户并设置密码

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) user add root

## 3.2.2. 添加非root用户并设置密码

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:123 user add huwh

## 3.2.3. 查看当前所有用户

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:123 user list

## 3.2.4. 将用户添加到对应角色

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:123 user grant --roles test1 phpor

## 3.2.5. 查看用户拥有哪些角色

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:123 user get phpor

## 3.3. role相关命令

```bash
[root@localhost etcd]# etcdctl role --help
NAME:
   etcdctl role - role add, grant and revoke subcommands
USAGE:
   etcdctl role command [command options] [arguments...]
COMMANDS:
   add      add a new role for the etcd cluster
   get      get details for a role
   list     list all roles
   remove   remove a role from the etcd cluster
   grant    grant path matches to an etcd role
   revoke   revoke path matches for an etcd role
   help, h  Shows a list of commands or help for one command
    
OPTIONS:
   --help, -h   show help
```

## 3.3.1. 添加角色

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:2379 role add test1

## 3.3.2. 查看所有角色

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:123 role list

## 3.3.3. 给角色分配权限

```bash
[root@localhost etcd]# etcdctl role grant --help
NAME:
   grant - grant path matches to an etcd role
USAGE:
   command grant [command options] [arguments...]
OPTIONS:
   --path   Path granted for the role to access
   --read   Grant read-only access
   --write  Grant write-only access
   --readwrite  Grant read-write access
```

1、只包含目录
etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:123 role grant --readwrite --path /test1 test1

2、包括目录和子目录或文件 
etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:123 role grant --readwrite --path /test1/* test1

## 3.3.4. 查看角色所拥有的权限

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) --username root:2379 role get test1

## 3.4. auth相关操作

```bash
[root@localhost etcd]# etcdctl auth --help
NAME:
   etcdctl auth - overall auth controls
USAGE:
   etcdctl auth command [command options] [arguments...]
COMMANDS:
   enable   enable auth access controls
   disable  disable auth access controls
   help, h  Shows a list of commands or help for one command
    
OPTIONS:
   --help, -h   show help
```

## 3.4.1. 开启认证

etcdctl --endpoints [http://172.16.22.36:2379](http://172.16.22.36:2379/) auth enable

# 4. 访问控制设置步骤

| 顺序   | 步骤                   | 命令                                       |
| ---- | -------------------- | ---------------------------------------- |
| 1    | 添加root用户             | etcdctl --endpoints http://<ip>:<port> user add root |
| 2    | 开启认证                 | etcdctl --endpoints http://<ip>:<port> auth enable |
| 3    | 添加非root用户            | etcdctl --endpoints http://<ip>:<port> –username root:<passwd> user add <user> |
| 4    | 添加角色                 | etcdctl --endpoints http://<ip>:<port> –username root:<passwd> role add <role> |
| 5    | 给角色授权（只读、只写、可读写）     | etcdctl --endpoints http://<ip>:<port> –username root:<passwd> role grant --readwrite --path <path> <role> |
| 6    | 给用户分配角色（即分配了角色对应的权限） | etcdctl --endpoints http://<ip>:<port> –username root:<passwd> user grant --roles <role> <user> |

# 5. 访问认证的API调用

更多参考

- https://coreos.com/etcd/docs/latest/v2/auth_api.html

- https://coreos.com/etcd/docs/latest/v2/authentication.html
