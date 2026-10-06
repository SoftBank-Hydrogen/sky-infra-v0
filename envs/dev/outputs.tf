output "github_role_arns" {
  description = "GitHub Actions 변수 AWS_PLAN_ROLE_ARN, AWS_APPLY_ROLE_ARN에 넣는다"
  value       = module.github_oidc.role_arns
}

output "published_parameters" {
  value = module.published_outputs.parameter_names
}
