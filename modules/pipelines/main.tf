locals {
  artifact_bucket_name = lower(replace("${var.name_prefix}-${var.aws_account_id}-codepipeline-artifacts", "_", "-"))
}

resource "aws_codestarconnections_connection" "github" {
  count         = var.create_codestar_connection ? 1 : 0
  name          = var.codestar_connection_name
  provider_type = "GitHub"
  tags          = var.tags
}

locals {
  connection_arn = var.create_codestar_connection ? aws_codestarconnections_connection.github[0].arn : var.codestar_connection_arn
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Name = local.artifact_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["codepipeline.amazonaws.com"] }
  }
}

resource "aws_iam_role" "codepipeline" {
  for_each           = var.pipeline_defs
  name               = "${var.name_prefix}-${each.key}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["codebuild.amazonaws.com"] }
  }
}

resource "aws_iam_role" "codebuild" {
  for_each           = var.pipeline_defs
  name               = "${var.name_prefix}-${each.key}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild_policy" {
  for_each = var.pipeline_defs

  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
      "arn:aws:s3:::${var.tf_state_bucket}",
      "arn:aws:s3:::${var.tf_state_bucket}/*"
    ]
  }

  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem", "dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.tf_lock_table}"]
  }

  statement {
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  for_each = var.pipeline_defs
  name     = "${var.name_prefix}-${each.key}-codebuild-inline"
  role     = aws_iam_role.codebuild[each.key].id
  policy   = data.aws_iam_policy_document.codebuild_policy[each.key].json
}

data "aws_iam_policy_document" "codepipeline_policy" {
  for_each = var.pipeline_defs

  statement {
    actions = ["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  statement {
    actions   = ["codestar-connections:UseConnection"]
    resources = [local.connection_arn]
  }

  statement {
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  for_each = var.pipeline_defs
  name     = "${var.name_prefix}-${each.key}-codepipeline-inline"
  role     = aws_iam_role.codepipeline[each.key].id
  policy   = data.aws_iam_policy_document.codepipeline_policy[each.key].json
}

locals {
  buildspec_plan = <<YAML
version: 0.2
phases:
  install:
    commands:
      - echo "Installing Terraform..."
      - TF_VERSION="1.12.2"
      - curl -sSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
      - unzip -o /tmp/terraform.zip -d /usr/local/bin
      - terraform -version
  pre_build:
    commands:
      - cd ${TF_WORKING_DIR}
      - terraform init -input=false -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="region=${AWS_REGION}" -backend-config="dynamodb_table=${TF_LOCK_TABLE}"
  build:
    commands:
      - terraform validate
      - terraform plan -input=false ${TF_TARGET_ARGS}
YAML

  buildspec_apply = <<YAML
version: 0.2
phases:
  install:
    commands:
      - echo "Installing Terraform..."
      - TF_VERSION="1.12.2"
      - curl -sSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
      - unzip -o /tmp/terraform.zip -d /usr/local/bin
      - terraform -version
  pre_build:
    commands:
      - cd ${TF_WORKING_DIR}
      - terraform init -input=false -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="region=${AWS_REGION}" -backend-config="dynamodb_table=${TF_LOCK_TABLE}"
  build:
    commands:
      - terraform validate
      - terraform plan -input=false -out=tfplan ${TF_TARGET_ARGS}
      - terraform apply -input=false -auto-approve tfplan
YAML
}

resource "aws_codebuild_project" "plan" {
  for_each     = var.pipeline_defs
  name         = "${var.name_prefix}-${each.key}-tf-plan"
  service_role = aws_iam_role.codebuild[each.key].arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable { name = "AWS_REGION",      value = var.aws_region }
    environment_variable { name = "TF_WORKING_DIR",  value = each.value.working_dir }
    environment_variable { name = "TF_STATE_BUCKET", value = var.tf_state_bucket }
    environment_variable { name = "TF_LOCK_TABLE",   value = var.tf_lock_table }
    environment_variable { name = "TF_STATE_KEY",    value = var.tf_state_key }

    environment_variable {
      name  = "TF_TARGET_ARGS"
      value = join(" ", [for t in each.value.tf_targets : "-target=${t}"])
    }
  }

  source { type = "CODEPIPELINE", buildspec = local.buildspec_plan }
  tags = var.tags
}

resource "aws_codebuild_project" "apply" {
  for_each     = var.pipeline_defs
  name         = "${var.name_prefix}-${each.key}-tf-apply"
  service_role = aws_iam_role.codebuild[each.key].arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable { name = "AWS_REGION",      value = var.aws_region }
    environment_variable { name = "TF_WORKING_DIR",  value = each.value.working_dir }
    environment_variable { name = "TF_STATE_BUCKET", value = var.tf_state_bucket }
    environment_variable { name = "TF_LOCK_TABLE",   value = var.tf_lock_table }
    environment_variable { name = "TF_STATE_KEY",    value = var.tf_state_key }

    environment_variable {
      name  = "TF_TARGET_ARGS"
      value = join(" ", [for t in each.value.tf_targets : "-target=${t}"])
    }
  }

  source { type = "CODEPIPELINE", buildspec = local.buildspec_apply }
  tags = var.tags
}

resource "aws_codepipeline" "this" {
  for_each = var.pipeline_defs

  name     = "${var.name_prefix}-${each.key}-pipeline"
  role_arn = aws_iam_role.codepipeline[each.key].arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = local.connection_arn
        FullRepositoryId = var.git_repo_full_name
        BranchName       = var.branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name            = "TerraformPlan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = { ProjectName = aws_codebuild_project.plan[each.key].name }
    }
  }

  stage {
    name = "Approve"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  stage {
    name = "Apply"
    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = { ProjectName = aws_codebuild_project.apply[each.key].name }
    }
  }

  tags = var.tags
}
