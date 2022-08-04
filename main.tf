/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

module "host_project" {
  source = "github.com/apichick/cloud-foundation-fabric.git//modules/project?ref=master"
  billing_account = (var.project_create != null
    ? var.project_create.billing_account_id
    : null
  )
  parent = (var.project_create != null
    ? var.project_create.parent
    : null
  )
  name = var.host_project_id
  shared_vpc_host_config = {
    enabled          = true
    service_projects = []
  }
  services = [
    "container.googleapis.com"
  ]
}

module "mgmt_project" {
  source = "github.com/apichick/cloud-foundation-fabric.git//modules/project?ref=master"
  billing_account = (var.project_create != null
    ? var.project_create.billing_account_id
    : null
  )
  parent = (var.project_create != null
    ? var.project_create.parent
    : null
  )
  name = var.mgmt_project_id
  shared_vpc_service_config = {
    attach               = true
    host_project         = module.host_project.project_id
    service_identity_iam = null
  }
  services = [
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",
    "serviceusage.googleapis.com"
  ]
}

module "clusters_project" {
  source = "github.com/apichick/cloud-foundation-fabric.git//modules/project?ref=master"
  billing_account = (var.project_create != null
    ? var.project_create.billing_account_id
    : null
  )
  parent = (var.project_create != null
    ? var.project_create.parent
    : null
  )
  name = var.clusters_project_id
  shared_vpc_service_config = {
    attach       = true
    host_project = module.host_project.project_id
    service_identity_iam = {
      "roles/compute.networkUser" = [
        "cloudservices", "container-engine"
      ]
      "roles/container.hostServiceAgentUser" = [
        "container-engine"
      ]
    }
  }
  services = [
    "anthos.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "gkeconnect.googleapis.com",
    "logging.googleapis.com",
    "mesh.googleapis.com",
    "monitoring.googleapis.com",
    "stackdriver.googleapis.com"
  ]
  iam = {
    "roles/container.admin"     = [module.mgmt_server.service_account_iam_email]
    "roles/gkehub.admin"        = [module.mgmt_server.service_account_iam_email]
    "roles/gkehub.serviceAgent" = ["serviceAccount:${module.clusters_project.service_accounts.robots.fleet}"]
  }
  service_config = {
    disable_on_destroy         = false
    disable_dependent_services = true
  }
}

module "svpc" {
  source     = "github.com/apichick/cloud-foundation-fabric.git//modules/net-vpc?ref=master"
  project_id = module.host_project.project_id
  name       = "svpc"
  mtu        = 1500
  subnets = concat([for key, config in var.clusters_config : {
    ip_cidr_range = config.subnet_cidr_block
    name          = "subnet-${key}"
    region        = config.region
    secondary_ip_range = {
      pods     = config.pods_cidr_block
      services = config.services_cidr_block
    }
    }], [{
    ip_cidr_range      = var.mgmt_subnet_cidr_block
    name               = "subnet-mgmt"
    region             = var.mgmt_server_config.region
    secondary_ip_range = null
  }])
}

module "mgmt_server" {
  source        = "github.com/apichick/cloud-foundation-fabric.git//modules/compute-vm?ref=master"
  project_id    = module.mgmt_project.project_id
  zone          = var.mgmt_server_config.zone
  name          = "mgmt"
  instance_type = var.mgmt_server_config.instance_type
  network_interfaces = [{
    network    = module.svpc.self_link
    subnetwork = module.svpc.subnet_self_links["${var.mgmt_server_config.region}/subnet-mgmt"]
    nat        = false
    addresses  = null
  }]
  service_account_create = true
  boot_disk = {
    image = var.mgmt_server_config.image
    type  = var.mgmt_server_config.disk_type
    size  = var.mgmt_server_config.disk_size
  }
}

