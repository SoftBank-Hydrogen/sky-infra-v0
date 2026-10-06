variable "name_prefix" {
  type = string
}

variable "create_provider" {
  description = "계정에 GitHub OIDC 공급자가 아직 없으면 true"
  type        = bool
  default     = true
}

variable "permissions_boundary_arn" {
  description = "모든 역할에 걸 권한 경계. 없으면 null"
  type        = string
  default     = null
}

variable "roles" {
  description = "역할 이름(접두어 제외) → 신뢰 조건과 권한"
  type = map(object({
    description         = string
    subjects            = list(string)
    managed_policy_arns = optional(list(string), [])
    inline_policy_json  = optional(string)
    max_session_seconds = optional(number, 3600)
  }))

  validation {
    condition = alltrue([
      for cfg in values(var.roles) : alltrue([
        for s in cfg.subjects : startswith(s, "repo:") && !contains(["repo:*", "repo:*/*"], s)
      ])
    ])
    error_message = "subjects는 repo:<org>/<repo>:... 형식이어야 하고, 모든 저장소를 허용하는 와일드카드는 쓸 수 없다."
  }
}
