#! /bin/sh -e
export $(./scripts/assume-role.sh)

BASE_DIR=$(pwd)

cd $BASE_DIR/provision
terraform init
terraform plan # -auto-approve

cd $BASE_DIR/src
aws s3 sync . s3://status.example.com --acl public-read
