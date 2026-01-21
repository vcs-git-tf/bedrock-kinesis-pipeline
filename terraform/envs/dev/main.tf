terraform {
  backend "s3" {
    bucket         = "data-paltform-terraform-state-194191748922"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "data-paltform-terraform-locks"
    encrypt        = true
  }
}

terraform {
  required_providers {
    aws = {
      source   = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  project_name = "data_platform"
  environment  = "dev"
}

module "vpc" {
  source       = "../../modules/vpc"
  environment  = local.environment
  project_name = local.project_name
  vpc_cidr     = "10.0.0.0/28"
}

module "data_lake" {
  source       = "../../modules/data-lake"
  environment  = local.environment
  project_name = local.project_name
}

module "kinesis" {
  source               = "../../modules/kinesis"
  environment          = local.environment
  project_name         = local.project_name
  data_lake_bucket_arn = module.data_lake.bucket_arn
  glue_database_name   = module.data_lake.glue_database_name
}

module "bedrock_processor" {
  source        = "../../modules/lambda"
  function_name = "${local.project_name}-${local.environment}-bedrock-processor"
  source_dir    = "../../../src/lambda/bedrock_processor"
  environment_variables = {
    DATA_LAKE_BUCKET = module.data_lake.bucket_name
  }
}

module "data_processing_workflow" {
  source             = "../../modules/step_functions"
  state_machine_name = "${local.project_name}-${local.environment}-workflow"
  lambda_arn         = module.bedrock_processor.function_arn
}

module "spice_scheduler" {
  source              = "../../modules/eventbridge_scheduler"
  schedule_name       = "${local.project_name}-${local.environment}-spice-schedule"
  schedule_expression = "rate(4 hour)"
  target_arn          = module.data_processing_workflow.state_machine_arn
}

module "api_key_secret" {
  source       = "../../modules/secrets"
  secret_name  = "/repo/github/${local.project_name}/${local.environment}/api-key"
  secret_value = var.api_key_secret
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name = local.project_name
  environment  = local.environment
  alarm_email  = "aws-root-ananke@thefactor.org"

  aws_lambda_function_name = [
    module.bedrock_processor.function_name
  ]

  aws_kinesis_stream_name = module.kinesis.stream_name
  step_function_arn       = module.data_processing_workflow.state_machine_arn
}

module "security" {
  source = "../../modules/security"

  project_name        = local.project_name
  environment         = local.environment
  alarm_sns_topic_arn = module.monitoring.sns_topic_arn
  budget_amount       = 5 # $5.00/month budget for dev
}

#Outputs
output "bucket_name" {
  description = "Name of the data lake S3 bucket"
  value       = module.data_lake.bucket_name  # Adjust resource name if different
}

output "aws_cloudwatch_dashboard_url" {
  value = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${module.monitoring.dashboard_name}"
}

output "data_lake_bucket" {
  value = module.data_lake.bucket_name
}

output "aws_kinesis_stream" {
  value = module.kinesis.stream_name
}

output "step_function_arn" {
  value = module.data_processing_workflow.state_machine_arn
}

data "aws_region" "current" {}