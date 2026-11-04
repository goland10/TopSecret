variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment (test, prod)"
  type        = string
  #default     = "test"
}

variable "owner" {
  description = "Team or individual responsible for this project"
  type        = string
  default     = "security-team"
}

variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "top-secret"
}

variable "secret_name" {
  description = "Short name of the secret. It is created as <secret_name>/monitored."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.@=+-]+$", var.secret_name))
    error_message = "Use only letters, digits and _.@=+- (no slashes; the /monitored suffix is added automatically)."
  }
}

variable "extra_secret_reader_arns" {
  description = "Optional additional role ARNs allowed to read the monitored secret (e.g. break-glass admin)"
  type        = list(string)
  default     = [] 
}

variable "alert_email" {
  description = "Email address for the monitored secret access alerts"
  type        = string
  default     = ""
}
