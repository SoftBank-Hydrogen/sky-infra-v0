output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.this.name
}

output "task_definition_family" {
  value = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "sky-platform CI가 태스크 정의에서 이미지를 바꿀 컨테이너"
  value       = local.container_name
}

output "state_file_system_id" {
  value = aws_efs_file_system.state.id
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.this.name
}
