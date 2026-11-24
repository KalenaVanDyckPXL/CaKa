# The API server's IP allow-list. Found set by hand to 198.51.100.0/24
# (a documentation range): it locked everyone out, the pipeline too.
# Break-glass: imported and applied locally, removed in the next commit.
import {
  to = ovh_cloud_project_kube_iprestrictions.api
  id = "f9b3c6ad1ebe4d0da853feacccd21576/2f9c280f-b61f-47ba-9630-c238f3785108"
}

resource "ovh_cloud_project_kube_iprestrictions" "api" {
  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  ips          = ["198.51.100.0/24"]
}
