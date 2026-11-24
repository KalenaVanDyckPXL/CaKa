# The API server's IP allow-list, owned by Terraform. It was set by hand to
# 198.51.100.0/24 (a documentation range) twice, locking everyone out. Now any
# change outside Git shows up as drift in the hourly pipeline check.
# 0.0.0.0/0 = reachable from anywhere; access is still protected by the
# cluster's client certificates. Narrow it to known IPs if you have them.
import {
  to = ovh_cloud_project_kube_iprestrictions.api
  id = "f9b3c6ad1ebe4d0da853feacccd21576/2f9c280f-b61f-47ba-9630-c238f3785108"
}

resource "ovh_cloud_project_kube_iprestrictions" "api" {
  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  ips          = ["0.0.0.0/0"]
}
