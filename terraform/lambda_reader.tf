##################################################
# Lambda that reads the monitored secret
##################################################

# --- The function -----------------------------------------------------------

resource "aws_lambda_function" "reader" {
  function_name    = local.lambda_reader_name
  description      = "Reads the monitored secret (returns metadata only, never the value)"
  role             = aws_iam_role.lambda_reader.arn
  runtime          = "python3.13"
  handler          = "lambda_reader.lambda_handler"
  filename         = data.archive_file.lambda_reader.output_path
  source_code_hash = data.archive_file.lambda_reader.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      SECRET_ID = aws_secretsmanager_secret.top_secret.arn
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda_reader.name
  }  

  depends_on = [
    aws_cloudwatch_log_group.lambda_reader,
    aws_iam_role_policy.lambda_reader,
  ]
}

locals {
  lambda_reader_name = "${var.project_name}-lambda-reader"
}

# --- Package the code --------------------------------------------------------

data "archive_file" "lambda_reader" {
  type        = "zip"
  source_file = "${path.module}/lambda_reader.py"
  output_path = "${path.module}/lambda_reader.zip"
}

# --- Log group (created explicitly so retention is controlled) --------------

resource "aws_cloudwatch_log_group" "lambda_reader" {
  name              = "/${var.project_name}/${var.environment}/lambda-reader"
  retention_in_days = 30
}

# --- Execution role ---------------------------------------------------------

data "aws_iam_policy_document" "lambda_reader_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_reader" {
  name               = "${local.lambda_reader_name}-role"
  description        = "Execution role for ${local.lambda_reader_name}"
  assume_role_policy = data.aws_iam_policy_document.lambda_reader_trust.json
}

data "aws_iam_policy_document" "lambda_reader_access" {
  statement {
    sid       = "ReadTheMonitoredSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.top_secret.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda_reader.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_reader" {
  name   = "${local.lambda_reader_name}-policy"
  role   = aws_iam_role.lambda_reader.id
  policy = data.aws_iam_policy_document.lambda_reader_access.json
}

