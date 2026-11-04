##############
# CloudTrail
##############
# The trail is not really needed for the alerting functionality, but it is a good practice to have one in place for auditing purposes.
# We can remove the trail and all its components (S3 bucket, CloudWatch log group, IAM role) and the alerts on reading the secret will still work.
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true                        #Relevant only to us-east-1 since November 22, 2021 (According to Amazon Q); Just be on the safe side.
  is_multi_region_trail         = true                        #Needed to capture Global service events (e.g. IAM, STS, CloudFront)
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch.arn
  kms_key_id                    = aws_kms_key.secrets.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
    exclude_management_event_sources = ["rdsdata.amazonaws.com"]  # Do not exclude "kms.amazonaws.com" because Key tampering ALERT depends on it.
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
  #advanced_event_selector {
  #  name = "Track management events"
#
  #  # Only track management events (not data events), read (not write), and only for Secrets Manager service.
  #  field_selector {
  #    field  = "eventCategory"
  #    equals = ["Management"]
  #  }
#
  #  field_selector {
  #    field  = "readOnly"
  #    equals = ["true"]
  #  }    
  #  
  ## eventSource = secretsmanager ; This can't go hand in hand with eventCategory = Management
  #  field_selector {
  #    field  = "eventSource"
  #    equals = ["secretsmanager.amazonaws.com"]
  #  }
#
  #  #field_selector {
  #  #  field      = "eventSource"
  #  #  not_equals = ["kms.amazonaws.com", "rdsdata.amazonaws.com"]
  #  #}
  #}

#######################################
# CloudWatch Log Group for CloudTrail
#######################################
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/${var.project_name}/${var.environment}/cloudtrail"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.secrets.arn

  tags = {
    Project = var.project_name
  }
}

#######################################################
# IAM role for CloudTrail to write to CloudWatch Logs
#######################################################
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}
