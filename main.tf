module "tf_backend" {
  source         = "./modules/tf_backend"
  aws_account_id = var.aws_account_id
  name_prefix    = var.name_prefix
  tags           = var.tags
}

module "network" {
  source               = "./modules/network_baseline"
  name_prefix          = var.name_prefix
  vpc_cidr             = var.vpc_cidr
  subnets              = var.subnets
  nat_gateway_strategy = var.nat_gateway_strategy
  tags                 = var.tags
}

module "audit" {
  source                        = "./modules/audit_baseline"
  aws_account_id                = var.aws_account_id
  name_prefix                   = var.name_prefix
  enable_cloudtrail             = var.enable_cloudtrail
  enable_config                 = var.enable_config
  cloudtrail_multi_region       = var.cloudtrail_multi_region
  cloudtrail_enable_cw_logs     = var.cloudtrail_enable_cloudwatch_logs
  sns_email_subscriptions       = var.sns_email_subscriptions
  config_managed_rules          = var.config_managed_rules
  tags                          = var.tags
}

module "pipelines" {
  source = "./modules/pipelines"
  count  = var.enable_pipelines ? 1 : 0

  aws_account_id             = var.aws_account_id
  aws_region                 = var.aws_region
  name_prefix                = var.name_prefix
  branch                     = var.pipeline_branch
  git_repo_full_name         = var.git_repo_full_name
  create_codestar_connection = var.create_codestar_connection
  codestar_connection_arn    = var.codestar_connection_arn
  codestar_connection_name   = var.codestar_connection_name

  tf_state_bucket = module.tf_backend.tfstate_bucket
  tf_lock_table   = module.tf_backend.lock_table
  tf_state_key    = var.tf_state_key

  tags = var.tags

  pipeline_defs = {
    audit = {
      working_dir = "."
      tf_targets  = ["module.audit"]
    }
    networking = {
      working_dir = "."
      tf_targets  = ["module.network"]
    }
  }

  depends_on = [module.tf_backend, module.audit, module.network]
}
