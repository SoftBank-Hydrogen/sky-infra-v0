variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "github_org" {
  type    = string
  default = "SoftBank-Hydrogen"
}

variable "create_github_oidc_provider" {
  description = "계정에 GitHub OIDC 공급자가 이미 있으면 false"
  type        = bool
  default     = true
}

variable "infra_apply_policy_arns" {
  description = "apply 역할에 붙일 정책. 범위는 docs/decisions/0002-apply-role-scope.md에서 정한다"
  type        = list(string)
}
