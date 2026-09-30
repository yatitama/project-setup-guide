#!/usr/bin/env bash
# S3 + CloudFront(OAC) + GitHub OIDC用IAMロールを一括作成する。AWS CloudShell等で実行。
# 使い方: 先頭の変数を編集して bash aws-setup.sh
set -euo pipefail
export AWS_PAGER=""

BUCKET="<bucket-name>"          # 例: my-app (全世界で一意)
REGION="ap-northeast-1"
ACCOUNT="<aws-account-id>"      # 12桁
REPO="<owner>/<repo>"           # 例: yatitama/my-app
ROLE="github-actions-$(basename "$REPO")-deploy"
# GitHub OIDCのsub。新しいリポジトリは owner@ID/repo@ID 形式になることがある(guide 5.5参照)。
# 分からなければまず既定形式で作り、失敗したらデバッグステップで実際のsubを確認して更新する。
SUB="repo:$REPO:ref:refs/heads/main"

# 1. S3バケット(非公開)
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 2. CloudFront OAC
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
  "Name=oac-$BUCKET,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
  --query 'OriginAccessControl.Id' --output text)

# 3. CloudFrontディストリビューション(SPA用に403/404をindex.htmlへ)
cat > dist-config.json <<JSON
{
  "CallerReference": "$BUCKET-$(date +%s)",
  "Comment": "$BUCKET",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {"Quantity": 1, "Items": [{"Id": "S3Origin", "DomainName": "$BUCKET.s3.$REGION.amazonaws.com", "S3OriginConfig": {"OriginAccessIdentity": ""}, "OriginAccessControlId": "$OAC_ID"}]},
  "DefaultCacheBehavior": {"TargetOriginId": "S3Origin", "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {"Quantity": 2, "Items": ["HEAD","GET"], "CachedMethods": {"Quantity": 2, "Items": ["HEAD","GET"]}},
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6", "Compress": true},
  "CustomErrorResponses": {"Quantity": 2, "Items": [
    {"ErrorCode": 403, "ResponsePagePath": "/index.html", "ResponseCode": "200", "ErrorCachingMinTTL": 10},
    {"ErrorCode": 404, "ResponsePagePath": "/index.html", "ResponseCode": "200", "ErrorCachingMinTTL": 10}]}
}
JSON
read -r DIST_ID DIST_DOMAIN < <(aws cloudfront create-distribution \
  --distribution-config file://dist-config.json \
  --query 'Distribution.[Id,DomainName]' --output text)

# 4. バケットポリシー(このCloudFrontからのみ許可)
cat > bucket-policy.json <<JSON
{"Version":"2012-10-17","Statement":[{"Sid":"AllowCloudFrontServicePrincipal","Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::$BUCKET/*","Condition":{"ArnLike":{"AWS:SourceArn":"arn:aws:cloudfront::$ACCOUNT:distribution/$DIST_ID"}}}]}
JSON
aws s3api put-bucket-policy --bucket "$BUCKET" --policy file://bucket-policy.json

# 5. GitHub OIDCプロバイダー(未作成の場合のみ)
OIDC_ARN="arn:aws:iam::$ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

# 6. デプロイ用IAMロール
cat > trust-policy.json <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"$OIDC_ARN"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com","token.actions.githubusercontent.com:sub":"$SUB"}}}]}
JSON
aws iam create-role --role-name "$ROLE" --assume-role-policy-document file://trust-policy.json >/dev/null

cat > deploy-policy.json <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:ListBucket"],"Resource":["arn:aws:s3:::$BUCKET","arn:aws:s3:::$BUCKET/*"]},{"Effect":"Allow","Action":"cloudfront:CreateInvalidation","Resource":"arn:aws:cloudfront::$ACCOUNT:distribution/$DIST_ID"}]}
JSON
aws iam put-role-policy --role-name "$ROLE" --policy-name DeployToS3 --policy-document file://deploy-policy.json

echo "BUCKET      : $BUCKET"
echo "DIST_ID     : $DIST_ID"
echo "DIST_DOMAIN : $DIST_DOMAIN"
echo "ROLE_ARN    : arn:aws:iam::$ACCOUNT:role/$ROLE"
