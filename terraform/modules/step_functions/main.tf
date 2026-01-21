variable "state_machine_name" {
  description = "Name of the Step Functions state machine"
  type        = string
}

variable "lambda_arn" {
  description = "ARN of the Lambda function to invoke"
  type        = string
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = var.state_machine_name
  role_arn = aws_iam_role.step_function_role.arn

  definition = jsonencode({
    Comment = "Data processing workflow"
    StartAt = "ProcessData"
    States = {
      ProcessData = {
        Type     = "Task"
        Resource = var.lambda_arn
        End      = true
      }
    }
  })
}

resource "aws_iam_role" "step_function_role" {
  name = "${var.state_machine_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "step_function_policy" {
  name = "step_function_policy"
  role = aws_iam_role.step_function_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          var.lambda_arn
        ]
      }
    ]
  })
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.sfn_state_machine.arn
}