resource "aws_cloudwatch_log_metric_filter" "secret_rotation" {
  name           = "${var.project_name}-secret-rotation"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = "{ ($.eventSource = \"secretsmanager.amazonaws.com\") && ($.eventName = \"RotateSecret\") && ($.requestParameters.secretId = \"*${local.secret_name}*\") }"

  metric_transformation {
    name      = "SecretRotationCount"
    namespace = "${var.project_name}/Security"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "secret_rotation_burst" {
  alarm_name          = "${var.project_name}-rotation-burst"
  alarm_description   = "${local.secret_name} rotated 2 or more times within 1 minute"
  namespace           = "${var.project_name}/Security"
  metric_name         = "SecretRotationCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.secret_alerts.arn]
}
