##################################
# S3 bucket for CloudTrail logs
##################################

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.project_name}-cloudtrail-logs"       # bucket name
  force_destroy = var.environment == "prod" ? false : true    # lets `terraform destroy` wipe it instantly — fine for test, risky for prod
}

# Encrypts all objects at rest with your KMS key by default,
# so anything written without explicit encryption still gets KMS-encrypted.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id  
  #bucket_key_enabled = true  # cache a bucket-level key to cut KMS request volume/cost
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"                     # use KMS (not default AES-256/SSE-S3) for encryption
      kms_master_key_id = aws_kms_key.secrets.arn       # the customer-managed key to encrypt objects with
    }
  }
}

# Blocks all public access paths on this bucket.
# Should always be on for a bucket holding audit logs.
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id     # target bucket for these public-access restrictions
  block_public_acls       = true                            # reject PUT requests that include public ACLs
  block_public_policy     = true                            # reject bucket policies that would allow public access
  ignore_public_acls      = true                            # ignore any public ACLs already on the bucket/objects
  restrict_public_buckets = true                            # block public access even if policy would otherwise allow it
}

# Bucket policy for CloudTrail logs: allow CloudTrail to write,
# deny all non-TLS access.
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow CloudTrail to check the bucket ACL so it can write logs. Needed even if ACLs are disabled (BucketOwnerEnforced).
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail"
          }
        }
      },      
      {
        # Let this account's CloudTrail write logs here.
        # Scoped by SourceAccount/SourceArn to prevent other accounts/trails from writing to this bucket.
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail"
          }
        }
      },
      {
        # Deny any request not using HTTPS/TLS.
        Sid    = "DenyNonSSL"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail.arn,
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Ensure ACLs are disabled before this policy applies.
  depends_on = [aws_s3_bucket_ownership_controls.cloudtrail,
                aws_s3_bucket_public_access_block.cloudtrail]
}

# Disables ACLs on the bucket; bucket owner owns all objects.
resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Lifecycle for CloudTrail logs: CloudWatch Logs covers live querying
# for the first 90 days, so S3 can go cold early.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-log-tiering"
    status = "Enabled"

    filter {}                        # apply to all objects in the bucket
    #Objects smaller than 128 KB will not transition by default to any storage class

    transition {
      days          = 30
      storage_class = "GLACIER_IR"  # Glacier Instant Retrieval - cheaper archive, still millisecond access
    }

    expiration {
      days = 365                    # keep one year of audit history, then delete
    }
  }
}

