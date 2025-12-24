output "pipelines" { value = { for k, p in aws_codepipeline.this : k => p.name } }
output "codestar_connection_arn" { value = local.connection_arn }
output "artifacts_bucket" { value = aws_s3_bucket.artifacts.bucket }
