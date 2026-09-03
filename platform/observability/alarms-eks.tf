# ── EKS Workload Alarms ──────────────────────────────────────────────────────
# Flash sale alert thresholds. Warning at 70%, critical at 90%.
# Pod restarts and count drops are always critical — any occurrence
# during a flash sale means lost revenue.

resource "aws_cloudwatch_metric_alarm" "pod_cpu_warning" {
  alarm_name          = "stratum-pod-cpu-warning"
  alarm_description   = "Pod CPU utilisation exceeds 70% - investigate workload scaling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = "eks-platform"
    Namespace   = "stratum-workloads"
  }

  alarm_actions = [aws_sns_topic.platform_alerts.arn]

  tags = {
    Severity = "warning"
  }
}

resource "aws_cloudwatch_metric_alarm" "pod_cpu_critical" {
  alarm_name          = "stratum-pod-cpu-critical"
  alarm_description   = "Pod CPU utilisation exceeds 90% - immediate scaling required"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = "eks-platform"
    Namespace   = "stratum-workloads"
  }

  alarm_actions = [aws_sns_topic.platform_alerts.arn]

  tags = {
    Severity = "critical"
  }
}

resource "aws_cloudwatch_metric_alarm" "pod_memory_warning" {
  alarm_name          = "stratum-pod-memory-warning"
  alarm_description   = "Pod memory utilisation exceeds 70% - investigate memory pressure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = "eks-platform"
    Namespace   = "stratum-workloads"
  }

  alarm_actions = [aws_sns_topic.platform_alerts.arn]

  tags = {
    Severity = "warning"
  }
}

resource "aws_cloudwatch_metric_alarm" "pod_memory_critical" {
  alarm_name          = "stratum-pod-memory-critical"
  alarm_description   = "Pod memory utilisation exceeds 90% - OOM kill imminent"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pod_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = "eks-platform"
    Namespace   = "stratum-workloads"
  }

  alarm_actions = [aws_sns_topic.platform_alerts.arn]

  tags = {
    Severity = "critical"
  }
}

resource "aws_cloudwatch_metric_alarm" "pod_restart" {
  alarm_name          = "stratum-pod-restart"
  alarm_description   = "Pod restart detected - container crashed during operation"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = "eks-platform"
    Namespace   = "stratum-workloads"
  }

  alarm_actions = [aws_sns_topic.platform_alerts.arn]

  tags = {
    Severity = "critical"
  }
}

resource "aws_cloudwatch_metric_alarm" "pod_count_low" {
  alarm_name          = "stratum-pod-count-low"
  alarm_description   = "Running pod count below expected - capacity reduced"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "namespace_number_of_running_pods"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 4
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = "eks-platform"
    Namespace   = "stratum-workloads"
  }

  alarm_actions = [aws_sns_topic.platform_alerts.arn]

  tags = {
    Severity = "critical"
  }
}

# ── SNS Reference ─────────────────────────────────────────────────────────────


