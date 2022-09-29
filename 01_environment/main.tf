# Configure the VMware vSphere Provider
provider "vsphere" {
  user           = "administrator@vsphere.local"
  password       = "P@ssw0rd"
  vsphere_server = "192.168.20.251"

  # if you have a self-signed cert
  allow_unverified_ssl = true
}

# Deploy 3 linux VMs
module "centos-server-linuxvm" {
  source    = "Terraform-VMWare-Modules/vm/vsphere"
  #source    = ".terraform/modules/centos-server-linuxvm"
  version   = "3.5.0"
  vmtemp    = "CentOS8"
  instances = 3
  vmname    = "cicdlab"
  vmnameformat  = "%03d" #To use three decimal with leading zero vmnames will be AdvancedVM001,AdvancedVM002
  vmrp      = "Felix-Cluster/Resources/terraform"
  network = {
    "VM Network" = ["192.168.22.91", "192.168.22.92", "192.168.22.93"] # To use DHCP create Empty list ["",""]; You can also use a CIDR annotation;
  }
  vmgateway = "192.168.0.250"
  dc        = "Felix-DC"
  datastore = "Data"
  ipv4submask  = ["16", "16", "16"]
  network_type = ["vmxnet3", "vmxnet3", "vmxnet3"]
  dns_server_list  = ["192.168.22.1", "192.168.22.1", "192.168.22.1"]
  is_windows_image = false
}

output "vmnames" {
  value = module.centos-server-linuxvm.VM
}

output "vmnameswip" {
  value = module.centos-server-linuxvm.ip
}