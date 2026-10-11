variable "name_prefix" {
  type = string
}

variable "platform_repository_arn" {
  description = "서비스 서버 이미지 ECR 레포(sky-platform) ARN"
  type        = string
}

variable "secret_arns" {
  description = "태스크에 주입할 비밀 ARN 목록"
  type        = list(string)
}

variable "log_group_name" {
  description = "서비스 서버 앱 로그 그룹 이름"
  type        = string
}

variable "exec_log_group_name" {
  description = "ECS Exec 세션 기록 로그 그룹 이름"
  type        = string
}

variable "cluster_name" {
  description = "서비스 서버 ECS 클러스터 이름 (GitHub 배포 역할 범위)"
  type        = string
}

variable "service_name" {
  description = "서비스 서버 ECS 서비스 이름 (GitHub 배포 역할 범위)"
  type        = string
}

variable "state_bucket_name" {
  description = "Terraform state 버킷 (이미지 배포 역할 범위)"
  type        = string
}

variable "state_key" {
  description = "이 환경 state 객체 키 (이미지 배포 역할 범위)"
  type        = string
}