module "clusters" {
  for_each                 = var.clusters_config
  source                   = "github.com/apichick/cloud-foundation-fabric.git//modules/gke-cluster?ref=master"
  project_id               = module.clusters_project.project_id
  name                     = each.key
  location                 = each.value.region
  network                  = module.svpc.self_link
  subnetwork               = module.svpc.subnet_self_links["${each.value.region}/subnet-${each.key}"]
  secondary_range_pods     = "pods"
  secondary_range_services = "services"
  private_cluster_config = {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = each.value.master_cidr_block
    master_global_access    = true
  }
  master_authorized_ranges = merge({
    mgmt : var.mgmt_subnet_cidr_block
    },
    { for key, config in var.clusters_config :
      "pods-${key}" => config.pods_cidr_block if key != each.key
  })
  enable_autopilot  = false
  release_channel   = "REGULAR"
  workload_identity = true
  labels = {
    mesh_id = "proj-${module.clusters_project.number}"
  }
}

module "cluster_nodepools" {
  for_each                    = var.clusters_config
  source                      = "github.com/apichick/cloud-foundation-fabric.git//modules/gke-nodepool?ref=master"
  project_id                  = module.clusters_project.project_id
  cluster_name                = module.clusters[each.key].name
  location                    = each.value.region
  name                        = "nodepool-${each.key}"
  node_service_account_create = true
  initial_node_count          = 1
  node_machine_type           = "e2-standard-4"
  node_tags                   = ["${each.key}-node"]
}

module "firewall" {
  source     = "github.com/apichick/cloud-foundation-fabric.git//modules/net-vpc-firewall?ref=master"
  project_id = module.host_project.project_id
  network    = module.svpc.name
  custom_rules = merge({ allow-mesh = {
    description          = "Allow "
    direction            = "INGRESS"
    action               = "allow"
    sources              = []
    ranges               = [for k, v in var.clusters_config : v.pods_cidr_block]
    targets              = [for k, v in var.clusters_config : "${k}-node"]
    use_service_accounts = false
    rules = [{ protocol = "tcp", ports = null },
      { protocol = "udp", ports = null },
      { protocol = "icmp", ports = null },
      { protocol = "esp", ports = null },
      { protocol = "ah", ports = null },
    { protocol = "sctp", ports = null }]
    extra_attributes = {
      priority = 900
    }
    } },
    { for k, v in var.clusters_config : "allow-${k}-istio" => {
      description          = "Allow "
      direction            = "INGRESS"
      action               = "allow"
      sources              = []
      ranges               = [v.master_cidr_block]
      targets              = ["${k}-node"]
      use_service_accounts = false
      rules                = [{ protocol = "tcp", ports = [8080, 15014, 15017] }]
      extra_attributes = {
        priority = 1000
      }
      }
    }
  )
}

module "nat" {
  for_each       = toset([for key, config in var.clusters_config : config.region])
  source         = "github.com/apichick/cloud-foundation-fabric.git//modules/net-cloudnat?ref=master"
  project_id     = module.host_project.project_id
  region         = each.value
  name           = "nat-${each.value}"
  router_create  = true
  router_network = module.svpc.name
}

module "hub" {
  source     = "github.com/apichick/cloud-foundation-fabric.git//modules/gke-hub?ref=master"
  project_id = module.clusters_project.project_id
  clusters   = { for k, v in module.clusters : k => v.id }
  features = {
    appdevexperience             = false
    configmanagement             = false
    identityservice              = false
    multiclusteringress          = null
    servicemesh                  = true
    multiclusterservicediscovery = false
  }
  depends_on = [
    module.clusters_project
  ]
}

resource "local_file" "vars_file" {
  content = templatefile("${path.module}/templates/vars.yaml.tpl", {
    istio_version         = var.istio_version
    clusters              = var.clusters_config
    service_account_email = module.mgmt_server.service_account_email
    project_id            = module.clusters_project.project_id
  })
  filename        = "${path.module}/ansible/vars/vars.yaml"
  file_permission = "0666"
}

resource "local_file" "gssh_file" {
  content = templatefile("${path.module}/templates/gssh.sh.tpl", {
    project_id = var.mgmt_project_id
    zone       = var.mgmt_server_config.zone
  })
  filename        = "${path.module}/ansible/gssh.sh"
  file_permission = "0777"
}
