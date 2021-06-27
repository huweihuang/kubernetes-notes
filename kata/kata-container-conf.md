# 1. 配置文件路径

默认的配置文件位于`/usr/share/defaults/kata-containers/configuration.toml`，如果`/etc/kata-containers/configuration.toml`的配置文件存在，则会替代默认的配置文件。

查看配置文件的路径命令如下：

```bash
# kata-runtime --kata-show-default-config-paths
/etc/kata-containers/configuration.toml
/usr/share/defaults/kata-containers/configuration.toml
```

指定自定义配置文件运行

```bash
kata-runtime --kata-config=/some/where/configuration.toml ...
```

# 2. kata-env

查看runtime使用到的环境参数，

```bash
kata-runtime kata-env
```

输出内容如下：

```bash
[Meta]
  Version = "1.0.23"

[Runtime]
  Debug = false
  Trace = false
  DisableGuestSeccomp = true
  DisableNewNetNs = false
  Path = "/usr/bin/kata-runtime"
  [Runtime.Version]
    Semver = "1.7.2"
    Commit = "9b9282693cfbcf70d442916bea56771cc6fc3afe"
    OCI = "1.0.1-dev"
  [Runtime.Config]
    Path = "/usr/share/defaults/kata-containers/configuration.toml"

[Hypervisor]
  MachineType = "pc"
  Version = "QEMU emulator version 2.11.0\nCopyright (c) 2003-2017 Fabrice Bellard and the QEMU Project developers"
  Path = "/usr/bin/qemu-lite-system-x86_64"
  BlockDeviceDriver = "virtio-scsi"
  EntropySource = "/dev/urandom"
  Msize9p = 8192
  MemorySlots = 10
  Debug = false
  UseVSock = false
  SharedFS = "virtio-9p"

[Image]
  Path = "/usr/share/kata-containers/kata-containers-image_centos_1.7.2_agent_20190702.img"

[Kernel]
  Path = "/usr/share/kata-containers/vmlinuz-4.19.28.42-6.1.container"
  Parameters = "init=/usr/lib/systemd/systemd systemd.unit=kata-containers.target systemd.mask=systemd-networkd.service systemd.mask=systemd-networkd.socket systemd.mask=systemd-journald.service systemd.mask=systemd-journald.socket systemd.mask=systemd-journal-flush.service systemd.mask=systemd-journald-dev-log.socket systemd.mask=systemd-udevd.service systemd.mask=systemd-udevd.socket systemd.mask=systemd-udev-trigger.service systemd.mask=systemd-udevd-kernel.socket systemd.mask=systemd-udevd-control.socket systemd.mask=systemd-timesyncd.service systemd.mask=systemd-update-utmp.service systemd.mask=systemd-tmpfiles-setup.service systemd.mask=systemd-tmpfiles-cleanup.service systemd.mask=systemd-tmpfiles-cleanup.timer systemd.mask=tmp.mount systemd.mask=systemd-random-seed.service systemd.mask=systemd-coredump@.service"

[Initrd]
  Path = ""

[Proxy]
  Type = "kataProxy"
  Version = "kata-proxy version 1.7.2-a56df7c"
  Path = "/usr/libexec/kata-containers/kata-proxy"
  Debug = false

[Shim]
  Type = "kataShim"
  Version = "kata-shim version 1.7.2-2ea178c"
  Path = "/usr/libexec/kata-containers/kata-shim"
  Debug = false

[Agent]
  Type = "kata"
  Debug = false
  Trace = false
  TraceMode = ""
  TraceType = ""

[Host]
  Kernel = "4.14.105-1-tlinux3-0008"
  Architecture = "amd64"
  VMContainerCapable = true
  SupportVSocks = true
  [Host.Distro]
    Name = "Tencent tlinux"
    Version = "2.2"
  [Host.CPU]
    Vendor = "GenuineIntel"
    Model = "Intel(R) Xeon(R) CPU           X3440  @ 2.53GHz"

[Netmon]
  Version = "kata-netmon version 1.7.2"
  Path = "/usr/libexec/kata-containers/kata-netmon"
  Debug = false
  Enable = false
```

# 3. configuration.toml

