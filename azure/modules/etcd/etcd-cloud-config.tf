provider "gzip" {
  compressionlevel = "BestCompression"
}

resource "gzip_me" "kube-apiserver" {
  input = "${ data.template_file.kube-apiserver.rendered }"
}
resource "gzip_me" "cloud_config" {
  input = "${ var.cloud_config }"
}

resource "gzip_me" "ca" {
  input = "${ var.ca }"
}

resource "gzip_me" "k8s_etcd" {
  input = "${ var.k8s_etcd }"
}

resource "gzip_me" "k8s_etcd_key" {
  input = "${ var.k8s_etcd_key }"
}

resource "gzip_me" "k8s_apiserver" {
  input = "${ var.k8s_apiserver }"
}

resource "gzip_me" "k8s_apiserver_key" {
  input = "${ var.k8s_apiserver_key }"
}

data "template_file" "kube-apiserver" {
  template = "${ file( "${ path.module }/kube-apiserver.yml" )}"
  vars {
    internal_tld = "${ var.internal_tld }"
    service_cidr = "${ var.service_cidr }"
    hyperkube = "${ var.kubelet_aci }:${ var.kubelet_version }"
    kubelet_aci = "${ var.kubelet_aci }"
    kubelet_version = "${ var.kubelet_version }"
  }
}

data "template_file" "etcd-cloud-config" {
  count = "${ var.master_node_count }"
  template = "${ file( "${ path.module }/etcd-cloud-config.yml" )}"

  vars {
    # bucket = "${ var.s3_bucket }"
    cluster_domain = "${ var.cluster_domain }"
    cluster-token = "etcd-cluster-${ var.name }"
    dns_service_ip = "${ var.dns_service_ip }"
    fqdn = "etcd${ count.index + 1 }.${ var.internal_tld }"
    hostname = "etcd${ count.index + 1 }"
    kubelet_image_url = "${ var.kubelet_image_url }"
    kubelet_image_tag = "${ var.kubelet_image_tag }"
    internal_tld = "${ var.internal_tld }"
    pod_cidr = "${ var.pod_cidr }"
    location = "${ var.location }"
    service_cidr = "${ var.service_cidr }"
    cloud_config = "${ gzip_me.cloud_config }"
    ca = "${ gzip_me.ca.output }"
    k8s_etcd = "${ gzip_me.k8s_etcd.output }"
    k8s_etcd_key = "${ gzip_me.k8s_etcd_key.output }"
    k8s_apiserver = "${ gzip_me.k8s_apiserver.output }"
    k8s_apiserver_key = "${ gzip_me.k8s_apiserver_key.output }"
    k8s-apiserver-yml = "${ gzip_me.kube-apiserver.output }"
    node-ip = "${ element(azurerm_network_interface.cncf.*.private_ip_address, count.index) }"

  }
}
