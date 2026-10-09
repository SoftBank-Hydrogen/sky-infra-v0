output "github_role_arns" {
  description = "GitHub Actions 변수 AWS_PLAN_ROLE_ARN, AWS_APPLY_ROLE_ARN에 넣는다"
  value       = module.github_oidc.role_arns
}

output "published_parameters" {
  value = module.published_outputs.parameter_names
}

output "service_url" {
  value = module.edge.service_url
}

output "alb_dns_name" {
  value = module.edge.alb_dns_name
}

output "cognito_user_pool_id" {
  description = "Sky 사용자는 이 풀에 관리자가 직접 만든다"
  value       = module.edge.cognito_user_pool_id
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "secret_arns" {
  description = "값은 적용 후 콘솔이나 CLI로 넣는다"
  value       = module.secrets.secret_arns
}

output "sky_task_role_arn" {
  value = module.iam.task_role_arn
}

output "platform_deploy_role_arn" {
  description = "sky-platform 저장소 GitHub Actions가 위임받을 역할"
  value       = module.github_oidc.role_arns["platform-deploy"]
}

output "platform_release_role_arn" {
  description = "GitHub 저장소 변수 AWS_PLATFORM_RELEASE_ROLE_ARN에 넣는다"
  value       = module.github_oidc.role_arns["platform-release"]
}

output "alarm_topic_arn" {
  value = module.observability.alarm_topic_arn
}
