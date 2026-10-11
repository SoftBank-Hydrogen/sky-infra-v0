# [Observability] 서비스 서버 로그와 기본 알람 설정
# 컨테이너 로그는 CloudWatch에 30일 쌓고, AWS 기본 지표로 알람 두 개를 걸어 SNS 토픽

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_cloudwatch_log_group" "platform" {
  name              = "/${var.name_prefix}/platform"
  retention_in_days = var.log_retention_days
}

# 운영자의 ECS Exec 세션 기록
resource "aws_cloudwatch_log_group" "exec" {
  name              = "/${var.name_prefix}/ecs-exec"
  retention_in_days = var.log_retention_days
}

resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
}

# 태스크가 1개뿐이라 정상 타깃이 0이면 곧 서비스 중단
resource "aws_cloudwatch_metric_alarm" "no_healthy_target" {
  alarm_name          = "${var.name_prefix}-no-healthy-target"
  alarm_description   = "Sky ALB 정상 타깃이 없다 (서비스 중단)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ALB 자체 5xx와 Sky가 돌려준 5xx를 합쳐 봄
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.name_prefix}-http-5xx"
  alarm_description   = "Sky ALB 5xx 급증 (${var.http_5xx_period_seconds}초에 ${var.http_5xx_threshold}건 이상)"
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.http_5xx_threshold
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "total"
    expression  = "FILL(elb, 0) + FILL(target, 0)"
    label       = "ELB + target 5xx"
    return_data = true
  }

  metric_query {
    id = "elb"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      stat        = "Sum"
      period      = var.http_5xx_period_seconds
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "target"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      stat        = "Sum"
      period      = var.http_5xx_period_seconds
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
        TargetGroup  = var.target_group_arn_suffix
      }
    }
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
