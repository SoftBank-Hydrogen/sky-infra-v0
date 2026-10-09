output "log_group_name" {
  value = aws_cloudwatch_log_group.platform.name
}

output "exec_log_group_name" {
  value = aws_cloudwatch_log_group.exec.name
}

output "alarm_topic_arn" {
  description = "알람 수신처(이메일, 이후 Chatbot)는 이 토픽에 구독"
  value       = aws_sns_topic.alarms.arn
}
