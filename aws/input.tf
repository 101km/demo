variable "name" { default = "aws" }
variable "aws_region" { default = "ap-southeast-2" }
variable "aws_key_name" { default = "aws" }
variable "aws_azs" { default = "ap-southeast-2a,ap-southeast-2b,ap-southeast-2c" }

variable "internal_tld" { default = "aws.cncf.demo" }
variable "cluster_domain" { default = "cluster.local" }
variable "etcd_ips" { default = "10.0.10.10,10.0.10.11,10.0.10.12" }
variable "vpc_cidr" { default = "10.0.0.0/16" }
variable "pod_cidr" { default = "10.2.0.0/16" }
variable "service_cidr"   { default = "10.3.0.0/24" }
variable "k8s_service_ip" { default = "10.3.0.1" }
variable "dns_service_ip" { default = "10.3.0.10" }
variable "allow_ssh_cidr" { default = "0.0.0.0/0" }

variable "admin_username" { default = "core" }
variable "aws_image_ami" { default = "ami-fde3e09e"} # channel/stable type/hvm
variable "aws_master_vm_size" { default = "m3.medium" }
variable "aws_worker_vm_size" { default = "m3.medium" }
variable "aws_bastion_vm_size" { default = "t2.nano" }

# Set from https://quay.io/repository/coreos/hyperkube?tab=tags
variable "kubelet_aci" { default = "quay.io/coreos/hyperkube"}
variable "kubelet_version" { default = "v1.5.1_coreos.0"}

variable "data_dir" { default = "/cncf/data/aws" }
