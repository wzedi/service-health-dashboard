#! /bin/sh

AWS_CLI="${AWS_CLI:-aws}"

if [ ! -z "$AWS_ROLE_ARN" ]
then
  resp=$($AWS_CLI sts assume-role --role-arn $AWS_ROLE_ARN --role-session-name ServiceHealthDashboard --duration-seconds 3600 --external-id serviceHealthDashboard)

  echo AWS_SECRET_ACCESS_KEY=$(echo $resp | jq -r '.Credentials.SecretAccessKey')
  echo AWS_ACCESS_KEY_ID=$(echo $resp | jq -r '.Credentials.AccessKeyId')
  echo AWS_SESSION_TOKEN=$(echo $resp | jq -r '.Credentials.SessionToken')
  echo AWS_EXPIRATION=$(echo $resp | jq -r '.Credentials.Expiration')
  echo AWS_SECURITY_TOKEN=$(echo $resp | jq -r '.Credentials.SessionToken')
fi