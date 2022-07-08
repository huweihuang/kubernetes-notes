# 1. FlexVolume介绍

Flexvolume提供了一种扩展k8s存储插件的方式，用户可以自定义自己的存储插件。类似的功能的实现还有CSI的方式。Flexvolume在k8s 1.8+以上版本提供GA功能版本。

# 2. 使用方式

在每个node节点安装存储插件二进制，该二进制实现flexvolume的相关接口，默认存储插件的存放路径为`/usr/libexec/kubernetes/kubelet-plugins/volume/exec/<vendor~driver>/<driver>`。

其中`vendor~driver`的名字需要和pod中flexVolume.driver的字段名字匹配，该字段名字通过`/`替换`~`。

例如：

- path:/usr/libexec/kubernetes/kubelet-plugins/volume/exec/foo~cifs/cifs

- pod中flexVolume.driver:foo/cifs

# 3. FlexVolume接口

节点上的存储插件需要实现以下的接口。

## 3.1. init

```
<driver executable> init
```

## 3.2. attach

```
<driver executable> attach <json options> <node name>
```

## 3.3. detach

```
<driver executable> detach <mount device> <node name>
```

## 3.4. waitforattach

```
<driver executable> waitforattach <mount device> <json options>
```

## 3.5. isattached

```
<driver executable> isattached <json options> <node name>
```

## 3.6. mountdevice

```
<driver executable> mountdevice <mount dir> <mount device> <json options>
```

## 3.7. unmountdevice

```
<driver executable> unmountdevice <mount device>
```

## 3.8. mount

```bash
<driver executable> mount <mount dir> <json options>
```

## 3.9. unmount

```bash
<driver executable> unmount <mount dir>
```

## 3.10. 插件输出

```json
{
	"status": "<Success/Failure/Not supported>",
	"message": "<Reason for success/failure>",
	"device": "<Path to the device attached. This field is valid only for attach & waitforattach call-outs>"
	"volumeName": "<Cluster wide unique name of the volume. Valid only for getvolumename call-out>"
	"attached": <True/False (Return true if volume is attached on the node. Valid only for isattached call-out)>
    "capabilities": <Only included as part of the Init response>
    {
        "attach": <True/False (Return true if the driver implements attach and detach)>
    }
}
```

# 4. 示例

## 4.1. pod的yaml文件内容

**nginx-nfs.yaml**

相关参数为flexVolume.driver等。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-nfs
  namespace: default
spec:
  containers:
  - name: nginx-nfs
    image: nginx
    volumeMounts:
    - name: test
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: test
    flexVolume:
      driver: "k8s/nfs"
      fsType: "nfs"
      options:
        server: "172.16.0.25"
        share: "dws_nas_scratch"
```

## 4.2. 插件脚本

nfs脚本实现了flexvolume的接口。

/usr/libexec/kubernetes/kubelet-plugins/volume/exec/k8s~nfs/nfs。

```bash
#!/bin/bash

# Copyright 2015 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Notes:
#  - Please install "jq" package before using this driver.
usage() {
	err "Invalid usage. Usage: "
	err "\t$0 init"
	err "\t$0 mount <mount dir> <json params>"
	err "\t$0 unmount <mount dir>"
	exit 1
}

err() {
	echo -ne $* 1>&2
}

log() {
	echo -ne $* >&1
}

ismounted() {
	MOUNT=`findmnt -n ${MNTPATH} 2>/dev/null | cut -d' ' -f1`
	if [ "${MOUNT}" == "${MNTPATH}" ]; then
		echo "1"
	else
		echo "0"
	fi
}

domount() {
	MNTPATH=$1

	NFS_SERVER=$(echo $2 | jq -r '.server')
	SHARE=$(echo $2 | jq -r '.share')

	if [ $(ismounted) -eq 1 ] ; then
		log '{"status": "Success"}'
		exit 0
	fi

	mkdir -p ${MNTPATH} &> /dev/null

	mount -t nfs ${NFS_SERVER}:/${SHARE} ${MNTPATH} &> /dev/null
	if [ $? -ne 0 ]; then
		err "{ \"status\": \"Failure\", \"message\": \"Failed to mount ${NFS_SERVER}:${SHARE} at ${MNTPATH}\"}"
		exit 1
	fi
	log '{"status": "Success"}'
	exit 0
}

unmount() {
	MNTPATH=$1
	if [ $(ismounted) -eq 0 ] ; then
		log '{"status": "Success"}'
		exit 0
	fi

	umount ${MNTPATH} &> /dev/null
	if [ $? -ne 0 ]; then
		err "{ \"status\": \"Failed\", \"message\": \"Failed to unmount volume at ${MNTPATH}\"}"
		exit 1
	fi

	log '{"status": "Success"}'
	exit 0
}

op=$1

if ! command -v jq >/dev/null 2>&1; then
	err "{ \"status\": \"Failure\", \"message\": \"'jq' binary not found. Please install jq package before using this driver\"}"
	exit 1
fi

if [ "$op" = "init" ]; then
	log '{"status": "Success", "capabilities": {"attach": false}}'
	exit 0
fi

if [ $# -lt 2 ]; then
	usage
fi

shift

case "$op" in
	mount)
		domount $*
		;;
	unmount)
		unmount $*
		;;
	*)
		log '{"status": "Not supported"}'
		exit 0
esac

exit 1
```



参考：

- https://github.com/kubernetes/community/blob/master/contributors/devel/sig-storage/flexvolume.md
- https://github.com/kubernetes/examples/tree/master/staging/volumes/flexvolume
- https://github.com/kubernetes/examples/blob/master/staging/volumes/flexvolume/nginx-nfs.yaml
- https://github.com/kubernetes/examples/blob/master/staging/volumes/flexvolume/nfs
