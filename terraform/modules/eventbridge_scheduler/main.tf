variable "schedule_name" {
  description = "Name of the EventBridge Scheduler"
  type        = string
}

variable "schedule_expression" {
  description = "Schedule expression (e.g. - 'rate(1 hour)' or 'cron(0 12   ?*)')"
  type        = string
}

variable "target_arn" {
  description = "ARN of the target to invoke (e.g. - Step Functions state machine)"
  type        = string
}

resource "aws_scheduler_schedule" "spice_schedule" {
  name       = var.schedule_name
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.schedule_expression

  target {
    arn      = var.target_arn
    role_arn = aws_iam_role.scheduler_role.arn
  }
}

resource "aws_iam_role" "scheduler_role" {
  name = "${var.schedule_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_policy" {
  name = "scheduler_policy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states.StartExecution"
        ]
        Resource = [
          var.target_arn
        ]
      }
    ]
  })
}

output "schdule_arn" {
  value = aws_scheduler_schedule.spice_schedule.arn
}