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
  region = var.aws_region
  profile = var.aws_profile
}

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
  name         = "whale_alerts"
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
  name = "crypto_whale_detector_lambda_role"

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
  name        = "crypto_whale_detector_policy"
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
  function_name    = "whale_detector"
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