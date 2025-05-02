terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.97.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

#
resource "aws_cloudwatch_log_group" "example" {
  name              = "/example/log-group"
  retention_in_days = 7
}


resource "aws_s3_bucket" "log_storage" {
  bucket = "<s3 bucket name here>"
}

resource "aws_iam_role" "firehose_to_s3_role" {
  name = "firehose_delivery_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "firehose.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "cwlogs_to_firehose_role" {
  name = "cwlogs_to_firehose_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "logs.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "cwlogs_to_s3" {
  name        = "cwlogs_to_s3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_to_s3_role.arn
    bucket_arn         = aws_s3_bucket.log_storage.arn
    buffering_size     = 1
    buffering_interval = 60
    compression_format = "GZIP"
  }
}

resource "aws_iam_role_policy" "cwlogs_to_firehose_policy" {
  name = "cwlogs_to_firehose_policy"
  role = aws_iam_role.cwlogs_to_firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "firehose:PutRecord",
        Resource = aws_kinesis_firehose_delivery_stream.cwlogs_to_s3.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_to_s3_policy" {
  name = "firehose_delivery_policy"
  role = aws_iam_role.firehose_to_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ],
        Resource = "${aws_s3_bucket.log_storage.arn}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "cwlogs_to_firehose" {
  name            = "cwlogs_to_firehose"
  log_group_name  = aws_cloudwatch_log_group.example.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.cwlogs_to_s3.arn
  role_arn        = aws_iam_role.cwlogs_to_firehose_role.arn
}

resource "aws_cloudwatch_log_stream" "sample_log_stream" {
  name           = "sample_log_stream"
  log_group_name = aws_cloudwatch_log_group.example.name
}