# Seal 1: ghost resources created outside Terraform (they keep coming back).
# Step 1: import them here. Step 2: delete this file, so Terraform destroys them.

import {
  to = ovh_cloud_project_kube_nodepool.hotfix
  id = "f9b3c6ad1ebe4d0da853feacccd21576/2f9c280f-b61f-47ba-9630-c238f3785108/6ecfe817-5ed9-482b-9669-3759f742ab9c"
}

resource "ovh_cloud_project_kube_nodepool" "hotfix" {
  service_name  = var.service_name
  kube_id       = ovh_cloud_project_kube.this.id
  name          = "hotfix-pool"
  flavor_name   = "b3-8"
  autoscale     = false
  min_nodes     = 1
  max_nodes     = 1
  desired_nodes = 1
}

import {
  to = ovh_cloud_project_user.debug_admin
  id = "f9b3c6ad1ebe4d0da853feacccd21576/1014209"
}

resource "ovh_cloud_project_user" "debug_admin" {
  service_name = var.service_name
  description  = "debug-admin"
  role_names   = ["administrator"]
}