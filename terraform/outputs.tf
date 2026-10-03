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