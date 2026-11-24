# Seal 3: a ClusterRoleBinding applied by hand (kubectl apply, 13:39) that gives
# every service account in the oracle namespace cluster-admin. It hides as a
# Kubernetes default: "system:" prefix, rbac-defaults label, autoupdate
# annotation. Imported here so removing this file destroys it.
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
    name      = "cluster-admin"
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "system:serviceaccounts:oracle"
  }
}
