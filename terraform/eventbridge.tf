###################
# EventBridge
###################

# --- Alert on unauthorized reads of the monitored secret ----------------
# This rule can work without any trail because it is configured to receive all CloudTrail read management events on the default bus.
resource "aws_cloudwatch_event_rule" "unauthorized_secret_read" {
  name        = "${var.project_name}-unauthorized-secret-read"
  description = "Alert when anyone other than Lambda reader/rotator reads ${local.secret_name}"
  #This state tells EventBridge to receive all CloudTrail management events on the default bus, including read-only ones like GetSecretValue. 
  #Without this, read-only API calls would not be forwarded to EventBridge at all (only write/mutating calls would be). Data events are not included.
  state       = "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"

  event_pattern = jsonencode({
    source        = ["aws.secretsmanager"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["secretsmanager.amazonaws.com"]
      eventName   = ["GetSecretValue", "BatchGetSecretValue"]
      requestParameters = {
        secretId = [{ wildcard = "*${local.secret_suffix}*" }]   # matches both the name and the full ARN
      }
      userIdentity = {
        arn = [{
          "anything-but" = [
            "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.lambda_reader.name}/${aws_lambda_function.reader.function_name}",
            "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.lambda_rotator.name}/${aws_lambda_function.rotator.function_name}",
          ]
        }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "unauthorized-secret-read_sns" {
  rule = aws_cloudwatch_event_rule.unauthorized_secret_read.name
  arn  = aws_sns_topic.secret_alerts.arn

  input_transformer {
    input_paths = {
      event  = "$.detail.eventName"
      secret = "$.detail.requestParameters.secretId"
      who    = "$.detail.userIdentity.arn"
      ip     = "$.detail.sourceIPAddress"
      time   = "$.detail.eventTime"
    }
    input_template = "\"Unauthorized secret read ALERT: <event> on <secret> by <who> from <ip> at <time>\""
  }

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }  
}

# --- Alert on tampering with the monitored secret (policy or configuration) ; Rotation is not included ----------------
# This rule depends on trail existence.
resource "aws_cloudwatch_event_rule" "secret_tampering" {
  name        = "${var.project_name}-secret-tampering"
  description = "Alert on changes to the policy or configuration of ${local.secret_name}"

  event_pattern = jsonencode({
    source        = ["aws.secretsmanager"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["secretsmanager.amazonaws.com"]
      eventName   = ["PutResourcePolicy", "DeleteResourcePolicy", "UpdateSecret", "DeleteSecret"]
      requestParameters = {
        secretId = [{ wildcard = "*${local.secret_suffix}*" }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "secret_tampering_sns" {
  rule = aws_cloudwatch_event_rule.secret_tampering.name
  arn  = aws_sns_topic.secret_alerts.arn

  input_transformer {
    input_paths = {
      event  = "$.detail.eventName"
      secret = "$.detail.requestParameters.secretId"
      who    = "$.detail.userIdentity.arn"
      ip     = "$.detail.sourceIPAddress"
      time   = "$.detail.eventTime"
    }
    input_template = "\"Secret tampering ALERT: <event> on <secret> by <who> from <ip> at <time>\""
  }

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }  
}

# --- Alert on tampering with the KMS key of the monitored secrets ----------------
# This rule depends on trail existence + KMS events *not* excluded from management events.
resource "aws_cloudwatch_event_rule" "key_tampering" {
  name        = "${var.project_name}-key-tampering"
  description = "Alert on changes to the CMK that protects the monitored secrets"

  event_pattern = jsonencode({
    source        = ["aws.kms"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["kms.amazonaws.com"]
      eventName   = ["PutKeyPolicy", "CreateGrant", "DisableKey", "ScheduleKeyDeletion"]
      "$or" = [
        # Successful calls: the key is in the request parameters
        {
          requestParameters = {
            keyId = [
              aws_kms_key.secrets.key_id,
              aws_kms_key.secrets.arn,
              aws_kms_alias.secrets.name,
            ]
          }
        },
        # Denied calls: requestParameters is empty, the key ARN is in the error text
        {
          errorMessage = [{ wildcard = "*${aws_kms_key.secrets.key_id}*" }]
        }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "key_tampering_sns" {
  rule = aws_cloudwatch_event_rule.key_tampering.name
  arn  = aws_sns_topic.secret_alerts.arn

  input_transformer {
    input_paths = {
      event = "$.detail.eventName"
      who   = "$.detail.userIdentity.arn"
      ip    = "$.detail.sourceIPAddress"
      time  = "$.detail.eventTime"
    }
    input_template = "\"Key tampering ALERT: <event> on the KMS key by <who> from <ip> at <time>\""
  }

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }
}
