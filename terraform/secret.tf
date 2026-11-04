###################
# Secrets Manager
###################

# --- Seed the secret (bootstrap only; Terraform never manages the value again) ---

ephemeral "random_password" "bootstrap" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "top_secret" {
  #name        = "TopSecret"
  name = local.secret_name
  description = "Monitored secret for CISO alerting pipeline"

  kms_key_id = aws_kms_key.secrets.arn
  
  recovery_window_in_days = var.environment == "prod" ? 30 : 0      
  # 0 = immediate deletion, no recovery window (Only for testing, not recommended for production)

  tags = {
    Sensitivity = "high"
    monitored   = "true"
  }
}

resource "aws_secretsmanager_secret_version" "top_secret" {
  secret_id                = aws_secretsmanager_secret.top_secret.id
  secret_string_wo         = ephemeral.random_password.bootstrap.result
  secret_string_wo_version = 1

  lifecycle {
    ignore_changes = [secret_string_wo_version]
  }
}

# --- Rotation ---
resource "aws_secretsmanager_secret_rotation" "top_secret" {
  secret_id           = aws_secretsmanager_secret.top_secret.id
  rotation_lambda_arn = aws_lambda_function.rotator.arn
  rotate_immediately  = true

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [
    aws_secretsmanager_secret_version.top_secret,
    aws_lambda_permission.rotator_secretsmanager,
  ]
}

# Deny all read access to the monitored secret except for the Lambda reader/rotator roles and any extra readers specified in extra_secret_reader_arns.
resource "aws_secretsmanager_secret_policy" "top_secret" {
  secret_arn = aws_secretsmanager_secret.top_secret.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyReadExceptAllowedReaders"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["secretsmanager:GetSecretValue", "secretsmanager:BatchGetSecretValue"]
        Resource  = "*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = concat(
              [aws_iam_role.lambda_reader.arn, aws_iam_role.lambda_rotator.arn, data.aws_caller_identity.current.arn],    # Add this for testing: data.aws_caller_identity.current.arn
              var.extra_secret_reader_arns
            )
          }
        }
      }
    ]
  })
}
