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

variable "project_create" {
  description = "Parameters for the creation of the new project."
  type = object({
    billing_account_id = string
    parent             = string
  })
  default = null
}

variable "host_project_id" {
  description = "Project ID."
  type        = string
}

variable "clusters_project_id" {
  description = "Management Project ID."
  type        = string
}

variable "mgmt_project_id" {
  description = "Management Project ID."
  type        = string
}

variable "mgmt_subnet_cidr_block" {
  description = "Management subnet CIDR block"
  type        = string
}

variable "clusters_config" {
  description = "Clusters configuration."
  type = map(object({
    region              = string
    subnet_cidr_block   = string
    master_cidr_block   = string
    services_cidr_block = string
    pods_cidr_block     = string
  }))
}

variable "mgmt_server_config" {
  description = "Mgmt server configuration"
  type = object({
    disk_size     = number
    disk_type     = string
    image         = string
    instance_type = string
    region        = string
    zone          = string
  })
  default = {
    disk_size     = 50
    disk_type     = "pd-ssd"
    image         = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    instance_type = "n1-standard-2"
    region        = "europe-west1"
    zone          = "europe-west1-c"
  }
}

variable "istio_version" {
  description = "ASM version"
  type        = string
  default     = "1.14.1-asm.3"
}
