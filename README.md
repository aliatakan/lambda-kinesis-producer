### Prerequisite
- AWS Account
- AWS CLI
- Terraform

At the end of the article we will have a producer Lambda functions with Python. The producer will send the data to the Amazon Kinesis Data stream.

We will use Terraform for all those processes. It means, we will create IAM roles, necessary S3 bucket and the Kinesis Data stream.

I create a terraform folder to store the terraform files. I also create a python folder for the producer and consumer functions.

- kinesis-lambda-producer-consumer/terraform
- kinesis-lambda-producer-consumer/python

## Create `terraform` user
I need an AWS IAM user to create AWS resources via Terraform. I create the `terraform` user. I follow these steps during the user creating.

1. Select the "Programmatic access"
2. Attach "AdministratorAccess" which is in the "Attach existing policies directly option
3. At the endof the process, store the "Access key ID" and "Secret access key" in a secure location. We will use them to create AWS resources by using Terraform.

## Create a new profile for AWS CLI
We create a new profile to use for Terraform and AWS CLI commands.

```
aws configure --profile terraform
AWS Access Key ID [None]: AKIA......
AWS Secret Access Key [None]: je.....
Default region name [None]: us-east-2
Default output format [None]: text
```

## Preparation for Terraform

Create 3 terraform files in `terraform` folder
- main.tf : All resource definitions will be in this file.
- provider.tf : Each Terraform module must declare which providers it requires, so that Terraform can install and use them. 
- variables.tfvars : We store necessary variables in this file. `profile = terraform` and `region = us-east-2` in this example.

Run `terraform init` command to initialise a working directory containing Terraform configuration files. Go to `terraform` folder and run the init command.
```
terraform init

Terraform has been successfully initialized!
```

## Create Local Variable and Archive File

We create a `source_dir` which is for producer folder and use `archive_file` to create source code's zip file.

```
locals {
  source_dir = "../${path.module}/python/producer"
}

data "archive_file" "producer_zip" {
    type        = "zip"
    source_file  = "${local.source_dir}/producer.py"
    output_path = "${local.source_dir}/producer.zip"
}
```

## Create IAM Role and Attach Policies

Lambda functions need IAM Roles to carry out some of their tasks. For example, they need `AWSLambdaExecute` policy to Put, Get access to S3 and full access to CloudWatch Logs. As we read and write to Kinesis, we add `AmazonKinesisFullAccess`.

```
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
```

## Create the Producer Lambda Function

We have add the Producer's source code zip file into the S3 bucket. Now, we can create the LambdaFunction

```
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
```

## Create a S3 Bucket for Triggering

We create an S3 bucket to store the csv files. When we add a csv into the `csv-example-data-bucket`, Lambda function is going to be triggered via `aws_s3_bucket_notification` resource.

```
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
```

## Create a Kinesis Data Stream

We create a Kinesis Data Stream with 1 shard and 24 hours retention period which is length of time data records are accessible after they are added to the stream. Despite the default value is 24 hours, I just added to explain what it is.

```
resource "aws_kinesis_stream" "data_stream" {
  name             = var.kinesis_stream_name
  shard_count      = 1
  retention_period = 24

  tags = {
    Environment = "test"
  }
}
```

## Run `terraform apply` to create all resources

Run `terraform apply` to create the all the resources. You can first run `terraform plan` to see which resources will be created. Go to `terraform` folder and run the apply command.

```
terraform apply -var-file="variables.tfvars" -auto-approve

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

## Test!

I use http://eforexcel.com/wp/downloads-18-sample-csv-files-data-sets-for-testing-sales/ sales records. You can download 50.000 records zip file, unzip it and then upload the zip file into the `csv-example-data-bucket` bucket. You need to remove the space characters from the name of the file. 

When you do that, you will see this message in the CloudWatch logs.

```
Total Records sent to Kinesis: 50000
```