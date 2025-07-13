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
  root_dir      = abspath("${path.module}/..")
  image_path    = "${local.root_dir}/project_pool/jammy-server-cloudimg-amd64.img"
  image_exists  = fileexists(local.image_path)
  ssh_key       = trimspace(file("${local.root_dir}/ssh_keys/project_key.pub"))
  ips           = ["10.0.0.10", "10.0.0.20", "10.0.0.30", "10.0.0.40"]
  macs          = ["52:54:00:aa:bb:10", "52:54:00:aa:bb:20", "52:54:00:aa:bb:30", "52:54:00:aa:bb:40"]
  hostname_base = "vm"
}

resource "libvirt_pool" "pool" {
  name = "project_pool"
  type = "dir"
  path = "${local.root_dir}/project_pool"
}

resource "null_resource" "download_image" {
  count = local.image_exists ? 0 : 1
  provisioner "local-exec" {
    command = <<EOT
      wget -q -nc "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" \
        -O "${local.image_path}"
    EOT
  }
}

resource "libvirt_volume" "base" {
  name           = "ubuntu-jammy.qcow2"
  source         = "${local.root_dir}/project_pool/jammy-server-cloudimg-amd64.img"
  format         = "qcow2"
  pool           = libvirt_pool.pool.name
  depends_on     = [null_resource.download_image]
}

resource "libvirt_volume" "disk" {
  count          = 4
  name           = "${local.hostname_base}-${count.index}.qcow2"
  base_volume_id = libvirt_volume.base.id
  size           = 10 * 1024 * 1024 * 1024
  pool           = libvirt_pool.pool.name
}

# Fixed: Single cloud-config part only
data "cloudinit_config" "vm" {
  count          = 4
  gzip           = false
  base64_encode  = false

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init/user-data.yml", {
      ssh_key  = local.ssh_key
      hostname = "${local.hostname_base}-${count.index}"
      fqdn     = "${local.hostname_base}-${count.index}.example.local"
    })
  }
}

# Fixed: Separate network config and metadata
resource "libvirt_cloudinit_disk" "cidata" {
  count     = 4
  name      = "${local.hostname_base}-${count.index}-init.iso"
  pool      = libvirt_pool.pool.name
  user_data = data.cloudinit_config.vm[count.index].rendered

  # Network configuration as separate parameter
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = {
        match = {
          macaddress = local.macs[count.index]
        }
        dhcp4 = false
        addresses = ["${local.ips[count.index]}/24"]
        routes = [
          {
            to = "default"
            via = "10.0.0.1"
          }
        ]
        nameservers = {
          addresses = ["8.8.8.8", "1.1.1.1"]
        }
      }
    }
  })

  # Metadata as separate parameter
  meta_data = yamlencode({
    instance-id = "${local.hostname_base}-${count.index}"
    local-hostname = "${local.hostname_base}-${count.index}"
  })
}

resource "libvirt_network" "net" {
  name      = "vm-net"
  mode      = "nat"
  domain    = "example.local"
  addresses = ["10.0.0.0/24"]
  dhcp {
    enabled = false
  }
}

resource "libvirt_domain" "vm" {
  count  = 4
  name   = "${local.hostname_base}-${count.index}"
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

output "ips" {
  value = local.ips
}
