terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

locals {
  root_dir     = abspath("${path.module}/..")
  image_path   = "${local.root_dir}/cloud_image/jammy-server-cloudimg-amd64.img"
  image_exists = fileexists(local.image_path)
  ssh_key      = trimspace(file("${local.root_dir}/ssh_keys/project_key.pub"))
  names = ["load_balancer", "next_cloud", "mail_server", "database_server"]
  ips   = ["10.0.0.10", "10.0.0.20", "10.0.0.30", "10.0.0.40"]
  macs  = ["52:54:00:aa:bb:10", "52:54:00:aa:bb:20", "52:54:00:aa:bb:30", "52:54:00:aa:bb:40"]
}

resource "libvirt_pool" "pool" {
  name = "project_pool"
  type = "dir"
  path = "${local.root_dir}/project_pool"
}

resource "null_resource" "fix_pool_permissions" {
  triggers = {
    pool_path = libvirt_pool.pool.path
  }

  provisioner "local_exec" {
    command = "chmod 755 '${libvirt_pool.pool.path}'"
  }

  depends_on = [libvirt_pool.pool]
}

resource "null_resource" "download_image" {
  count = local.image_exists ? 0 : 1
  provisioner "local-exec" {
    command = <<EOT
      mkdir -p "${local.root_dir}/cloud_image"
      wget -q -nc "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" \
        -O "${local.image_path}"
    EOT
  }
}

resource "libvirt_volume" "base" {
  name           = "ubuntu-jammy.qcow2"
  source         = local.image_path
  format         = "qcow2"
  pool           = libvirt_pool.pool.name
  depends_on     = [null_resource.download_image]
}

resource "libvirt_volume" "disk" {
  count          = length(local.names)
  name           = "${local.names[count.index]}.qcow2"
  base_volume_id = libvirt_volume.base.id
  size           = 10 * 1024 * 1024 * 1024
  pool           = libvirt_pool.pool.name
}

data "cloudinit_config" "vm" {
  count          = length(local.names)
  gzip           = false
  base64_encode  = false
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init/user-data.yml", {
      ssh_key  = local.ssh_key
      hostname = local.names[count.index]
      fqdn     = "${local.names[count.index]}.example.local"
    })
  }
}

resource "libvirt_cloudinit_disk" "cidata" {
  count     = length(local.names)
  name      = "${local.names[count.index]}-init.iso"
  pool      = libvirt_pool.pool.name
  user_data = data.cloudinit_config.vm[count.index].rendered
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = {
        match = {
          macaddress = local.macs[count.index]
        }
        dhcp4     = false
        addresses = ["${local.ips[count.index]}/24"]
        routes = [
          {
            to  = "default"
            via = "10.0.0.1"
          }
        ]
        nameservers = {
          addresses = ["8.8.8.8", "1.1.1.1"]
        }
      }
    }
  })
  meta_data = yamlencode({
    instance-id     = local.names[count.index]
    local-hostname  = local.names[count.index]
  })
}

resource "libvirt_network" "net" {
  name      = "vm-net"
  mode      = "nat"
  domain    = "example.local"
  addresses = ["10.0.0.0/24"]
  autostart = true
  dhcp {
    enabled = false
  }
}

resource "libvirt_domain" "vm" {
  count  = length(local.names)
  name   = local.names[count.index]
  vcpu   = 2
  memory = 2048
  disk {
    volume_id = libvirt_volume.disk[count.index].id
  }
  network_interface {
    network_id = libvirt_network.net.id
    mac        = local.macs[count.index]
  }
  cloudinit = libvirt_cloudinit_disk.cidata[count.index].id
  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

output "vm_ips" {
  value = {
    for idx in range(length(local.names)) :
    local.names[idx] => local.ips[idx]
  }
}
