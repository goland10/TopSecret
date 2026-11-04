###################
# SNS
###################

resource "aws_sns_topic" "secret_alerts" {
  name = "${var.project_name}-alert"
  kms_master_key_id = aws_kms_key.secrets.arn     #Topic is encrypted with CMK
}

resource "aws_sns_topic_subscription" "secret_alerts_email" {
  topic_arn = aws_sns_topic.secret_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email                     # you must confirm the subscription from the email AWS sends
}

# --- Allow EventBridge and CloudWatch to publish to the topic ----------------
resource "aws_sns_topic_policy" "secret_alerts" {
  arn = aws_sns_topic.secret_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.secret_alerts.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_cloudwatch_event_rule.unauthorized_secret_read.arn,
              aws_cloudwatch_event_rule.secret_tampering.arn,
              aws_cloudwatch_event_rule.key_tampering.arn,
            ]
          }
        }
      },
      {
        Sid       = "AllowCloudWatchAlarmPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.secret_alerts.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_metric_alarm.secret_rotation_burst.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
