terraform {
  backend "s3" {
    bucket = "my-state"
    key    = "sample-twitter/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
  default     = "172.16.248.0/21"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

// VPC

resource "aws_vpc" "sample_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "sample-vpc"
  }
}

// Subnets

resource "aws_subnet" "private_lab" {
  count             = 2
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 2, count.index)
  vpc_id            = aws_vpc.sample_vpc.id
  tags = {
    Name = "Private-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

resource "aws_subnet" "public_lab" {
  count                   = 2
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 2, count.index + 2)
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.sample_vpc.id
  tags = {
    Name = "Public-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

// Internet Gateway

resource "aws_internet_gateway" "igw_lab" {
  vpc_id = aws_vpc.sample_vpc.id

  tags = {
    Name = "Internet Gateway lab"
  }
}

// NAT Gateway

resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = element(aws_eip.nat.*.id, count.index)
  subnet_id     = element(aws_subnet.public_lab.*.id, count.index)

  tags = {
    Name = "NAT Gateway lab ${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

// Nat Gateway Elastic IP

resource "aws_eip" "nat" {
  count = 2
  vpc   = true
}

// Public Route table

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.sample_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_lab.id
  }

  tags = {
    Name = "public-route"
  }
}

//Public Route table association 

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = element(aws_subnet.public_lab.*.id, count.index)
  route_table_id = aws_route_table.public_route.id
}

//Private Route table

resource "aws_route_table" "private_route" {
  count  = 2
  vpc_id = aws_vpc.sample_vpc.id
  tags = {
    Name = "private-route"
  }
}

resource "aws_route" "private_route" {
  count                  = 2
  route_table_id         = element(aws_route_table.private_route.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.nat.*.id, count.index)
}

//Private Route table association

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = element(aws_subnet.private_lab.*.id, count.index)
  route_table_id = element(aws_route_table.private_route.*.id, count.index)
}


// lambda

resource "aws_security_group" "sg_for_lambda" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.sample_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_function" "sample_twitter_api" {
  function_name = "sampletwitterapi"
  image_uri     = "${aws_ecr_repository.twitter_api.repository_url}:latest"
  package_type  = "Image"
  timeout       = 10
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      "ACCESS_TOKEN"        = "token"
      "ACCESS_TOKEN_SECRET" = "secret"
      "CONSUMER_KEY"        = "key"
      "CONSUMER_SECRET"     = "secret"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    module.ecr_mirror
  ]

  vpc_config {
    subnet_ids         = aws_subnet.private_lab.*.id
    security_group_ids = [aws_security_group.sg_for_lambda.id]
  }
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name        = "lambda_dynamodb"
  path        = "/"
  description = "IAM policy to write data on dynamodb"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowAccessToOnlyItemsMatchingUserID",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:DescribeTable",
                "dynamodb:BatchGetItem",
                "dynamodb:Query",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": [
                "${aws_dynamodb_table.users.arn}",
                "${aws_dynamodb_table.total_by_hours.arn}",
                "${aws_dynamodb_table.hashtag_by_country.arn}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "twitter_api_lambda"

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
  inline_policy {
    name = "lambda_vpc"
    policy = jsonencode(
      {
        Statement = [
          {
            Action = [
              "ec2:DescribeNetworkInterfaces",
              "ec2:CreateNetworkInterface",
              "ec2:DeleteNetworkInterface",
              "ec2:DescribeInstances",
              "ec2:AttachNetworkInterface",
            ]
            Effect   = "Allow"
            Resource = "*"
          },
        ]
        Version = "2012-10-17"
      }
    )
  }
}


// Dynamodb

resource "aws_dynamodb_table" "users" {
  name         = "users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"


  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "total_by_hours" {
  name         = "total_by_hours"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "created_at"


  attribute {
    name = "created_at"
    type = "S"
  }
}

resource "aws_dynamodb_table" "hashtag_by_country" {
  name         = "hashtag_by_country"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "hashtag"


  attribute {
    name = "hashtag"
    type = "S"
  }
}

// Cloudwatch Event

resource "aws_cloudwatch_event_rule" "every_hour" {
  name                = "every-hour-twitter-api"
  description         = "Fires every hour"
  schedule_expression = "rate(60 minutes)"
}

resource "aws_cloudwatch_event_target" "check_twitter_api_every_hour" {
  rule      = aws_cloudwatch_event_rule.every_hour.name
  target_id = "check_twitter_api"
  arn       = aws_lambda_function.sample_twitter_api.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_twitter_api" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sample_twitter_api.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_hour.arn
}


// ECR

resource "aws_ecr_repository" "twitter_api" {
  name                 = "twitter-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

// ECR upload

module "ecr_mirror" {
  source         = "TechToSpeech/ecr-mirror/aws"
  version        = "0.0.7"
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = data.aws_region.current.name
  docker_source  = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/twitter-api:latest"
  aws_profile    = "default"
  ecr_repo_name  = aws_ecr_repository.twitter_api.name
  ecr_repo_tag   = "latest"
}

