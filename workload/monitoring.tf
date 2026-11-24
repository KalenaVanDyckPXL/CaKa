# The cluster's monitoring stack: a Helm chart in charts/kube-monitoring.
# Terraform installs it and upgrades it when the chart changes. Bump `version`
# in the chart's Chart.yaml whenever you change a template.

# The scrolls app's credentials are not in Git: the S3 key is the rotated
# scrolls-app key from ../core (remote state), the signing key is generated
# here. Both live only in the private state bucket and in the cluster.
# Rotate the signing key by changing its keepers.
resource "random_password" "scrolls_signing_key" {
  length  = 48
  special = false

  keepers = {
    rotation = "2026-11-24 leaked in Git"
  }
}

resource "helm_release" "monitoring" {
  name      = "kube-monitoring"
  chart     = "${path.module}/charts/kube-monitoring"
  namespace = "observability"

  create_namespace = true
  wait             = true
  timeout          = 600

  set = [
    {
      name  = "ingress.domain"
      value = var.ingress_domain
    },
  ]

  set_sensitive = [
    {
      name  = "scrolls.s3.accessKey"
      value = data.terraform_remote_state.core.outputs.scrolls_s3_access_key
    },
    {
      name  = "scrolls.s3.secretKey"
      value = data.terraform_remote_state.core.outputs.scrolls_s3_secret_key
    },
    {
      name  = "scrolls.signingKey"
      value = random_password.scrolls_signing_key.result
    },
  ]
}