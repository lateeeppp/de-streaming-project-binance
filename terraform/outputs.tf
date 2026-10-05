output "kinesis_stream_name" {
  description = "Nama Kinesis Stream yang berhasil dibuat"
  value       = aws_kinesis_stream.crypto_stream.name
}

output "kinesis_stream_arn" {
  description = "Amazon Resource Name (ARN) dari Kinesis Stream"
  value       = aws_kinesis_stream.crypto_stream.arn
}

output "dynamodb_table_name" {
  description = "Nama DynamoDB Table untuk whale alerts"
  value       = aws_dynamodb_table.whale_alerts.name
}

output "lambda_function_name" {
  description = "Nama AWS Lambda function untuk whale detection"
  value       = aws_lambda_function.whale_detector.function_name
}

output "s3_lakehouse_bucket_name" {
  description = "Nama S3 Bucket untuk Bronze Data Lake"
  value       = aws_s3_bucket.lakehouse_bucket.bucket
}

output "glue_database_name" {
  description = "Nama database AWS Glue Data Catalog"
  value       = aws_glue_catalog_database.crypto_lakehouse_db.name
}

output "firehose_delivery_stream_name" {
  description = "Nama Amazon Data Firehose Delivery Stream"
  value       = aws_kinesis_firehose_delivery_stream.crypto_firehose.name
}

output "athena_workgroup_name" {
  description = "Nama Athena Workgroup untuk dbt dan query analytics"
  value       = aws_athena_workgroup.lakehouse_workgroup.name
}

output "athena_query_results_s3_uri" {
  description = "S3 URI untuk menampung hasil query Athena"
  value       = "s3://${aws_s3_bucket.lakehouse_bucket.bucket}/athena-results/"
}