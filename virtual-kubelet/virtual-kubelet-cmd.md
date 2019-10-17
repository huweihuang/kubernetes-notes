# virtual-kubelet --help

```bash
#./virtual-kubelet --help
virtual-kubelet implements the Kubelet interface with a pluggable
backend implementation allowing users to create kubernetes nodes without running the kubelet.
This allows users to schedule kubernetes workloads on nodes that aren't running Kubernetes.

Usage:
  virtual-kubelet [flags]
  virtual-kubelet [command]

Available Commands:
  help        Help about any command
  providers   Show the list of supported providers
  version     Show the version of the program

Flags:
      --cluster-domain string                 kubernetes cluster-domain (default is 'cluster.local') (default "cluster.local")
      --disable-taint                         disable the virtual-kubelet node taint
      --enable-node-lease                     use node leases (1.13) for node heartbeats
      --full-resync-period duration           how often to perform a full resync of pods between kubernetes and the provider (default 1m0s)
  -h, --help                                  help for virtual-kubelet
      --klog.alsologtostderr                  log to standard error as well as files
      --klog.log_backtrace_at traceLocation   when logging hits line file:N, emit a stack trace (default :0)
      --klog.log_dir string                   If non-empty, write log files in this directory
      --klog.log_file string                  If non-empty, use this log file
      --klog.log_file_max_size uint           Defines the maximum size a log file can grow to. Unit is megabytes. If the value is 0, the maximum file size is unlimited. (default 1800)
      --klog.logtostderr                      log to standard error instead of files (default true)
      --klog.skip_headers                     If true, avoid header prefixes in the log messages
      --klog.skip_log_headers                 If true, avoid headers when opening log files
      --klog.stderrthreshold severity         logs at or above this threshold go to stderr (default 2)
      --klog.v Level                          number for the log level verbosity
      --klog.vmodule moduleSpec               comma-separated list of pattern=N settings for file-filtered logging
      --kubeconfig string                     kube config file to use for connecting to the Kubernetes API server (default "/root/.kube/config")
      --log-level string                      set the log level, e.g. "debug", "info", "warn", "error" (default "info")
      --metrics-addr string                   address to listen for metrics/stats requests (default ":10255")
      --namespace string                      kubernetes namespace (default is 'all')
      --nodename string                       kubernetes node name (default "virtual-kubelet")
      --os string                             Operating System (Linux/Windows) (default "Linux")
      --pod-sync-workers int                  set the number of pod synchronization workers (default 10)
      --provider string                       cloud provider
      --provider-config string                cloud provider configuration file
      --startup-timeout duration              How long to wait for the virtual-kubelet to start
      --trace-exporter strings                sets the tracing exporter to use, available exporters: [jaeger ocagent]
      --trace-sample-rate string              set probability of tracing samples
      --trace-service-name string             sets the name of the service used to register with the trace exporter (default "virtual-kubelet")
      --trace-tag map                         add tags to include with traces in key=value form

Use "virtual-kubelet [command] --help" for more information about a command.
```

