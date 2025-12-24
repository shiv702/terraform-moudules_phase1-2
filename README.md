# Terraform Foundation (Account 970547338216, Region ap-south-1)

## What this creates
**Phase 1**
- CloudTrail + AWS Config + SNS (audit baseline)
- VPC + public/private subnets + IGW + NAT + route tables (network baseline)

**Phase 2 (optional)**
- 2 AWS CodePipelines (source = GitHub repo via CodeConnections) that run Terraform via CodeBuild:
  - Audit pipeline
  - Networking pipeline

---

## Prerequisites
- Terraform >= 1.6
- AWS CLI credentials that can deploy into account `970547338216` in `ap-south-1`
- If enabling pipelines: a GitHub repo with this code pushed, and an AWS CodeConnections connection ARN to GitHub (recommended)

---

## How to run (local execution) — exact commands

### 1) Clone your Git repo
```bash
git clone <your-git-repo-url>
cd terraform-foundation
```

### 2) Create tfvars
```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
```

### 3) Bootstrap remote state (creates S3 bucket + DynamoDB lock table)
This repo uses an S3 backend (`backend "s3" {}`), so do the first init with backend disabled:

```bash
terraform init -backend=false
terraform apply -target=module.tf_backend
```

### 4) Switch Terraform to S3 backend (migrate state)
```bash
terraform init -migrate-state   -backend-config="bucket=foundation-970547338216-tfstate"   -backend-config="key=foundation/root/terraform.tfstate"   -backend-config="region=ap-south-1"   -backend-config="dynamodb_table=foundation-tfstate-lock"
```

> If you changed `name_prefix` in tfvars, update these names:
> - bucket: `<name_prefix>-970547338216-tfstate` (lowercase)
> - table: `<name_prefix>-tfstate-lock`

### 5) Deploy resources
```bash
terraform plan
terraform apply
```

### 6) Destroy (if needed)
```bash
terraform destroy
```

---

## How to execute via GitHub (AWS CodePipeline) — optional

1) Push the repo to GitHub.
2) Create an **AWS CodeConnections** connection to GitHub in the AWS Console and copy the connection ARN.
3) In `terraform.tfvars`:
```hcl
enable_pipelines       = true
git_repo_full_name     = "org/repo"
pipeline_branch        = "main"
codestar_connection_arn = "arn:aws:codestar-connections:ap-south-1:<account>:connection/<id>"
```
4) Apply once locally to create pipelines:
```bash
terraform apply
```

Now commits to the repo will trigger the pipelines (manual approval before Apply).
