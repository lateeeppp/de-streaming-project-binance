terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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