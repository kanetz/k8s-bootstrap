terraform {
  required_providers {
    alicloud = {
      source = "aliyun/alicloud"
      version = "1.186.0"
    }
  }
}


resource "time_static" "start_time" {}
resource "time_static" "end_time" {
  triggers = {
    completed = null_resource.post_install.id
  }
}


locals {
  elapsed_time_unix    = time_static.end_time.unix - time_static.start_time.unix
  elapsed_time_hours   = floor(local.elapsed_time_unix / 3600)
  elapsed_time_minutes = floor(local.elapsed_time_unix % 3600 / 60)
  elapsed_time_seconds = local.elapsed_time_unix % 60
  elapsed_time_text    = format("%s%s%s",
    local.elapsed_time_hours > 0 ? "${local.elapsed_time_hours}h" : "",
    (local.elapsed_time_hours > 0 || local.elapsed_time_minutes > 0) ? "${local.elapsed_time_minutes}m" : "",
    "${local.elapsed_time_seconds}s"
  )

  availability_zone = data.alicloud_instance_types.deployer_instance_types.instance_types.0.availability_zones.0
  image_id          = data.alicloud_images.ubuntu.ids.0

  script_dir           = "${path.root}/script"
  cloud_init_user_data = file("${local.script_dir}/cloud_init_user_data.sh")
  private_key_pem      = tls_private_key.key.private_key_pem
  private_key_file     = "${path.root}/ssh_private_key"

  data_disk_size       = 50

  vpc_id             = alicloud_vpc.vpc.id
  vsw_id             = alicloud_vswitch.vsw.id
  deployer_public_ip = alicloud_instance.deployer.public_ip

  all_nodes     = concat(alicloud_instance.masters, alicloud_instance.workers)
  all_instances = concat(local.all_nodes, [alicloud_instance.deployer])
}


################
# Provisioning #
################

data "alicloud_instance_types" "deployer_instance_types" {
  cpu_core_count = 1
  memory_size    = 1
}
data "alicloud_instance_types" "master_instance_types" {
  cpu_core_count    = var.master_cpu_core_count
  memory_size       = var.master_memory_size_gb
  availability_zone = local.availability_zone
}
data "alicloud_instance_types" "worker_instance_types" {
  cpu_core_count    = var.worker_cpu_core_count
  memory_size       = var.worker_memory_size_gb
  availability_zone = local.availability_zone
}

data "alicloud_images" "ubuntu" {
  name_regex  = "^ubuntu"
  most_recent = true
  owners      = "system"
}

resource "alicloud_vpc" "vpc" {
  vpc_name   = "k8s_bootstrap_vpc"
  cidr_block = "172.16.0.0/12"
}
resource "alicloud_vswitch" "vsw" {
  vpc_id     = local.vpc_id
  zone_id    = local.availability_zone
  cidr_block = "172.16.0.0/21"
}
resource "alicloud_nat_gateway" "nat_gtw" {
  nat_gateway_name = "nat_gtw"
  vpc_id           = local.vpc_id
  vswitch_id       = local.vsw_id
  nat_type         = "Enhanced"
}
resource "alicloud_eip_address" "nat_eip" {
}
resource "alicloud_eip_association" "nat_eip_assc" {
  allocation_id = alicloud_eip_address.nat_eip.id
  instance_id   = alicloud_nat_gateway.nat_gtw.id
}
resource "alicloud_snat_entry" "snat_entry" {
  depends_on        = [alicloud_eip_association.nat_eip_assc]

  snat_table_id     = alicloud_nat_gateway.nat_gtw.snat_table_ids
  source_vswitch_id = local.vsw_id
  snat_ip           = alicloud_eip_address.nat_eip.ip_address
}

resource "alicloud_security_group" "vpc_sec_grp" {
  name   = "vpc_sec_grp"
  vpc_id = local.vpc_id
}
resource "alicloud_security_group_rule" "vpc_allow_all" {
  security_group_id = alicloud_security_group.vpc_sec_grp.id
  description       = "VPC内允许任意连接"
  type              = "ingress"
  ip_protocol       = "all"
  policy            = "accept"
  port_range        = "-1/-1"
  cidr_ip           = alicloud_vpc.vpc.cidr_block
}

