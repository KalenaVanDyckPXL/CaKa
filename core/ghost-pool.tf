# Ghost nodepool "hotfix-pool": created by hand in the console (not in the
# code), 1 x b3-8, ran only system pods. Imported so Terraform owns it,
# removed in the next commit.
import {
  to = ovh_cloud_project_kube_nodepool.ghost
  id = "f9b3c6ad1ebe4d0da853feacccd21576/2f9c280f-b61f-47ba-9630-c238f3785108/0fb16fd1-38f2-427e-9551-8c06eabf65b7"
}

resource "ovh_cloud_project_kube_nodepool" "ghost" {
  service_name  = var.service_name
  kube_id       = ovh_cloud_project_kube.this.id
  name          = "hotfix-pool"
  flavor_name   = "b3-8"
  desired_nodes = 1
  min_nodes     = 1
  max_nodes     = 1
  autoscale     = false

  # Only imported to be deleted: never change or replace it in between.
  lifecycle {
    ignore_changes = all
  }
}
