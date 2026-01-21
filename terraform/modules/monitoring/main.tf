variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_lambda_function_name" {
  description = "List of Lambda function names to monitor"
  type        = list(string)
  default     = []
}

variable "aws_kinesis_stream_name" {
  description = "Kinesis stream name to monitor"
  type        = string
  default     = ""
}

variable "step_function_arn" {
  description = "Step function state machine ARN to monitor"
  type        = string
  # default     = ""
}

variable "alarm_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = "aws-root-ananke@thefactor.org"
}

# SNS Topic for Alarms
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-${var.environment}-alarms"

  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Lambda Error Rate Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.aws_lambda_function_name)

  alarm_name          = "${each.value}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda function ${each.value} error rate is too high"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }

  treat_missing_data = "notBreaching"
}

# Lambda Duration Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = toset(var.aws_lambda_function_name)

  alarm_name          = "${each.value}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 30000 # 30 Seconds
  alarm_description   = "Lambda function ${each.value} duration is too high"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }

  treat_missing_data = "notBreaching"
}

# Lambda Throttle Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = toset(var.aws_lambda_function_name)

  alarm_name          = "${each.value}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Lambda function ${each.value} is being throttled"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }

  treat_missing_data = "notBreaching"
}

# Kinesis Iterator Age Alarms
resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  count = var.aws_kinesis_stream_name != "" ? 1 : 0

  alarm_name          = "${var.aws_kinesis_stream_name}-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Maximum"
  threshold           = 60000 # 60 Seconds
  alarm_description   = "Kinesis stream ${var.aws_kinesis_stream_name} iterator age is too high"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    StreamName = var.aws_kinesis_stream_name
  }

  treat_missing_data = "notBreaching"
}

# Step Functions Failed Executions Alarms
resource "aws_cloudwatch_metric_alarm" "step_function_failures" {

  alarm_name          = "${var.project_name}-${var.environment}-step-function-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Step Functions executions are failing"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    StateMachineArn = var.step_function_arn
  }

  treat_missing_data = "notBreaching"

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metrics"
        properties = {
          metrics = [
            for fn in var.aws_lambda_function_name : [
              "AWS/Lambda", "Invocations", { stat = "Sum", lable = fn }
            ]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Lambda Invocations"
        }
      },
      {
        type = "metrics"
        properties = {
          metrics = [
            for fn in var.aws_lambda_function_name : [
              "AWS/Lambda", "Errors", { stat = "Sum", label = fn }
            ]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Lambda Errors"
        }
      },
      {
        type = "metrics"
        properties = {
          metrics = var.aws_kinesis_stream_name != "" ? [
            ["AWS/Kinesis", "IncomingRecords", { stat = "Sum" }],
            [".", "IncomingBytes", { stat = "Sum" }]
          ] : []
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Kinesis Metrics"
        }
      }
    ]
  })
}

data "aws_region" "current" {}

output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}
output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}