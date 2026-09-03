# ── Route53 Health Checks ─────────────────────────────────────────────────────
# Calculated health check aggregating CloudWatch alarm states.
# Reports platform as unhealthy when any critical alarm fires.
# No public endpoint required — monitors alarm state directly.

resource "aws_route53_health_check" "pod_cpu_critical" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.pod_cpu_critical.alarm_name
  cloudwatch_alarm_region         = "us-east-1"
  insufficient_data_health_status = "Healthy"

  tags = {
    Name = "stratum-pod-cpu-critical"
  }
}

resource "aws_route53_health_check" "pod_memory_critical" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.pod_memory_critical.alarm_name
  cloudwatch_alarm_region         = "us-east-1"
  insufficient_data_health_status = "Healthy"

  tags = {
    Name = "stratum-pod-memory-critical"
  }
}

resource "aws_route53_health_check" "pod_restart" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.pod_restart.alarm_name
  cloudwatch_alarm_region         = "us-east-1"
  insufficient_data_health_status = "Healthy"

  tags = {
    Name = "stratum-pod-restart"
  }
}

resource "aws_route53_health_check" "pod_count_low" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.pod_count_low.alarm_name
  cloudwatch_alarm_region         = "us-east-1"
  insufficient_data_health_status = "Healthy"

  tags = {
    Name = "stratum-pod-count-low"
  }
}

resource "aws_route53_health_check" "platform_aggregate" {
  type                   = "CALCULATED"
  child_health_threshold = 4
  child_healthchecks = [
    aws_route53_health_check.pod_cpu_critical.id,
    aws_route53_health_check.pod_memory_critical.id,
    aws_route53_health_check.pod_restart.id,
    aws_route53_health_check.pod_count_low.id,
  ]

  tags = {
    Name = "stratum-platform-aggregate"
  }
}

# ── Route53 Health Check Alarm ────────────────────────────────────────────────
# Fires when the aggregate health check reports unhealthy.
# This is the single alarm that says "the platform is down."

resource "aws_cloudwatch_metric_alarm" "platform_health" {
  alarm_name          = "stratum-platform-health"
  alarm_description   = "Platform aggregate health check failed - one or more critical alarms active"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.platform_aggregate.id
  }

  alarm_actions = [aws_sns_topic.platform_alerts.arn]

  tags = {
    Severity = "critical"
  }
}
