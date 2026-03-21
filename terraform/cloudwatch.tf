# SNS topic — receptor de todas las alarmas
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# Dashboard — observación activa del sistema
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          region  = "us-east-1"
          title   = "SQS — Mensajes pendientes"
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.project_name}-queue"]]
          period  = 60
          stat    = "Sum"
        }
      },
      {
        type = "metric"
        properties = {
          region  = "us-east-1"
          title   = "Lambda — Errores"
          metrics = [["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-image-processor"]]
          period  = 300
          stat    = "Sum"
        }
      },
      {
        type = "metric"
        properties = {
          region  = "us-east-1"
          title   = "CloudFront — Cache Hit Ratio"
          metrics = [["AWS/CloudFront", "CacheHitRate", "DistributionId", aws_cloudfront_distribution.main.id, "Region", "Global"]]
          period  = 300
          stat    = "Average"
        }
      },
      {
        type = "metric"
        properties = {
          region  = "us-east-1"
          title   = "DynamoDB — Write Capacity"
          metrics = [["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "${var.project_name}-metadata"]]
          period  = 300
          stat    = "Sum"
        }
      }
    ]
  })
}

# Alarma 1 — mensajes acumulados en SQS
# Si hay más de 100 mensajes sin procesar, Lambda está atrasada o rota
resource "aws_cloudwatch_metric_alarm" "sqs_backlog" {
  alarm_name          = "${var.project_name}-sqs-backlog"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = "${var.project_name}-queue" }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 100
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Alarma 2 — errores de Lambda
# Más de 5 errores en 5 minutos indica problema sistémico
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = "${var.project_name}-image-processor" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Alarma 3 — cache hit ratio bajo
# Por debajo de 80% CloudFront no está cumpliendo su función
resource "aws_cloudwatch_metric_alarm" "cloudfront_cache" {
  alarm_name  = "${var.project_name}-cloudfront-cache"
  namespace   = "AWS/CloudFront"
  metric_name = "CacheHitRate"
  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
    Region         = "Global"
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
