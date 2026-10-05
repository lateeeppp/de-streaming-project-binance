terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Ambil informasi AWS Account ID saat ini secara dinamis
data "aws_caller_identity" "current" {}

# Resource Kinesis Data Streams (1 Shard)
resource "aws_kinesis_stream" "crypto_stream" {
  name             = var.kinesis_stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = 24 # Masa simpan data di buffer: 24 jam

  # Metrik CloudWatch untuk memantau performa streaming
  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords"
  ]

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# 1. Tabel DynamoDB untuk Hot Path Alert (<5ms)
resource "aws_dynamodb_table" "whale_alerts" {
  name         = "de-streaming-project-binance-whale-alerts"
  billing_mode = "PAY_PER_REQUEST" # Always-Free tier
  hash_key     = "symbol"
  range_key    = "trade_time_id"   # Diubah ke composite key

  attribute {
    name = "symbol"
    type = "S"
  }

  attribute {
    name = "trade_time_id"
    type = "S"                     # Tipe String
  }

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# 2. Zip file kode Lambda otomatis via Terraform
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/whale_detector.py"
  output_path = "${path.module}/whale_detector.zip"
}

# 3. IAM Role untuk Lambda Execution
resource "aws_iam_role" "lambda_exec_role" {
  name = "de-streaming-project-binance-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 4. IAM Policy: Izin baca Kinesis, tulis DynamoDB, dan CloudWatch Logs
resource "aws_iam_policy" "lambda_policy" {
  name        = "de-streaming-project-binance-lambda-policy"
  description = "Policy untuk Lambda membaca Kinesis dan menulis ke DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.crypto_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.whale_alerts.arn
      }
    ]
  })
}

# Hubungkan Policy ke Role
resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# 5. AWS Lambda Function
resource "aws_lambda_function" "whale_detector" {
  function_name    = "de-streaming-project-binance-whale-detector"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "whale_detector.lambda_handler"
  runtime          = "python3.11"
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.whale_alerts.name
      TELEGRAM_BOT_TOKEN  = var.telegram_bot_token
      TELEGRAM_CHAT_ID    = var.telegram_chat_id
      WHALE_THRESHOLD_USD = tostring(var.whale_threshold_usd)
    }
  }

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# 6. Kinesis Event Source Mapping (Memicu Lambda secara otomatis per batch)
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn                   = aws_kinesis_stream.crypto_stream.arn
  function_name                      = aws_lambda_function.whale_detector.arn
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 3
}

# ==============================================================================
# MILESTONE 3: COLD PATH STORAGE (S3 BRONZE LAKEHOUSE + FIREHOSE INGESTION)
# ==============================================================================

# 7. Amazon S3 Bucket: Bronze Raw Data Lakehouse
resource "aws_s3_bucket" "lakehouse_bucket" {
  bucket        = "de-streaming-project-binance-bucket"
  force_destroy = true # Memudahkan teardown bersih saat destroy untuk portofolio

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "lakehouse_public_block" {
  bucket = aws_s3_bucket.lakehouse_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lakehouse_encryption" {
  bucket = aws_s3_bucket.lakehouse_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 8. AWS Glue Data Catalog Database & Table (Cetak Biru Skema Data Contract)
resource "aws_glue_catalog_database" "crypto_lakehouse_db" {
  name        = "de_streaming_project_binance_db"
  description = "Database katalog skema untuk Crypto Streaming Lakehouse"
}

resource "aws_glue_catalog_table" "bronze_trades" {
  name          = "bronze_trades"
  database_name = aws_glue_catalog_database.crypto_lakehouse_db.name
  description   = "Skema tabel mentah Bronze untuk format conversion Amazon Data Firehose"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lakehouse_bucket.bucket}/bronze/trades/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "trade_id"
      type = "string"
    }
    columns {
      name = "symbol"
      type = "string"
    }
    columns {
      name = "price"
      type = "double"
    }
    columns {
      name = "quantity"
      type = "double"
    }
    columns {
      name = "trade_value_usd"
      type = "double"
    }
    columns {
      name = "buyer_is_maker"
      type = "boolean"
    }
    columns {
      name = "trade_time_ms"
      type = "bigint"
    }
    columns {
      name = "event_time_ms"
      type = "bigint"
    }
  }
}

# 9. CloudWatch Log Group & Stream untuk Amazon Data Firehose
resource "aws_cloudwatch_log_group" "firehose_log_group" {
  name              = "/aws/kinesisfirehose/de-streaming-project-binance-firehose"
  retention_in_days = 7

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_stream" "firehose_log_stream" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose_log_group.name
}

# 10. IAM Role & Policy untuk Amazon Data Firehose
resource "aws_iam_role" "firehose_role" {
  name = "de-streaming-project-binance-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_policy" "firehose_policy" {
  name        = "de-streaming-project-binance-firehose-policy"
  description = "Izin Firehose untuk membaca Kinesis, memeriksa skema Glue, dan menulis ke S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Baca dari Kinesis Stream
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.crypto_stream.arn
      },
      # Tulis ke S3 Bucket Bronze
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
          aws_s3_bucket.lakehouse_bucket.arn,
          "${aws_s3_bucket.lakehouse_bucket.arn}/*"
        ]
      },
      # Akses Skema Glue Data Catalog untuk konversi format Parquet
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetTableVersion",
          "glue:GetTableVersions",
          "glue:GetDatabase"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          aws_glue_catalog_database.crypto_lakehouse_db.arn,
          aws_glue_catalog_table.bronze_trades.arn
        ]
      },
      # Menulis Error & Delivery Logs ke CloudWatch
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.firehose_log_group.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "firehose_attach" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_policy.arn
}

# 11. Amazon Data Firehose Delivery Stream (Kinesis -> Parquet -> S3)
resource "aws_kinesis_firehose_delivery_stream" "crypto_firehose" {
  name        = "de-streaming-project-binance-firehose"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.crypto_stream.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.lakehouse_bucket.arn

    prefix              = "bronze/trades/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "bronze/errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"

    # Saat konversi format Parquet aktif, AWS mensyaratkan buffer_size minimal 64 MB.
    # Namun timer buffer_interval = 60 detik menjamin data di-flush setiap 60 detik!
    buffering_size     = 64
    buffering_interval = 60

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_log_group.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_log_stream.name
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = "SNAPPY"
          }
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_database.crypto_lakehouse_db.name
        table_name    = aws_glue_catalog_table.bronze_trades.name
        role_arn      = aws_iam_role.firehose_role.arn
      }
    }
  }

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# ==============================================================================
# MILESTONE 4: DATA MODELING LAKEHOUSE (AMAZON ATHENA WORKGROUP)
# ==============================================================================

# 12. Amazon Athena Workgroup untuk dbt & Analytics
resource "aws_athena_workgroup" "lakehouse_workgroup" {
  name          = "de-streaming-project-binance-workgroup"
  state         = "ENABLED"
  force_destroy = true # Memudahkan teardown bersih saat destroy

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lakehouse_bucket.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = {
    Project     = "de-streaming"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}