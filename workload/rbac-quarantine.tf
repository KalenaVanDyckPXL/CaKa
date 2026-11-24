# Seal 3: the cluster-admin backdoors keep coming back.
#
# At 13:52 UTC (14:52 our time), 20 minutes after we destroyed it, someone
# re-applied system:oracle-sight (cluster-admin for every service account in
# the oracle namespace) and, a second later, ixeth-realm-security-admin.
# Destroying them again would only start the race over.
#
# So we take ownership of both names. Terraform keeps each binding, but points
# it at an empty ClusterRole. A binding's roleRef cannot be changed, so a new
# `kubectl apply` that tries to point them back at cluster-admin is refused by
# the API server. Deleting and recreating them shows up as drift in the hourly
# pipeline run.

# A ClusterRole with no rules: binding to it grants nothing.
resource "kubernetes_cluster_role_v1" "quarantine" {
  metadata {
    name = "realm-quarantine"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

import {
  to = kubernetes_cluster_role_binding_v1.oracle_sight
  id = "system:oracle-sight"
}

resource "kubernetes_cluster_role_binding_v1" "oracle_sight" {
  metadata {
    name = "system:oracle-sight"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.quarantine.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "system:serviceaccounts:oracle"
  }
}

import {
  to = kubernetes_cluster_role_binding_v1.ixeth_security_admin
  id = "ixeth-realm-security-admin"
}

resource "kubernetes_cluster_role_binding_v1" "ixeth_security_admin" {
  metadata {
    name = "ixeth-realm-security-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.quarantine.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "ixeth"
    namespace = "oracle"
  }
}
