resource "azurerm_network_interface" "cncf" {
  count = "${ length( split(",", var.etcd-ips) ) }"
  name                = "etcd-interface${ count.index + 1 }"
  location            = "${ var.location }"
  resource_group_name = "${ var.name }"

  ip_configuration {
    name                          = "etcd-nic${ count.index + 1 }"
    subnet_id                     = "${ var.subnet-id }"
    private_ip_address_allocation = "static"
    private_ip_address            = "${ element( split(",", var.etcd-ips), count.index ) }"
    load_balancer_backend_address_pools_ids = ["${ azurerm_lb_backend_address_pool.cncf.id }"]
  }
}

resource "azurerm_virtual_machine" "cncf" {
  count = "${ length( split(",", var.etcd-ips) ) }"
  name                  = "etcd-master${ count.index + 1 }"
  location              = "${ var.location }"
  availability_set_id   = "${ var.availability-id }"
  resource_group_name = "${ var.name }"
  network_interface_ids = ["${ element(azurerm_network_interface.cncf.*.id, count.index) }"] 
  vm_size               = "Standard_A2"

  storage_image_reference {
    publisher = "CoreOS"
    offer     = "CoreOS"
    sku       = "Stable"
    version   = "1298.6.0"
  }

  storage_os_disk {
    name          = "etcd-disks${ count.index + 1 }"
    vhd_uri       = "${ var.storage-primary-endpoint }${ var.storage-container }/etcd-vhd${ count.index + 1 }.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  os_profile {
    computer_name  = "etcd-master${ count.index + 1 }"
    admin_username = "${ var.admin-username }"
    admin_password = "Password1234!"
    custom_data = "${ element(data.template_file.cloud-config.*.rendered, count.index) }"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/${ var.admin-username }/.ssh/authorized_keys"
      key_data = "${file("/cncf/data/.ssh/id_rsa.pub")}"
  }
 }
}
