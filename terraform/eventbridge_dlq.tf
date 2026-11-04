###########################################################
# Dead-letter queue for failed EventBridge -> SNS deliveries
###########################################################
# In case of CMK deletion or disablement, EventBridge will fail to deliver the alert to SNS because SNS uses it to encrypt the messages in rest.
# The DLQ is a safety net for that case.
# DLQ -> CloudWatch Alarm -> SNS (unencrypted) -> Email

resource "aws_sqs_queue" "eventbridge_dlq" {
  name                      = "${var.project_name}-eventbridge-dlq"
  message_retention_seconds = 1209600 # 14 days (the maximum) to leave time to investigate
  # SQS-managed encryption (not the CMK): disabling or deleting the CMK must not
  # be able to break delivery to the DLQ, which is the safety net for the alert chain.
  sqs_managed_sse_enabled = true
}

# Only the three alert rules may send messages to the queue.
resource "aws_sqs_queue_policy" "eventbridge_dlq" {
  queue_url = aws_sqs_queue.eventbridge_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeRulesToSendFailedEvents"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.eventbridge_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_cloudwatch_event_rule.unauthorized_secret_read.arn,
              aws_cloudwatch_event_rule.secret_tampering.arn,
              aws_cloudwatch_event_rule.key_tampering.arn,
            ]
          }
        }
      }
    ]
  })
}

# A DLQ nobody looks at is still a silent failure, so alarm when anything lands in it.
resource "aws_cloudwatch_metric_alarm" "eventbridge_dlq_not_empty" {
  alarm_name          = "${var.project_name}-eventbridge-dlq-not-empty"
  alarm_description   = "EventBridge failed to deliver an alert; inspect the DLQ"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.eventbridge_dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  # Dedicated, unencrypted topic: it must keep working even if the CMK is disabled or deleted.
  alarm_actions = [aws_sns_topic.dlq_alerts.arn]
}

# Unencrypted topic for DLQ alerts to cover the cases that CMK is disabled or deleted.
resource "aws_sns_topic" "dlq_alerts" {
  name = "${var.project_name}-dlq-alert"
  # No kms_master_key_id on purpose: this topic must not depend on the CMK.
}

resource "aws_sns_topic_subscription" "dlq_alerts_email" {
  topic_arn = aws_sns_topic.dlq_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # confirm the subscription from the email AWS sends
}

resource "aws_sns_topic_policy" "dlq_alerts" {
  arn = aws_sns_topic.dlq_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowDlqAlarmPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.dlq_alerts.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_metric_alarm.eventbridge_dlq_not_empty.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
