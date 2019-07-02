terraform {
  backend "s3" {
    region         = "ap-southeast-2"
    bucket         = "codebuild-tfstate"
    encrypt        = true
    dynamodb_table = "dynamodb-terraform-state-lock"
  }
}

provider "aws" {
  version = "~> 2.0"
}

provider "archive" {}

variable "project_name" {
  type = string
}

variable "project_description" {
  default = ""
}

variable "build_image" {
  description = "What Docker image to run in"
  default     = "docker.io/hashicorp/terraform:0.12.1"
}

variable "build_timeout" {
  description = "The build timeout in minutes from 5 to 480"
  default     = 30
}

variable "compute_type" {
  description = "The build compute type, one of BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM or BUILD_GENERAL1_LARGE. BUILD_GENERAL1_SMALL is only valid if type is set to LINUX_CONTAINER"
  default     = "BUILD_GENERAL1_SMALL"
}

variable "source_type" {
  description = "The type of souce code repository. One of CODECOMMIT, CODEPIPELINE, GITHUB, GITHUB_ENTERPRISE, BITBUCKET, S3 or NO_SOURCE."
  default     = "GITHUB"
}

variable "source_location" {
  description = "The source code location"
}

variable "buildspec_location" {
  description = "The relative path to the buildspec file from the project root"
  default     = "buildspec.yml"
}

variable "environment" {
  description = "The deployment environment, e.g. production, development"
}

variable "continue_delivery_role_arn" {
  description = "The ARN of the ContinueDelivery role to be assumed by build scripts during deployment"
}

variable "slack_webhook_path" {
  description = "The Slack webhook path to send build notifications to"
  default     = "/services/T0K3RA4RH/B92BUA7GX/indnn7WhOEvBwrKcS4DdSKvd"
}

variable "slack_channel" {
  description = "The Slack channel to send build notifications to"
  default     = "#mapper-notifications"
}

data "aws_caller_identity" "current" {
}

data "aws_region" "current" {
}

#create iam role for codebuild
resource "aws_iam_policy" "cloudwatch_logs_policy" {
  name        = "CodeBuildCloudWatchLogsPolicy-${var.project_name}"
  path        = "/"
  description = "Policy used in trust relationship with CodeBuild"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Resource": [
                "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.project_name}CodeBuild",
                "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.project_name}CodeBuild:*",
                "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}:log-stream:*"
            ],
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "assume_role_policy" {
  name        = "CodeBuildAssumeRolePolicy-${var.project_name}"
  path        = "/"
  description = "Policy used in trust relationship with CodeBuild"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CodeBuildAssumeRolePermissions",
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": [
                "${var.continue_delivery_role_arn}"
            ]
        }
    ]
}
EOF
}


resource "aws_iam_role" "service_role" {
name = "CodeBuildServiceRole-${var.project_name}"

assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "logs_policy_attachment" {
  role = aws_iam_role.service_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
}

resource "aws_iam_role_policy_attachment" "assume_role_policy_attachment" {
  role = aws_iam_role.service_role.name
  policy_arn = aws_iam_policy.assume_role_policy.arn
}

#create codebuild project - env vars - HOSTED_ZONE_NAME, ENVIRONMENT, CERTIFICATE_ARN, CF_IAM_ROLE_ARN

resource "aws_codebuild_project" "codebuild_project" {
  name = var.project_name
  description = var.project_description
  build_timeout = var.build_timeout
  service_role = aws_iam_role.service_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = var.compute_type
    image = var.build_image
    type = "LINUX_CONTAINER"

    environment_variable {
      name = "AWS_ROLE_ARN"
      value = var.continue_delivery_role_arn
    }
  }

  source {
    type = var.source_type
    location = var.source_location
    buildspec = var.buildspec_location
    git_clone_depth = 1

    auth {
      type = "OAUTH"
    }
  }
}

resource "aws_codebuild_webhook" "codebuild_webhook" {
  project_name = "${aws_codebuild_project.codebuild_project.name}"
}

resource "aws_cloudwatch_event_target" "codebuild_event_target" {
  rule      = aws_cloudwatch_event_rule.codebuild_event_rule.name
  arn       = "${aws_lambda_function.codebuild_notifier.arn}"
}

resource "aws_cloudwatch_event_rule" "codebuild_event_rule" {
  name        = "CodeBuildEventRule-${var.project_name}"
  description = "Capture CodeBuild event changes"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.codebuild"
  ],
  "detail-type": [
    "CodeBuild Build State Change"
  ]
}
PATTERN
}

resource "aws_iam_role" "codebuild_notifier_role" {
  name = "CodeBuildNotifierRole-${var.project_name}"

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

resource "aws_iam_role_policy_attachment" "notifier_policy_attachment" {
  role       = "${aws_iam_role.codebuild_notifier_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "notify" {
  type        = "zip"
  source_file = "${path.module}/notify.js"
  output_path = "${path.module}/notify.zip"
}

resource "aws_lambda_function" "codebuild_notifier" {
  filename         = "${data.archive_file.notify.output_path}"
  function_name    = "codebuild_notifier_${var.project_name}"
  role             = "${aws_iam_role.codebuild_notifier_role.arn}"
  handler          = "notify.handler"
  source_code_hash = "${filebase64sha256(data.archive_file.notify.output_path)}"
  runtime          = "nodejs10.x"

  environment {
    variables = {
      CHANNEL   = var.slack_channel
      PATH      = var.slack_webhook_path
      USER_NAME = "CodeBuild"
    }
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.codebuild_notifier.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.codebuild_event_rule.arn}"
}

output "codebuild_role_arn" {
  value = aws_iam_role.service_role.arn
}
