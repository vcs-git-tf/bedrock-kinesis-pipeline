variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "data_lake_bucket_arn" {
  description = "ARN of data lake s3 bucket"
  type        = string
}

variable "shard_count" {
  description = "Number of shards for Kinesis stream"
  type        = number
  default     = 1
}

#KINESIS DATA STREAM
resource "aws_kinesis_stream" "main" {
  name             = "${var.project_name}-${var.environment}-stream"
  shard_count      = var.shard_count
  retention_period = 8 #hours

  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"
}

#KINESIS FIREHOSE IAM ROLE
resource "aws_iam_role" "firehose" {
  name = "${var.project_name}-${var.environment}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts.AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "s3-access"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          var.data_lake_bucket_arn,
          "${var.data_lake_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.main.arn
      }
    ]
  })
}

#KINESIS FIREHOSE DELIVERY STREAM
resource "aws_kinesis_firehose_delivery_stream" "main" {
  name        = "${var.project_name}-${var.environment}-firehose"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.main.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = var.data_lake_bucket_arn
    prefix     = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = 5   #MB
    buffering_interval = 300 #seconds (5-minutes)

    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = "S3Delivery"
    }

    # Data format conversion (optional - Parquet for better analytics performance)
    data_format_conversion_configuration {
      enabled = true

      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }

      schema_configuration {
        database_name = var.glue_database_name
        table_name    = aws_glue_catalog_table.firehose_schema.name
        role_arn      = aws_iam_role.firehose.arn
      }
    }
  }
}

variable "glue_database_name" {
  description = "Glue database name for schema"
  type        = string
}

#GLUE TABLE FOR FIREHOSE SCHEMA
resource "aws_glue_catalog_table" "firehose_schema" {
  name          = "${var.project_name}-${var.environment}_raw_events"
  database_name = var.glue_database_name

  storage_descriptor {
    columns {
      name = "event_id"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "timestamp"
    }
    columns {
      name = "event_type"
      type = "string"
    }
    columns {
      name = "payload"
      type = "string"
    }

    location      = "s3://${split(":", var.data_lake_bucket_arn)[5]}/raw/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }
  }
}

#CLOUDWATCH LOG GROUP FOR FIREHOSE
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.project_name}-${var.environment}"
  retention_in_days = 5
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

output "stream_name" {
  value = aws_kinesis_stream.main.name
}

output "stream_arn" {
  value = aws_kinesis_stream.main.arn
}

output "firehose_name" {
  value = aws_kinesis_firehose_delivery_stream.main.name
}

output "firehose_arn" {
  value = aws_kinesis_firehose_delivery_stream.main.arn
}