resource "alicloud_security_group" "deployer_sec_grp" {
  name   = "deployer_sec_grp"
  vpc_id = local.vpc_id
}
resource "alicloud_security_group_rule" "deployer_allow_ssh" {
  security_group_id = alicloud_security_group.deployer_sec_grp.id
  description       = "允许连接到Deployer的SSH服务"
  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "22/22"
  cidr_ip           = "0.0.0.0/0"
}
resource "alicloud_security_group_rule" "deployer_allow_k8s_ingress" {
  security_group_id = alicloud_security_group.deployer_sec_grp.id
  description       = "允许通过Deployer连接到K8s Ingress Controller"
  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "80/80"
  cidr_ip           = "0.0.0.0/0"
}
resource "alicloud_security_group_rule" "deployer_allow_k8s_api_server" {
  security_group_id = alicloud_security_group.deployer_sec_grp.id
  description       = "允许通过Deployer连接到K8s API Server"
  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "6443/6443"
  cidr_ip           = "0.0.0.0/0"
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "local_sensitive_file" "ssh_private_key" {
    content         = local.private_key_pem
    filename        = local.private_key_file
    file_permission = "0400"
}
resource "alicloud_ecs_key_pair" "ecs_key_pair" {
  key_pair_name = "k8s_bootstrap_key_pair"
  public_key    = tls_private_key.key.public_key_openssh
}

resource "alicloud_instance" "deployer" {
  depends_on = [alicloud_security_group_rule.deployer_allow_ssh]

  host_name     = "deployer"
  instance_name = "deployer"
  instance_type = data.alicloud_instance_types.deployer_instance_types.instance_types.0.id
  image_id      = local.image_id
  user_data     = local.cloud_init_user_data
  key_name      = alicloud_ecs_key_pair.ecs_key_pair.id

  vswitch_id                 = local.vsw_id
  internet_max_bandwidth_out = 10
  security_groups            = [
    alicloud_security_group.vpc_sec_grp.id,
    alicloud_security_group.deployer_sec_grp.id,
  ]

  data_disks {
    name = "data_disk"
    size = local.data_disk_size
  }

  security_enhancement_strategy = "Deactive"

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "root"
    private_key = local.private_key_pem
  }

  provisioner "file" {
    content     = local.private_key_pem
    destination = "/root/.ssh/id_rsa"
  }

  provisioner "file" {
    content     = tls_private_key.key.public_key_pem
    destination = "/root/.ssh/id_rsa.pub"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /root/.ssh/id_rsa",
    ]
  }
}

resource "alicloud_instance" "masters" {
  depends_on = [alicloud_security_group_rule.vpc_allow_all]

  count = var.master_count

  host_name     = "master${count.index}"
  instance_name = "master${count.index}"
  instance_type = data.alicloud_instance_types.master_instance_types.instance_types.0.id
  image_id      = local.image_id
  user_data     = local.cloud_init_user_data
  key_name      = alicloud_ecs_key_pair.ecs_key_pair.id

  vswitch_id      = local.vsw_id
  security_groups = [alicloud_security_group.vpc_sec_grp.id]

  data_disks {
    name = "data_disk"
    size = local.data_disk_size
  }

  security_enhancement_strategy = "Deactive"

  connection {
    type         = "ssh"
    bastion_host = local.deployer_public_ip
    host         = self.private_ip
    user         = "root"
    private_key  = local.private_key_pem
  }

  provisioner "file" {
    content     = local.private_key_pem
    destination = "/root/.ssh/id_rsa"
  }

  provisioner "file" {
    content     = tls_private_key.key.public_key_pem
    destination = "/root/.ssh/id_rsa.pub"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /root/.ssh/id_rsa",
    ]
  }
}

