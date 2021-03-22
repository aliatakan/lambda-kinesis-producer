variable profile {}
variable region {}
variable csv_bucket_name {}
variable kinesis_stream_name {}

locals {
  source_dir = "../${path.module}/python/producer"
}

data "archive_file" "producer_zip" {
    type        = "zip"
    source_file  = "${local.source_dir}/producer.py"
    output_path = "${local.source_dir}/producer.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_execute_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
}

resource "aws_iam_role_policy_attachment" "lambda_kinesis_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
}

resource "aws_lambda_function" "producer_function" {
  filename         = "${local.source_dir}/producer.zip"
  function_name    = "python_producer"
  role             = aws_iam_role.lambda_role.arn
  handler          = "producer.lambda_handler"
  source_code_hash = data.archive_file.producer_zip.output_base64sha256

  runtime = "python3.8"
  timeout = 300
  memory_size = 512

  environment {
    variables = {
      stream_name         = var.kinesis_stream_name
      stream_shard_count  = 1
    }
  }

  depends_on = [
    data.archive_file.producer_zip
  ]

}

resource "aws_lambda_permission" "producer_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer_function.function_name
  principal     = "s3.amazonaws.com"
}

resource "aws_s3_bucket" "csv_bucket" {
  bucket = var.csv_bucket_name
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Desc = "S3 bucket for csv files"
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.csv_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.producer_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [
    aws_lambda_permission.producer_lambda_permission
  ]
}

resource "aws_kinesis_stream" "data_stream" {
  name             = var.kinesis_stream_name
  shard_count      = 1
  retention_period = 24

  tags = {
    Environment = "test"
  }
}