terraform {
  backend "s3" {
    region         = "ap-southeast-2"
    bucket         = "service-health-dashboard-tfstate"
    key            = "service-health-dashboard"
    encrypt        = true
    dynamodb_table = "dynamodb-terraform-state-lock"
  }
}

provider "aws" {
  version = "~> 2.0"
}

provider "archive" {}

data "aws_caller_identity" "current" {
}

data "aws_region" "current" {
}

resource "aws_s3_bucket" "service_status_bucket" {
  bucket = "status.example.com"
  acl    = "public-read"

  website {
    index_document = "index.html"
  }
}

resource "aws_secretsmanager_secret" "service_health_dashboard_configuration" {
  name = "ServiceHealthDashoardConfiguration"
}

resource "aws_secretsmanager_secret_version" "service_health_dashboard_configuration_default" {
  secret_id     = aws_secretsmanager_secret.service_health_dashboard_configuration.id
  secret_string = " "
}

resource "aws_iam_policy" "service_status_policy" {
  name        = "service_status_policy"
  path        = "/"
  description = "Service status lambda function policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/ServiceHealthDashboard:*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": [
                "arn:aws:s3:::status.example.com/status.json"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHealthChecks",
                "route53:GetHealthCheck",
                "route53:GetHealthCheckStatus"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
              "secretsmanager:PutSecretValue",
              "secretsmanager:GetSecretValue"
            ],
            "Resource": "${aws_secretsmanager_secret.service_health_dashboard_configuration.arn}"
        }
    ]
}
EOF
}

resource "aws_iam_role" "service_status_role" {
  name = "service_status_role"

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

resource "aws_iam_role_policy_attachment" "service_status_policy_attachment" {
  role       = aws_iam_role.service_status_role.name
  policy_arn = aws_iam_policy.service_status_policy.arn
}

data "template_file" "status" {
  template = "${file("${path.module}/status.js")}"
  vars = {
    secretId = aws_secretsmanager_secret.service_health_dashboard_configuration.arn
  }
}

data "archive_file" "status" {
  type        = "zip"
  output_path = "${path.module}/status.zip"

  source {
    content  = "${data.template_file.status.rendered}"
    filename = "status.js"
  }
}

resource "aws_lambda_function" "service_status_function" {
  filename      = data.archive_file.status.output_path
  function_name = "ServiceHealthDashboard"
  role          = aws_iam_role.service_status_role.arn
  handler       = "status.handler"
  timeout       = 60

  source_code_hash = filebase64sha256(data.archive_file.status.output_path)

  runtime = "nodejs10.x"

  environment {
    variables = {
      CHANNEL    = "#support"
      PATH       = "/services/T0K3RA4RH/BGJSTNUKU/7d6dkeRXbJBHHhYV21obOj2X"
      USER_NAME  = "Service Health Dashboard"
      ICON_EMOJI = ":warning:"
    }
  }
}

resource "aws_cloudwatch_event_target" "service_status_event_target" {
  rule      = aws_cloudwatch_event_rule.service_status_event_rule.name
  arn       = aws_lambda_function.service_status_function.arn
}

resource "aws_cloudwatch_event_rule" "service_status_event_rule" {
  name        = "ServiceHealthEventRule"
  description = "Capture Route53 health status"
  schedule_expression = "cron(* * * * ? *)"
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.service_status_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.service_status_event_rule.arn
}

output "status_bucket_url" {
  value = aws_s3_bucket.service_status_bucket.bucket_domain_name 
}
