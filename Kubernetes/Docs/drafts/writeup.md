# Kuberentes Walkthrough 

## Prologue

This walkthrough started life as a post-mortem. The notes for it read eerily similarly to a choose your own adventure book, countles pages dog eared and stuffed with markers as virtually every choice seemed to eventually lead to dead ends and certain doom.

The path is now beaten and what follows describes the dos and don'ts chronologically for your edification.

## Picking a host operating system

<sub><sub>_"If you wish to make an apple pie from scratch, you must first invent the universe."_ -- [Carl Sagan](https://www.youtube.com/watch?v=7s664NsLeFM)</sub></sub>

Starting out on AWS one might be tempted to quick start from the web console and opt for Amazon Linux AMI. But that is not a portable choice. To keep your options open (perhaps in the future you'll want to run on another cloud provider, baremetal, or your laptop) it is best to opt for something like CentOS, Debian, or CoreOS.

This is not an easy choice and there is no right answer. Each option brings along its own dependencies, problems, and bugs. But since choose we must we will go down the CentOS direction of this decision tree and see how far it takes us.

### CentOS 7

[Official CentOS images](https://wiki.centos.org/Cloud/AWS) are provided for us on the AWS Marketplace.

To avoid ending up with deprecated AMI's and outdated images it is recommended to grab the AMI id programatically (`aws --region us-west-2 ec2 describe-images --owners aws-marketplace --filters Name=product-code,Values=aw0evgkw8e5c1q413zgy5pjce`) and in case of a response with multiple ids pick the one with the most recent creation date as well as running `yum update` as the first step in your build process.

### Default Docker is strongly discouraged for production use

Docker is not actually a hard requirement for Kubernetes, but this isn't about recommending alternative container runtimes. This is about the defaults being a hidden minefield.


What happens if you simply `yum install docker`?

> $ docker info


```
Containers: 0
Server Version: 1.10.3
Storage Driver: devicemapper
 Pool Name: docker-202:1-9467182-pool
 Pool Blocksize: 65.54 kB
 Base Device Size: 10.74 GB
 Backing Filesystem: xfs
 Data file: /dev/loop0
 Metadata file: /dev/loop1
 ..
 Data loop file: /var/lib/docker/devicemapper/devicemapper/data
 WARNING: Usage of loopback devices is strongly discouraged for production use. 
 Metadata loop file: /var/lib/docker/devicemapper/devicemapper/metadata
```

As you can see from the warning, the default Docker storage config that ships with CentOS 7 is not recommended for production use. Using devicemapper with loopback can lead to unpredictable behaviour. 

In fact, to give a bit of a look into this dead end if we follow the path all the way to a Kubernetes cluster you will see nodes coming up like this:

```
systemctl --failed
  UNIT                         LOAD   ACTIVE SUB    DESCRIPTION
● docker-storage-setup.service loaded failed failed Docker Storage Setup
● kdump.service                loaded failed failed Crash recovery kernel arming
● network.service              loaded failed failed LSB: Bring up/down networking
```

Along with the docker service there's docker-storage-setup. It looks for free space in the volume group of the root volume and attempts to setup a thin pool. If there is no free space it fails to set up an LVM thin pool and will fall back to using loopback devices. Which we are warned by docker itself is a `strongly discouraged` outcome.

This is insidious because depending on how many volumes your instance happens to spin up with (and how they're configured) you might never see this warning. Later you might end up in this edgecase but the cluster will still appear to be working.

For example if you have one hard-drive on bare-metal and no unallocated space this will always happen.

Only after some activity will xfs corruption in the docker image tree (`/var/lib/docker`) start to sporadically manifest itself and kubernetes nodes will mysteriously fail. 

#### Select a storage driver

Docker has a [pluggable storage driver architecture](https://docs.docker.com/engine/userguide/storagedriver/selectadriver/), the default is inappropriate and so you must carefully consider your options here. Getting this wrong will cascade all the way into hard to debug and reproduce bugs and broken clusters.

>Which storage driver should you choose?
Several factors influence the selection of a storage driver. However, these two facts must be kept in mind:

> - No single driver is well suited to every use-case
> - Storage drivers are improving and evolving all of the time

The docker docs don't take a position. If one doesn't want to make assumptions about how many disks a machine has (laptops, baremetal servers with one drive, 'etc) direct LVM is out. 

AUFS [was the original backend](http://jpetazzo.github.io/assets/2015-03-03-not-so-deep-dive-into-docker-storage-drivers.html#28) used by docker but is not in the mainline kernel (it is included by debian/ubuntu). 

Overlay is in mainline and supported as a Technology Preview by RHEL.

Additionally _"Many people consider OverlayFS as the future of the Docker storage driver"_. It is the future proof way to go (Incidently this issue is currently one of the reasons to opt for CentOS over debian/ubuntu or CoreOS).

##### Overlay Dependencies 

- CentOS 7.2
- _"Only XFS is currently supported for use as a lower layer file system."_
- _"/etc/sysconfig/docker must not contain --selinux-enabled"_ (for now)

With the above satisfied, to enable overlay simply:

`echo "overlay" > /etc/modules-load.d/overlay.conf`

And add the flag (`--storage-driver=overlay`) in the docker service file or DOCKER_OPTS (`/etc/default/docker`).

This requires a reboot, but first...

### Properly configure netfilter

`docker info` had another complaint.

```
WARNING: bridge-nf-call-iptables is disabled
WARNING: bridge-nf-call-ip6tables is disabled
```

This toggles whether packets traversing the bridge are forwarded to iptables.
This is [docker issue #24809](https://github.com/docker/docker/issues/24809) and _could_ be ignored ("either /proc/sys/net/bridge/bridge-nf-call-iptables doesn't exist or is set to 0"). CentOS and most distros default this to 0.

If I was writing a choose your own adventure book this is the point I'd write that thunder rumbles in the distance, a quiet intensity.

If you follow _this_ dead end all the way to a Kubernetes cluster you will find out that **kube-proxy requires that bridged traffic passes through netfilter**. So that path should absolutely exist otherwise you have a problem.

Furthermore you'll find that [kube-proxy will not work properly with Weave Net on Centos](https://github.com/kubernetes/kubernetes/issues/33790) if this isn't toggled to 1. At first everything will appear to be fine, the problem only manifests itself by kubernetes service endpoints not being routable. 

To get rid of these warnings you might try:

`echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables`

`echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables`

This would toggle the setting but not persist after a reboot.

These settings used to live in /etc/sysctl.conf the contents of which nowadays are:

```
# System default settings live in /usr/lib/sysctl.d/00-system.conf.
# To override those settings, enter new settings here, or in an /etc/sysctl.d/<name>.conf file
```

This file is sourced on every invocation of `sysctl -p`.

Attempting to toggle via `sysctl -p` [gives the following error](https://github.com/ansible/ansible/issues/6272) under certain conditions:

```
error: "net.bridge.bridge-nf-call-ip6tables" is an unknown key
error: "net.bridge.bridge-nf-call-iptables" is an unknown key
```

Since `sysctl` runs at boot there's a very possible race condition [if the bridge module hasn't loaded yet](https://bugzilla.redhat.com/show_bug.cgi?id=1054178#c1) at that point. Making this a (sometimes) misleading error message.

The correct way to set this as of CentOS7:

> $ cat /usr/lib/sysctl.d/00-system.conf

```

# Kernel sysctl configuration file
#
# For binary values, 0 is disabled, 1 is enabled.  See sysctl(8) and
# sysctl.conf(5) for more details.

# Disable netfilter on bridges.
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0

```

> $ cat /usr/lib/sysctl.d/90-system.conf

```
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
```

This way systemd ensures these settings will be evaluated whenever a bridge module is loaded and the race condition is avoided.

Speaking of misleading error messages, kubernetes logs an [incorrect br-netfilter warning on Centos 7](https://github.com/kubernetes/kubernetes/issues/23385):

> proxier.go:205] missing br-netfilter module or unset br-nf-call-iptables; proxy may not work as intended

Stay the course, there's nothing else to toggle to make this warning go away, it is simply a false positive.

### Consider disabling selinux

With Overlay as the storage backend currently you can only run with selinux on the host. However, kubernetes uses a mechanism that injects special volumes into each container to expose service account tokens and [with selinux turned on secrets simply don't work](http://stackoverflow.com/questions/35338213/kubernetes-serviceaccounts-and-selinux/35347520#35347520).

The work around is to set the security context of volume on the kubernetes host (`sudo chcon -Rt svirt_sandbox_file_t /var/lib/kubelet`) or set selinux to permissive mode. 

Otherwise down the line [kubernetes add-ons](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons) will fail or behave unpredictably. For example KubeDNS will fail to authenticate with the master and dns lookups on service endpoints will fail. (Slightly differs from the bridge netfilter disabled problem described above which results in routing by ip intermittently failing)

Since there might be other selinux permissions necessary elsewhere consider turning off selinux entirely until this is properly pinned down upstream and documented.

### Correct CNI config	


Kubernetes supports [CNI Network Plugins](http://kubernetes.io/docs/admin/network-plugins/#cni) for interoperability. Setting up a network overlay requires this dependency.

Kubernetes 1.3.5 [broke the cni config](https://github.com/kubernetes/kubernetes/issues/30681) - as of that version it is neccessary to pull in the [cni release binaries](https://github.com/containernetworking/cni/releases) into the cni bin folder.

As of Kuberentes 1.4 the [flags to specify cni directories](https://github.com/kubernetes/kubernetes.github.io/pull/1516) changed and documentation was added pinning the minimum cni version to 0.2 and at least the `lo` binary.

### Other Dependencies

In https://github.com/kubernetes/kubernetes/issues/26093 additional undocumented dependencies have been identified and pinned as follows:

   - conntrack-tools
   - socat
   - bridge-utils
   
### AWS specific requirements & debugging

[Peeking under the hood of Kubernetes on AWS](https://github.com/kubernetes/kubernetes/blob/master/docs/design/aws_under_the_hood.md#tagging) you'll find:

> All AWS resources are tagged with a tag named "KubernetesCluster", with a value that is the unique cluster-id. This tag is used to identify a particular 'instance' of Kubernetes, even if two clusters are deployed into the same VPC. Resources are considered to belong to the same cluster if and only if they have the same value in the tag named "KubernetesCluster".

This isn't only neccessary to diffrentiate resources of two different clusters in the same VPC but also for the controller to discover and manage AWS resources (even if it has an entire VPC to itself).

Unfortunatly these tags are [not filtered on in a uniform manner across different resource types](https://github.com/cncf/demo/issues/144). 

A `kubectl create -f resource.yaml` succesfully submitted to kubernetes might not result in expected functionality (in this case a load balancer endpoint) even when the desired resource shows as `creating...` - it will show that indefinitely.

Since the problem doesn't bubble up to kubectl responses the only way to see that something is amiss is by carefully watching the controller log.

```
aws.go:2731] Error opening ingress rules for the load balancer to the instances: Multiple tagged security groups found for instance i-04bd9c4c8aa; ensure only the k8s security group is tagged
```

And reading the code at https://github.com/kubernetes/kubernetes/blob/master/pkg/cloudprovider/providers/aws/aws.go#L2783:

```
// Returns the first security group for an instance, or nil
// We only create instances with one security group, so we don't expect multiple security groups.
// However, if there are multiple security groups, we will choose the one tagged with our cluster filter.
// Otherwise we will return an error.
```

In this example the kubernetes masters and minions each have a security group, both security groups are tagged with "KubernetesCluster=<name>". Removing the tags from the master security group resolves this problem as now the controller receives an expected response from the AWS API.

## Conclusion

The most difficult bugs are the ones that occur far away from their origins. 

Even a slightly outdated version of the host OS can turn out to be insufficient. 

Picking the wrong storage backend can initially result in a functioning cluster. Nodes hang unpredictabily at some inderminent point down the line. Or not, depending how many disks you've started with.

Incorrect networking configurations are not necessarily catastrophic right away. Connectivity problems can manifest sporadically and only grow dire after reboots. 

Warning messages can erroneously complain missing dependencies haven't been resolved when they in fact have. Minor releases of kubernetes can have undocumented changes and undocumented dependencies. 

Critical Add-ons might work until they hit a codepath that requires permissions blocked by selinux. 

And unforseen combinations of AWS resources can confuse the controller and prevent it from deploying things with silent errors.

The permutations of host operating system kind and version, cloud providers and bare metal, minor and major versions of kubernetes and its dependencies, different types of overlay networks, and the state of resources allocated to the cluster result in a complex support metrix. 

Better smoke tests, e2e tests, and CI for all these combinations would likely catch many problems quicker. And most of all more and better documentation.