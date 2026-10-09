output "instance_profile_name" {
  value = aws_iam_instance_profile.instance.name
}

output "instance_role_arn" {
  value = aws_iam_role.instance.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "github_deploy_policy_json" {
  description = "github-oidc 모듈의 sky-platform 배포 역할에 넣는 인라인 정책"
  value       = data.aws_iam_policy_document.github_deploy.json
}

output "platform_release_policy_json" {
  description = "github-oidc 모듈의 sky-infra 이미지 배포 역할에 넣는 인라인 정책"
  value       = data.aws_iam_policy_document.platform_release.json
}
