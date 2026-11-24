# Least-privilege identity used by workloads on the cluster to access the
# scrolls bucket. It can read and write objects in that one bucket only.

resource "ovh_cloud_project_user" "scrolls_app" {
  service_name = var.service_name
  description  = "${var.name_prefix}-scrolls-app"
  role_names   = ["objectstore_operator"]
}

# Seal 2: the scrolls-app credentials were compromised. Bump `input` to rotate:
# Terraform deletes the old S3 key and creates a new one.
resource "terraform_data" "scrolls_key_rotation" {
  input = 1
}

resource "ovh_cloud_project_user_s3_credential" "scrolls_app" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.scrolls_app.id

  lifecycle {
    replace_triggered_by = [terraform_data.scrolls_key_rotation]
  }
}

# Seal 2: a second S3 key for scrolls-app, created outside Terraform by the
# attacker. Imported here so the next commit (removing this block) destroys it.
import {
  to = ovh_cloud_project_user_s3_credential.rogue
  id = "f9b3c6ad1ebe4d0da853feacccd21576/1013902/83b21a2e59b74d5690a7b509217e874e"
}

resource "ovh_cloud_project_user_s3_credential" "rogue" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.scrolls_app.id
}

resource "ovh_cloud_project_user_s3_policy" "scrolls_app" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.scrolls_app.id

  policy = jsonencode({
    Statement = [
      {
        Sid    = "ScrollsReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListMultipartUploadParts",
          "s3:ListBucketMultipartUploads",
          "s3:AbortMultipartUpload",
        ]
        Resource = [
          "arn:aws:s3:::${ovh_cloud_storage_object_bucket.scrolls.name}",
          "arn:aws:s3:::${ovh_cloud_storage_object_bucket.scrolls.name}/*",
        ]
      },
    ]
  })
}