output "kinesis_stream_name" {
  description = "Nama Kinesis Stream yang berhasil dibuat"
  value       = aws_kinesis_stream.crypto_stream.name
}

output "kinesis_stream_arn" {
  description = "Amazon Resource Name (ARN) dari Kinesis Stream"
  value       = aws_kinesis_stream.crypto_stream.arn
}