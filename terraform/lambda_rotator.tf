####################################################
# Lambda to rotate (and read) the monitored secret
####################################################

# --- The function -----------------------------------------------------------
resource "aws_lambda_function" "rotator" {
  function_name    = "${var.project_name}-lambda-rotator"
  description      = "Reads and rotates the monitored secret"
  role             = aws_iam_role.lambda_rotator.arn
  runtime          = "python3.13"
  handler          = "lambda_rotator.lambda_handler"
  filename         = data.archive_file.lambda_rotator.output_path
  source_code_hash = data.archive_file.lambda_rotator.output_base64sha256
  timeout          = 30

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda_rotator.name
  }
  
  depends_on = [
    aws_cloudwatch_log_group.lambda_rotator,
    aws_iam_role_policy.lambda_rotator,
  ]
}

resource "aws_lambda_permission" "rotator_secretsmanager" {
  statement_id   = "AllowSecretsManagerInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rotator.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_arn     = aws_secretsmanager_secret.top_secret.arn
  source_account = data.aws_caller_identity.current.account_id
}

# --- Package the code --------------------------------------------------------
data "archive_file" "lambda_rotator" {
  type        = "zip"
  source_file = "${path.module}/lambda_rotator.py"
  output_path = "${path.module}/lambda_rotator.zip"
}

# --- Log group --------------
resource "aws_cloudwatch_log_group" "lambda_rotator" {
  name              = "/${var.project_name}/${var.environment}/lambda-rotator"
  retention_in_days = 30
}

# --- Execution role ---------------------------------------------------------
data "aws_iam_policy_document" "lambda_rotator_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_rotator" {
  name               = "${var.project_name}-lambda-rotator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_rotator_trust.json
}

data "aws_iam_policy_document" "lambda_rotator_access" {
  statement {
    sid       = "ReadTheMonitoredSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.top_secret.arn]
  }

  statement {
    sid = "RotateTheMonitoredSecret"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = [aws_secretsmanager_secret.top_secret.arn]
  }

  statement {
    sid       = "GenerateRandomPassword"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda_rotator.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_rotator" {
  name   = "${var.project_name}-lambda-rotator-policy"
  role   = aws_iam_role.lambda_rotator.id
  policy = data.aws_iam_policy_document.lambda_rotator_access.json
}

