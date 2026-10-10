variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_account_id" {
  description = "대상 AWS 계정 ID. tfvars(로컬) 또는 TF_VAR_aws_account_id(CI)로만 넘긴다"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "12자리 AWS 계정 ID여야 한다."
  }
}

variable "github_org" {
  type    = string
  default = "SoftBank-Hydrogen"
}

variable "platform_oidc_subject_prefix" {
  description = "GitHub sky-platform OIDC sub_claim_prefix, including immutable owner/repository IDs"
  type        = string
  default     = "repo:SoftBank-Hydrogen@338183202/sky-platform@1407769237"

  validation {
    condition     = can(regex("^repo:[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.platform_oidc_subject_prefix))
    error_message = "Use the immutable repo:owner@ID/repository@ID prefix returned by GitHub OIDC customization."
  }
}

variable "create_github_oidc_provider" {
  description = "계정에 GitHub OIDC 공급자가 이미 있으면 false"
  type        = bool
  default     = true
}

variable "infra_apply_policy_arns" {
  description = "apply 역할에 붙일 정책 ARN 목록"
  type        = list(string)
}

variable "zone_name" {
  description = "콘솔에서 만든 Route 53 호스팅 영역. Terraform은 읽기만 한다"
  type        = string
  default     = "cloudas.store"
}

variable "service_domain" {
  description = "Sky 서비스 주소"
  type        = string
  default     = "cloudas.store"
}

variable "health_check_path" {
  description = "ALB 헬스 체크 경로. sky-platform에 /healthz가 생기면 바꾼다"
  type        = string
  default     = "/"
}

variable "enable_auth" {
  description = "ALB 앞단 Cognito 로그인. 인터넷에 열리므로 끄지 않는다"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "Sky ECS 인스턴스 유형 (Docker 빌드 포함)"
  type        = string
  default     = "t3.large"
}

variable "platform_image_tag" {
  description = "서비스 서버 이미지 태그(sky-platform 커밋의 7자리 git SHA). platform-image.auto.tfvars에서만 바꾼다"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7}$", var.platform_image_tag))
    error_message = "platform_image_tag는 7자리 소문자 git SHA여야 한다."
  }
}
