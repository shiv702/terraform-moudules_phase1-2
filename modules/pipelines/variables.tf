variable "aws_account_id" { type = string }
variable "aws_region"     { type = string }
variable "name_prefix"    { type = string }
variable "branch"         { type = string, default = "main" }
variable "tags"           { type = map(string), default = {} }

variable "git_repo_full_name" {
  description = "GitHub repository in the form 'org/repo'."
  type        = string
}

variable "create_codestar_connection" {
  type    = bool
  default = false
}

variable "codestar_connection_arn" {
  type    = string
  default = ""
}

variable "codestar_connection_name" {
  type    = string
  default = "foundation-github-connection"
}

variable "tf_state_bucket" { type = string }
variable "tf_lock_table"   { type = string }
variable "tf_state_key"    { type = string }

variable "pipeline_defs" {
  type = map(object({
    working_dir = string
    tf_targets  = list(string)
  }))
}