```bash
# Copyright (c) 2017-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# XXX: WARNING: this file is auto-generated.
# XXX:
# XXX: Source file: "cli/config/configuration-qemu.toml.in"
# XXX: Project:
# XXX:   Name: Kata Containers
# XXX:   Type: kata

[hypervisor.qemu]
path = "/usr/bin/qemu-lite-system-x86_64"
kernel = "/usr/share/kata-containers/vmlinuz.container"
image = "/usr/share/kata-containers/kata-containers.img"
machine_type = "pc"

# Optional space-separated list of options to pass to the guest kernel.
# For example, use `kernel_params = "vsyscall=emulate"` if you are having
# trouble running pre-2.15 glibc.
#
# WARNING: - any parameter specified here will take priority over the default
# parameter value of the same name used to start the virtual machine.
# Do not set values here unless you understand the impact of doing so as you
# may stop the virtual machine from booting.
# To see the list of default parameters, enable hypervisor debug, create a
# container and look for 'default-kernel-parameters' log entries.
kernel_params = ""

# Path to the firmware.
# If you want that qemu uses the default firmware leave this option empty
firmware = ""

# Machine accelerators
# comma-separated list of machine accelerators to pass to the hypervisor.
# For example, `machine_accelerators = "nosmm,nosmbus,nosata,nopit,static-prt,nofw"`
machine_accelerators=""

# Default number of vCPUs per SB/VM:
# unspecified or 0                --> will be set to 1
# < 0                             --> will be set to the actual number of physical cores
# > 0 <= number of physical cores --> will be set to the specified number
# > number of physical cores      --> will be set to the actual number of physical cores
default_vcpus = 1

# Default maximum number of vCPUs per SB/VM:
# unspecified or == 0             --> will be set to the actual number of physical cores or to the maximum number
#                                     of vCPUs supported by KVM if that number is exceeded
# > 0 <= number of physical cores --> will be set to the specified number
# > number of physical cores      --> will be set to the actual number of physical cores or to the maximum number
#                                     of vCPUs supported by KVM if that number is exceeded
# WARNING: Depending of the architecture, the maximum number of vCPUs supported by KVM is used when
# the actual number of physical cores is greater than it.
# WARNING: Be aware that this value impacts the virtual machine's memory footprint and CPU
# the hotplug functionality. For example, `default_maxvcpus = 240` specifies that until 240 vCPUs
# can be added to a SB/VM, but the memory footprint will be big. Another example, with
# `default_maxvcpus = 8` the memory footprint will be small, but 8 will be the maximum number of
# vCPUs supported by the SB/VM. In general, we recommend that you do not edit this variable,
# unless you know what are you doing.
default_maxvcpus = 0

# Bridges can be used to hot plug devices.
# Limitations:
# * Currently only pci bridges are supported
# * Until 30 devices per bridge can be hot plugged.
# * Until 5 PCI bridges can be cold plugged per VM.
#   This limitation could be a bug in qemu or in the kernel
# Default number of bridges per SB/VM:
# unspecified or 0   --> will be set to 1
# > 1 <= 5           --> will be set to the specified number
# > 5                --> will be set to 5
default_bridges = 1

# Default memory size in MiB for SB/VM.
# If unspecified then it will be set 2048 MiB.
default_memory = 2048
#
# Default memory slots per SB/VM.
# If unspecified then it will be set 10.
# This is will determine the times that memory will be hotadded to sandbox/VM.
#memory_slots = 10

# The size in MiB will be plused to max memory of hypervisor.
# It is the memory address space for the NVDIMM devie.
# If set block storage driver (block_device_driver) to "nvdimm",
# should set memory_offset to the size of block device.
# Default 0
#memory_offset = 0

# Disable block device from being used for a container's rootfs.
# In case of a storage driver like devicemapper where a container's
# root file system is backed by a block device, the block device is passed
# directly to the hypervisor for performance reasons.
# This flag prevents the block device from being passed to the hypervisor,
# 9pfs is used instead to pass the rootfs.
disable_block_device_use = false

# Shared file system type:
#   - virtio-9p (default)
#   - virtio-fs
shared_fs = "virtio-9p"

# Path to vhost-user-fs daemon.
virtio_fs_daemon = "/usr/bin/virtiofsd-x86_64"

# Default size of DAX cache in MiB
virtio_fs_cache_size = 1024

# Cache mode:
#
#  - none
#    Metadata, data, and pathname lookup are not cached in guest. They are
#    always fetched from host and any changes are immediately pushed to host.
#
#  - auto
#    Metadata and pathname lookup cache expires after a configured amount of
#    time (default is 1 second). Data is cached while the file is open (close
#    to open consistency).
#
#  - always
#    Metadata, data, and pathname lookup are cached in guest and never expire.
virtio_fs_cache = "always"

# Block storage driver to be used for the hypervisor in case the container
# rootfs is backed by a block device. This is virtio-scsi, virtio-blk
# or nvdimm.
block_device_driver = "virtio-scsi"

# Specifies cache-related options will be set to block devices or not.
# Default false
#block_device_cache_set = true

# Specifies cache-related options for block devices.
# Denotes whether use of O_DIRECT (bypass the host page cache) is enabled.
# Default false
#block_device_cache_direct = true

# Specifies cache-related options for block devices.
# Denotes whether flush requests for the device are ignored.
# Default false
#block_device_cache_noflush = true

# Enable iothreads (data-plane) to be used. This causes IO to be
# handled in a separate IO thread. This is currently only implemented
# for SCSI.
#
enable_iothreads = false

# Enable pre allocation of VM RAM, default false
# Enabling this will result in lower container density
# as all of the memory will be allocated and locked
# This is useful when you want to reserve all the memory
# upfront or in the cases where you want memory latencies
# to be very predictable
# Default false
#enable_mem_prealloc = true

# Enable huge pages for VM RAM, default false
# Enabling this will result in the VM memory
# being allocated using huge pages.
# This is useful when you want to use vhost-user network
# stacks within the container. This will automatically
# result in memory pre allocation
#enable_hugepages = true

# Enable swap of vm memory. Default false.
# The behaviour is undefined if mem_prealloc is also set to true
#enable_swap = true

# This option changes the default hypervisor and kernel parameters
# to enable debug output where available. This extra output is added
# to the proxy logs, but only when proxy debug is also enabled.
#
# Default false
#enable_debug = true

# Disable the customizations done in the runtime when it detects
# that it is running on top a VMM. This will result in the runtime
# behaving as it would when running on bare metal.
#
#disable_nesting_checks = true

# This is the msize used for 9p shares. It is the number of bytes
# used for 9p packet payload.
#msize_9p = 8192

# If true and vsocks are supported, use vsocks to communicate directly
# with the agent and no proxy is started, otherwise use unix
# sockets and start a proxy to communicate with the agent.
# Default false
#use_vsock = true

# VFIO devices are hotplugged on a bridge by default.
# Enable hotplugging on root bus. This may be required for devices with
# a large PCI bar, as this is a current limitation with hotplugging on
# a bridge. This value is valid for "pc" machine type.
# Default false
#hotplug_vfio_on_root_bus = true

# If host doesn't support vhost_net, set to true. Thus we won't create vhost fds for nics.
# Default false
#disable_vhost_net = true
#
# Default entropy source.
# The path to a host source of entropy (including a real hardware RNG)
# /dev/urandom and /dev/random are two main options.
# Be aware that /dev/random is a blocking source of entropy.  If the host
# runs out of entropy, the VMs boot time will increase leading to get startup
# timeouts.
# The source of entropy /dev/urandom is non-blocking and provides a
# generally acceptable source of entropy. It should work well for pretty much
# all practical purposes.
#entropy_source= "/dev/urandom"

# Path to OCI hook binaries in the *guest rootfs*.
# This does not affect host-side hooks which must instead be added to
# the OCI spec passed to the runtime.
#
# You can create a rootfs with hooks by customizing the osbuilder scripts:
# https://github.com/kata-containers/osbuilder
#
# Hooks must be stored in a subdirectory of guest_hook_path according to their
# hook type, i.e. "guest_hook_path/{prestart,postart,poststop}".
# The agent will scan these directories for executable files and add them, in
# lexicographical order, to the lifecycle of the guest container.
# Hooks are executed in the runtime namespace of the guest. See the official documentation:
# https://github.com/opencontainers/runtime-spec/blob/v1.0.1/config.md#posix-platform-hooks
# Warnings will be logged if any error is encountered will scanning for hooks,
# but it will not abort container execution.
#guest_hook_path = "/usr/share/oci/hooks"

[factory]
# VM templating support. Once enabled, new VMs are created from template
# using vm cloning. They will share the same initial kernel, initramfs and
# agent memory by mapping it readonly. It helps speeding up new container
# creation and saves a lot of memory if there are many kata containers running
# on the same host.
#
# When disabled, new VMs are created from scratch.
#
# Note: Requires "initrd=" to be set ("image=" is not supported).
#
# Default false
#enable_template = true

# Specifies the path of template.
#
# Default "/run/vc/vm/template"
#template_path = "/run/vc/vm/template"

# The number of caches of VMCache:
# unspecified or == 0   --> VMCache is disabled
# > 0                   --> will be set to the specified number
#
# VMCache is a function that creates VMs as caches before using it.
# It helps speed up new container creation.
# The function consists of a server and some clients communicating
# through Unix socket.  The protocol is gRPC in protocols/cache/cache.proto.
# The VMCache server will create some VMs and cache them by factory cache.
# It will convert the VM to gRPC format and transport it when gets
# requestion from clients.
# Factory grpccache is the VMCache client.  It will request gRPC format
# VM and convert it back to a VM.  If VMCache function is enabled,
# kata-runtime will request VM from factory grpccache when it creates
# a new sandbox.
#
# Default 0
#vm_cache_number = 0

# Specify the address of the Unix socket that is used by VMCache.
#
# Default /var/run/kata-containers/cache.sock
#vm_cache_endpoint = "/var/run/kata-containers/cache.sock"

[proxy.kata]
path = "/usr/libexec/kata-containers/kata-proxy"

# If enabled, proxy messages will be sent to the system log
# (default: disabled)
#enable_debug = true

[shim.kata]
path = "/usr/libexec/kata-containers/kata-shim"

# If enabled, shim messages will be sent to the system log
# (default: disabled)
#enable_debug = true

# If enabled, the shim will create opentracing.io traces and spans.
# (See https://www.jaegertracing.io/docs/getting-started).
#
# Note: By default, the shim runs in a separate network namespace. Therefore,
# to allow it to send trace details to the Jaeger agent running on the host,
# it is necessary to set 'disable_new_netns=true' so that it runs in the host
# network namespace.
#
# (default: disabled)
#enable_tracing = true

[agent.kata]
# If enabled, make the agent display debug-level messages.
# (default: disabled)
#enable_debug = true

# Enable agent tracing.
#
# If enabled, the default trace mode is "dynamic" and the
# default trace type is "isolated". The trace mode and type are set
# explicity with the `trace_type=` and `trace_mode=` options.
#
# Notes:
#
# - Tracing is ONLY enabled when `enable_tracing` is set: explicitly
#   setting `trace_mode=` and/or `trace_type=` without setting `enable_tracing`
#   will NOT activate agent tracing.
#
# - See https://github.com/kata-containers/agent/blob/master/TRACING.md for
#   full details.
#
# (default: disabled)
#enable_tracing = true
#
#trace_mode = "dynamic"
#trace_type = "isolated"

[netmon]
# If enabled, the network monitoring process gets started when the
# sandbox is created. This allows for the detection of some additional
# network being added to the existing network namespace, after the
# sandbox has been created.
# (default: disabled)
#enable_netmon = true

# Specify the path to the netmon binary.
path = "/usr/libexec/kata-containers/kata-netmon"

# If enabled, netmon messages will be sent to the system log
# (default: disabled)
#enable_debug = true

[runtime]
# If enabled, the runtime will log additional debug messages to the
# system log
# (default: disabled)
#enable_debug = true
#
# Internetworking model
# Determines how the VM should be connected to the
# the container network interface
# Options:
#
#   - bridged
#     Uses a linux bridge to interconnect the container interface to
#     the VM. Works for most cases except macvlan and ipvlan.
#
#   - macvtap
#     Used when the Container network interface can be bridged using
#     macvtap.
#
#   - none
#     Used when customize network. Only creates a tap device. No veth pair.
#
#   - tcfilter
#     Uses tc filter rules to redirect traffic from the network interface
#     provided by plugin to a tap interface connected to the VM.
#
internetworking_model="tcfilter"

# disable guest seccomp
# Determines whether container seccomp profiles are passed to the virtual
# machine and applied by the kata agent. If set to true, seccomp is not applied
# within the guest
# (default: true)
disable_guest_seccomp=true

# If enabled, the runtime will create opentracing.io traces and spans.
# (See https://www.jaegertracing.io/docs/getting-started).
# (default: disabled)
#enable_tracing = true

# If enabled, the runtime will not create a network namespace for shim and hypervisor processes.
# This option may have some potential impacts to your host. It should only be used when you know what you're doing.
# `disable_new_netns` conflicts with `enable_netmon`
# `disable_new_netns` conflicts with `internetworking_model=bridged` and `internetworking_model=macvtap`. It works only
# with `internetworking_model=none`. The tap device will be in the host network namespace and can connect to a bridge
# (like OVS) directly.
# If you are using docker, `disable_new_netns` only works with `docker run --net=none`
# (default: false)
#disable_new_netns = true

# Enabled experimental feature list, format: ["a", "b"].
# Experimental features are features not stable enough for production,
# They may break compatibility, and are prepared for a big version bump.
# Supported experimental features:
# 1. "newstore": new persist storage driver which breaks backward compatibility,
#				expected to move out of experimental in 2.0.0.
# (default: [])
experimental=[]
```





参考：

- https://github.com/kata-containers/runtime#configuration