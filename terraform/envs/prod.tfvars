# Production environment
# Usage: terraform apply -var-file=prod.tfvars
#
# environment = "prod" also switches on:
#   - 30-day recovery window on the secret (instead of immediate deletion)
#   - force_destroy = false on the CloudTrail log bucket

region       = "eu-west-1"
environment  = "prod"
owner        = "security-team"
project_name = "top-secret-prod"
secret_name  = "Secret01"

# Use a shared security distribution list, not a personal mailbox.
alert_email = "test@infracloud.uk"

# Break-glass role(s) allowed to read the monitored secret (they are exempt from the deny policy
# and from the unauthorized-read alert pattern only if also added there).
extra_secret_reader_arns = [
  # "arn:aws:iam::123456789012:role/break-glass-admin",
]
