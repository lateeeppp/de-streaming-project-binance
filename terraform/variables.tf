variable "aws_region" {
  description = "Region AWS yang digunakan untuk mendeploy resource"
  type        = string
  default     = "ap-southeast-3"
}

variable "kinesis_stream_name" {
  description = "Nama stream Kinesis untuk menampung data transaksi kripto"
  type        = string
  default     = "crypto-trades-stream"
}

variable "kinesis_shard_count" {
  description = "Jumlah shard untuk Kinesis stream (1 shard = 1000 records/sec)"
  type        = number
  default     = 1
}

variable "aws_profile" {
  description = "Profil AWS CLI yang digunakan untuk autentikasi"
  type        = string
  default     = "de-streaming-project-binance"
}