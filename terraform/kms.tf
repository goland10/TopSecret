##############
# KMS
##############
resource "aws_kms_key" "secrets" {
  description             = "KMS key for the monitored secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      #{
      #  # I removed this statement so access is managed only from KMS key policy (here), not from IAM policies solely. It's more secure.
      #  # To allow IAM users/roles to use the key, you must explicitly add them to the KMS policy + allow them from their IAM policies.
      #  # Manage key access via IAM policies.
      #  Sid    = "EnableRootAccess"
      #  Effect = "Allow"
      #  Principal = {
      #    AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      #  }
      #  Action   = "kms:*"
      #  Resource = "*"
      #},
      {
        Sid       = "AllowCallerFullAccess"
        Effect    = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
        Action    = "kms:*"
        Resource  = "*"
      },      
      {
        Sid    = "AllowSecretsManagerAccess"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda Reader via Secrets Manager"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_reader.arn
        }
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "secretsmanager.${var.region}.amazonaws.com"
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },            
      {
        Sid    = "Allow Lambda Rotator via Secrets Manager"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_rotator.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "secretsmanager.${var.region}.amazonaws.com"
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        # Allow EventBridge indirect access to the key (via SNS). 
        # SNS will use KMS to encrypt/decrypt the messages in behalf of EventBridge.
        Sid       = "AllowEventBridgeToPublishToEncryptedTopic"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "sns.${var.region}.amazonaws.com"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },     
      {
        Sid       = "AllowCloudWatchAlarmsToPublishToEncryptedTopic"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "sns.${var.region}.amazonaws.com"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },             
      {
        Sid    = "AllowCloudTrail"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          #"kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          ArnLike: {
            "aws:SourceArn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail"
          }          
          StringLike = {            
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail"
          }
        }
      },    
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          #"kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }   
    ]
  })
}

# Human-friendly key reference (code/console use this instead of raw key IDs).
resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.secrets.key_id
}
