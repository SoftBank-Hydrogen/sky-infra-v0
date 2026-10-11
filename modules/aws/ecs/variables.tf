variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  description = "ECS 서비스 이름"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "alb_listener_arn" {
  description = "대상 그룹이 연결된 리스너. 서비스 생성 순서를 맞추는 데만 쓴다"
  type        = string
}

variable "instance_profile_name" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "instance_type" {
  description = "Docker 빌드까지 한 대에서 하므로 여유 있게 잡는다"
  type        = string
  default     = "t3.large"
}

variable "root_volume_gib" {
  description = "인스턴스 루트 볼륨 크기. 빌드 이미지, 캐시가 여기에 쌓인다"
  type        = number
  default     = 50
}

variable "image" {
  description = "컨테이너 이미지 (<ECR URL>:<git SHA>)"
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "task_cpu" {
  type    = number
  default = 1024
}

variable "task_memory" {
  description = "MiB. 사용자 앱 빌드는 호스트 Docker에서 돌아 이 한도 밖이다"
  type        = number
  default     = 3072
}

variable "state_path" {
  description = "컨테이너 안 .sky/ 경로. sky-platform 이미지의 작업 디렉터리와 맞춘다"
  type        = string
  default     = "/app/.sky"
}

variable "environment" {
  description = "컨테이너 환경변수 (비밀이 아닌 값)"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "환경변수 이름 → Secrets Manager ARN"
  type        = map(string)
  default     = {}
}

variable "log_group_name" {
  type = string
}

variable "exec_log_group_name" {
  type = string
}
