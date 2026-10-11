variable "name_prefix" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "http_5xx_threshold" {
  description = "이 건수 이상이면 5xx 알람"
  type        = number
  default     = 10
}

variable "http_5xx_period_seconds" {
  type    = number
  default = 300
}
