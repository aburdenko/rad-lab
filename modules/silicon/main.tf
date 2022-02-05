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

locals {
  random_id = var.random_id != null ? var.random_id : random_id.default.hex
  project = (var.create_project
    ? try(module.project_radlab_silicon.0, null)
    : try(data.google_project.existing_project.0, null)
  )
  region = join("-", [split("-", var.zone)[0], split("-", var.zone)[1]])

  network = (
    var.create_network
    ? try(module.vpc_ai_notebook.0.network.network, null)
    : try(data.google_compute_network.default.0, null)
  )

  subnet = (
    var.create_network
    ? try(module.vpc_ai_notebook.0.subnets["${local.region}/${var.subnet_name}"], null)
    : try(data.google_compute_subnetwork.default.0, null)
  )

  notebook_sa_project_roles = [
    "roles/artifactregistry.reader",
    "roles/notebooks.admin",
    "roles/compute.instanceAdmin",
    "roles/iam.serviceAccountUser",
  ]

  project_services = var.enable_services ? [
    "compute.googleapis.com",
    "notebooks.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
  ] : []
}

resource "random_id" "default" {
  byte_length = 2
}

#####################
# ANALYTICS PROJECT #
#####################

data "google_project" "existing_project" {
  count      = var.create_project ? 0 : 1
  project_id = var.project_name
}

module "project_radlab_silicon" {
  count   = var.create_project ? 1 : 0
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 11.0"

  name              = format("%s-%s", var.project_name, local.random_id)
  random_project_id = false
  folder_id         = var.folder_id
  billing_account   = var.billing_account_id
  org_id            = var.organization_id

  activate_apis = []
}

resource "google_project_service" "enabled_services" {
  for_each                   = toset(local.project_services)
  project                    = local.project.project_id
  service                    = each.value
  disable_dependent_services = true
  disable_on_destroy         = true

  depends_on = [
    module.project_radlab_silicon
  ]
}

data "google_compute_network" "default" {
  count   = var.create_network ? 0 : 1
  project = local.project.project_id
  name    = var.network_name
}

data "google_compute_subnetwork" "default" {
  count   = var.create_network ? 0 : 1
  project = local.project.project_id
  name    = var.subnet_name
  region  = local.region
}

module "vpc_ai_notebook" {
  count   = var.create_network ? 1 : 0
  source  = "terraform-google-modules/network/google"
  version = "~> 3.0"

  project_id   = local.project.project_id
  network_name = var.network_name
  routing_mode = "GLOBAL"
  description  = "VPC Network created via Terraform"

  subnets = [
    {
      subnet_name           = var.subnet_name
      subnet_ip             = var.ip_cidr_range
      subnet_region         = local.region
      description           = "Subnetwork inside *vpc-silicon* VPC network, created via Terraform"
      subnet_private_access = true
    }
  ]

  firewall_rules = [
    {
      name        = "fw-ai-notebook-allow-internal"
      description = "Firewall rule to allow traffic on all ports inside *vpc-silicon* VPC network."
      priority    = 65534
      ranges      = ["10.0.0.0/8"]
      direction   = "INGRESS"

      allow = [{
        protocol = "tcp"
        ports    = ["0-65535"]
      }]
    }
  ]

  depends_on = [
    google_project_service.enabled_services
  ]
}

resource "google_service_account" "sa_p_notebook" {
  project      = local.project.project_id
  account_id   = format("sa-p-notebook-%s", local.random_id)
  display_name = "Notebooks in trusted environment"
}

resource "google_project_iam_member" "sa_p_notebook_permissions" {
  for_each = toset(local.notebook_sa_project_roles)
  project  = local.project.project_id
  member   = "serviceAccount:${google_service_account.sa_p_notebook.email}"
  role     = each.value
}

resource "google_service_account_iam_member" "sa_ai_notebook_user_iam" {
  for_each           = var.trusted_users
  member             = each.value
  role               = "roles/iam.serviceAccountUser"
  service_account_id = google_service_account.sa_p_notebook.id
}

resource "google_project_iam_binding" "ai_notebook_user_role1" {
  project = local.project.project_id
  members = var.trusted_users
  role    = "roles/notebooks.admin"
}

resource "google_project_iam_binding" "ai_notebook_user_role2" {
  project = local.project.project_id
  members = var.trusted_users
  role    = "roles/viewer"
}

resource "google_notebooks_instance" "ai_notebook" {
  count        = var.notebook_count
  project      = local.project.project_id
  name         = "notebooks-instance-${count.index}"
  location     = var.zone
  machine_type = var.machine_type

  container_image {
    repository = "${google_artifact_registry_repository.containers_repo.location}-docker.pkg.dev/${local.project.project_id}/${google_artifact_registry_repository.containers_repo.repository_id}/openlane-jupyterlab"
 }

  service_account = google_service_account.sa_p_notebook.email

  install_gpu_driver = false
  boot_disk_type     = var.boot_disk_type
  boot_disk_size_gb  = var.boot_disk_size_gb

  no_public_ip    = false
  no_proxy_access = false

  network = local.network.self_link
  subnet  = local.subnet.self_link

  labels = {
    module = "silicon"
  }

  metadata = {
    terraform  = "true"
    proxy-mode = "service_account"
  }
  depends_on = [
    time_sleep.wait_120_seconds,
    null_resource.build_and_push_image,
  ]
}

resource "google_artifact_registry_repository" "containers_repo" {
  provider = google-beta

  project = local.project.project_id
  location = local.region
  repository_id = "containers"
  description = "container image repository"
  format = "DOCKER"

  depends_on = [
    google_project_service.enabled_services
  ]  
}

# Locally build container for notebook container and push to container registry #
resource "null_resource" "build_and_push_image" {
  triggers = {
    cloudbuild_yaml_sha = filesha1("${path.module}/scripts/build/container/jupyterlab/cloudbuild.yaml")
    dockerfile_sha      = filesha1("${path.module}/scripts/build/container/jupyterlab/Dockerfile")
    build_script_sha    = filesha1("${path.module}/scripts/build/container/jupyterlab/build-container.sh")
    notebook_sha    = filesha1("${path.module}/scripts/build/container/jupyterlab/inverter.ipynb")    
  }

  provisioner "local-exec" {
    working_dir = path.module
    command     = "scripts/build/container/jupyterlab/build-container.sh ${local.project.project_id} ${google_artifact_registry_repository.containers_repo.location} ${google_artifact_registry_repository.containers_repo.repository_id}"
  }

  depends_on = [
    google_artifact_registry_repository.containers_repo
  ]  
}
