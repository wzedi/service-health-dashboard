#! /bin/bash -e

# Requires AWS CLI and jq to be installed.


AWS_CLI="${AWS_CLI:-aws}"
REGION="${AWS_REGION:-ap-southeast-2}"

BUCKET_NAME=codebuild-tfstate
LOCK_TABLE_NAME=dynamodb-terraform-state-lock

PROJECT_NAME=$1
ACTION="${2:-apply}"
ENVIRONMENT="${3:-production}"

if [[ "$ACTION" == "apply" ]]
then
  # Create TF state bucket
  echo Checking if bucket already exists && ${AWS_CLI} s3 ls --region $REGION | grep "\<$BUCKET_NAME\>" 2>&1 > /dev/null || \
    (echo Creating bucket && 
    ${AWS_CLI} s3 mb s3://$BUCKET_NAME --region $REGION)

  # Create TF lock table
  echo Checking if DynamoDB lock table already exists && \
    ${AWS_CLI} dynamodb list-tables --region $REGION | grep "$LOCK_TABLENAME" 2>&1 > /dev/null || \
    (echo Creating lock table && \
      ${AWS_CLI} dynamodb create-table \
        --table-name "$LOCK_TABLENAME" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST)
fi

terraform init \
  -input=false\
	-backend-config="key=$PROJECT_NAME-$ENVIRONMENT"

terraform $ACTION \
  -var buildspec_location=".codebuild/buildspec.yml" \
  -var continue_delivery_role_arn="arn:aws:iam::961723680371:role/ContinueDelivery" \
  -var environment=${ENVIRONMENT} \
  -var project_name=${PROJECT_NAME} \
  -var source_location="https://github.com/wzedi/service-health-dashboard.git" \
  -auto-approve


if [[ "$ACTION" == "destroy" ]]
then
  # Delete TF lock table
  # echo Checking if DynamoDB lock table already exists && \
  #   ${AWS_CLI} dynamodb list-tables --region $REGION | grep "$LOCK_TABLENAME" 2>&1 > /dev/null && \
  #   ${AWS_CLI} dynamodb delete-table --table-name "$LOCK_TABLENAME"

  # Delete TF state bucket
  #echo Checking if bucket already exists && ${AWS_CLI} s3 ls --region $REGION | grep "\<$BUCKET_NAME\>" 2>&1 > /dev/null && \
  #  echo Destroying bucket && 
  #  ${AWS_CLI} s3 rb s3://$BUCKET_NAME --region $REGION --force
else
  CODEBUILD_ROLE_ARN=$(terraform output --json | jq '.codebuild_role_arn.value' | tr -d '"')
  echo "*************************************************"
  echo "**** Update the ContinueDelivery role assume role"
  echo "**** policy in the deployment target account to"
  echo "**** allow AWS Principal for ARN"
  echo "**** " $CODEBUILD_ROLE_ARN 
  echo "*************************************************"
fi
