locals {
  project_name = "${var.project_name}-${var.environment}"
}

locals {
  secret_suffix = "/monitored"
  secret_name   = "${var.secret_name}${local.secret_suffix}"
}

data "aws_caller_identity" "current" {}