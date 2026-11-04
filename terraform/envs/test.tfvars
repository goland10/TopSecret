# Test environment
# Usage: terraform apply -var-file=test.tfvars

region       = "eu-west-1"
environment  = "test"
owner        = "security-team"
project_name = "top-secret"
secret_name  = "Secret01"

# Replace with a real, monitored mailbox. You must confirm the SNS subscription email.
alert_email = "test@infracloud.uk"

# No extra readers in test.
extra_secret_reader_arns = ["arn:aws:iam::643218715566:user/tester-admin"]