resource "alicloud_instance" "workers" {
  depends_on = [alicloud_security_group_rule.vpc_allow_all]

  count = var.worker_count

  host_name     = "worker${count.index}"
  instance_name = "worker${count.index}"
  instance_type = data.alicloud_instance_types.worker_instance_types.instance_types.0.id
  image_id      = local.image_id
  user_data     = local.cloud_init_user_data
  key_name      = alicloud_ecs_key_pair.ecs_key_pair.id

  vswitch_id      = local.vsw_id
  security_groups = [alicloud_security_group.vpc_sec_grp.id]

  data_disks {
    name = "data_disk"
    size = local.data_disk_size
  }

  security_enhancement_strategy = "Deactive"

  connection {
    type         = "ssh"
    bastion_host = local.deployer_public_ip
    host         = self.private_ip
    user         = "root"
    private_key  = local.private_key_pem
  }

  provisioner "file" {
    content     = local.private_key_pem
    destination = "/root/.ssh/id_rsa"
  }

  provisioner "file" {
    content     = tls_private_key.key.public_key_pem
    destination = "/root/.ssh/id_rsa.pub"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /root/.ssh/id_rsa",
    ]
  }
}


resource "alicloud_pvtz_zone" "vpc_pvtz_zone" {
  zone_name = "vpc"
}
resource "alicloud_pvtz_zone_attachment" "zone_attachment" {
  zone_id = alicloud_pvtz_zone.vpc_pvtz_zone.id
  vpc_ids = [local.vpc_id]
}
resource "alicloud_pvtz_zone_record" "vpc_instances" {
  count = length(local.all_instances)

  zone_id = alicloud_pvtz_zone.vpc_pvtz_zone.id
  type    = "A"
  rr      = local.all_instances[count.index].host_name
  value   = local.all_instances[count.index].private_ip
}


##############
# Deployment #
##############

resource "null_resource" "deployer_config" {
  depends_on = [
    alicloud_snat_entry.snat_entry,
    alicloud_pvtz_zone_record.vpc_instances,
  ]

  connection {
    type        = "ssh"
    host        = local.deployer_public_ip
    user        = "root"
    private_key = local.private_key_pem
  }

  provisioner "file" {
    source     = "${path.root}/conf"
    destination = "/root"
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.script_dir}/deployer_config.sh",
    ]
  }
}

resource "null_resource" "k8s_prerequisites" {
  depends_on = [
    null_resource.deployer_config,
  ]

  count = length(local.all_nodes)

  connection {
    type         = "ssh"
    bastion_host = local.deployer_public_ip
    host         = local.all_nodes[count.index].private_ip
    user         = "root"
    private_key  = local.private_key_pem
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.script_dir}/k8s_prerequisites.sh",
    ]
  }
}

resource "null_resource" "k8s_control_plane" {
  depends_on = [
    null_resource.k8s_prerequisites,
  ]

  count = length(alicloud_instance.masters)

  connection {
    type         = "ssh"
    bastion_host = local.deployer_public_ip
    host         = alicloud_instance.masters[count.index].private_ip
    user         = "root"
    private_key  = local.private_key_pem
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.script_dir}/k8s_control_plane.sh",
    ]
  }
}

resource "null_resource" "k8s_worker_nodes" {
  depends_on = [
    null_resource.k8s_control_plane,
  ]

  count = length(alicloud_instance.workers)

  connection {
    type         = "ssh"
    bastion_host = local.deployer_public_ip
    host         = alicloud_instance.workers[count.index].private_ip
    user         = "root"
    private_key  = local.private_key_pem
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.script_dir}/k8s_worker_node.sh",
    ]
  }
}

resource "null_resource" "post_install" {
  depends_on = [
    null_resource.k8s_control_plane,
    null_resource.k8s_worker_nodes,
  ]

  connection {
    type        = "ssh"
    host        = local.deployer_public_ip
    user        = "root"
    private_key = local.private_key_pem
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.script_dir}/k8s_post_install_config.sh",
      "${local.script_dir}/k8s_nginx_hello.sh",
    ]
  }
}


##########
# Output #
##########

output "_00_elapsed_time" {
  value = local.elapsed_time_text
}

output "_01_ssh" {
  value = "ssh -i ${abspath(local.private_key_file)} root@${local.deployer_public_ip}"
}

output "_02_grafana" {
  value = "http://${local.deployer_public_ip}/"
}
