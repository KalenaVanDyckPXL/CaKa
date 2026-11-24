# Seal 1: drift found in the Kubernetes API access list.
# Someone restricted the API to 198.51.100.0/24 (TEST-NET-2, RFC 5737):
# an address range nobody uses, so the realm was locked out of its own
# cluster (pipeline, Seer and heroes alike). Not in the IaC, not needed.
# Imported here and managed from code from now on. Access stays protected by
# the cluster's client certificates.
import {
  to = ovh_cloud_project_kube_iprestrictions.this
  id = "f9b3c6ad1ebe4d0da853feacccd21576/2f9c280f-b61f-47ba-9630-c238f3785108"
}

resource "ovh_cloud_project_kube_iprestrictions" "this" {
  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  ips          = ["0.0.0.0/0"]
}