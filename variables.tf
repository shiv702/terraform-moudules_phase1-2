variable "aws_account_id" {
  description = "AWS account id where the resources will be deployed."
  type        = string
  default     = "970547338216"
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
  default     = "foundation"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags."
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Project   = "Foundation"
  }
}

# ---------- Networking inputs ----------
variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnets" {
  description = "Map of subnets to create."
  type = map(object({
    cidr = string
    az   = string
    type = string # public or private
    tags = optional(map(string), {})
  }))
}

variable "nat_gateway_strategy" {
  description = "NAT strategy: none | single | per_az"
  type        = string
  default     = "single"
  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_gateway_strategy)
    error_message = "nat_gateway_strategy must be one of: none, single, per_az"
  }
}

# ---------- Audit inputs ----------
variable "enable_cloudtrail" {
  type    = bool
  default = true
}

variable "enable_config" {
  type    = bool
  default = true
}

variable "cloudtrail_multi_region" {
  type    = bool
  default = true
}

variable "cloudtrail_enable_cloudwatch_logs" {
  type    = bool
  default = true
}

variable "sns_email_subscriptions" {
  description = "Map of subscription name => email address."
  type        = map(string)
  default     = {}
}

variable "config_managed_rules" {
  description = "Managed AWS Config rules to create (key=rule name)."
  type = map(object({
    identifier       = string
    input_parameters = optional(map(string), {})
    scope = optional(object({
      compliance_resource_types = optional(list(string))
      compliance_resource_id    = optional(string)
      tag_key                   = optional(string)
      tag_value                 = optional(string)
    }))
  }))
  default = {}
}

# ---------- Remote state ----------
variable "tf_state_key" {
  description = "S3 key for the root Terraform state (used when backend is s3)."
  type        = string
  default     = "foundation/root/terraform.tfstate"
}

# ---------- Optional pipelines (GitHub via AWS CodeConnections) ----------
variable "enable_pipelines" {
  description = "Create CodePipelines (Audit and Networking) that run Terraform via CodeBuild."
  type        = bool
  default     = false
}

variable "pipeline_branch" {
  description = "Git branch to watch."
  type        = string
  default     = "main"
}

variable "git_repo_full_name" {
  description = "Git repository full name, e.g. 'my-org/terraform-foundation'."
  type        = string
  default     = ""
}

variable "create_codestar_connection" {
  description = "If true, Terraform creates a CodeStar connection (GitHub). You must COMPLETE the handshake in AWS Console."
  type        = bool
  default     = false
}

variable "codestar_connection_arn" {
  description = "Existing CodeStar connection ARN (recommended)."
  type        = string
  default     = ""
}

variable "codestar_connection_name" {
  description = "Name for the CodeStar connection when create_codestar_connection=true."
  type        = string
  default     = "foundation-github-connection"
}
