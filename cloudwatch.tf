resource "aws_cloudwatch_metric_alarm" "vote_client_cpu_high" {
  alarm_name          = "vote-client-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale up vote-client if CPU > 70% for 2 minutes"
  dimensions = {
    ClusterName = aws_ecs_cluster.vote_cluster.name
    ServiceName = aws_ecs_service.client_service.name
  }
  alarm_actions = [aws_appautoscaling_policy.vote_client_scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "vote_client_cpu_low" {
  alarm_name          = "vote-client-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale down vote-client if CPU < 30% for 2 minutes"
  dimensions = {
    ClusterName = aws_ecs_cluster.vote_cluster.name
    ServiceName = aws_ecs_service.client_service.name
  }
  alarm_actions = [aws_appautoscaling_policy.vote_client_scale_down.arn]
}

resource "aws_cloudwatch_log_group" "vote_server_logs" {
  name              = "/ecs/vote-server"
  retention_in_days = 1
}