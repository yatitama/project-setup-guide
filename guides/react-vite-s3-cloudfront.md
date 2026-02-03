# React + Vite + S3 + CloudFront セットアップガイド

Claude Code on the Webのみで完結する、React + TypeScript + Viteプロジェクトの立ち上げからAWSデプロイまでの手順書です。

## 構成

- **フロントエンド**: React 18 / TypeScript 5 / Vite / Tailwind CSS 3
- **ホスティング**: AWS S3 + CloudFront（OAC使用）
- **CI/CD**: GitHub Actions（OIDC認証）
- **AI支援**: Claude Code Action

---

## 1. リポジトリの立ち上げ

### 1.1 GitHubリポジトリの作成

```bash
# gh CLIでリポジトリを作成
gh repo create <owner>/<repo-name> --public --clone

# 例
gh repo create yatitama/my-new-app --public --clone
cd my-new-app
```

### 1.2 プロジェクトの初期化（Vite + React + TypeScript）

```bash
# Viteプロジェクトを現在のディレクトリに初期化
npm create vite@latest . -- --template react-ts

# 依存関係のインストール
npm install

# Tailwind CSSのインストール
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

---

## 2. 初期ファイルのセットアップ

### 2.1 README.md

```markdown
# <プロジェクト名>

## 概要
<プロジェクトの説明>

## 技術スタック
- React 18 / TypeScript 5 / Vite / Tailwind CSS 3

## 開発コマンド
- `npm run dev` - 開発サーバー起動
- `npm run build` - プロダクションビルド
- `npm run preview` - ビルド結果のプレビュー

## デプロイ
mainブランチへのpushで自動デプロイ（AWS S3 + CloudFront）
```

### 2.2 CLAUDE.md

```markdown
# CLAUDE.md

## プロジェクト概要
<プロジェクトの説明>

## 技術スタック
- React 18 / TypeScript 5 / Vite / Tailwind CSS 3

## ディレクトリ構成
- `src/components/` - UIコンポーネント
- `src/pages/` - ページコンポーネント
- `src/hooks/` - カスタムHooks
- `src/services/` - 外部サービス連携
- `src/types/` - 型定義

## 開発コマンド
- `npm run dev` - 開発サーバー起動
- `npm run build` - プロダクションビルド

## コーディング規約
- `any`禁止、`unknown`を使う
- Enum禁止、Union型で代替
- 関数コンポーネントのみ、`export const`で名前付きエクスポート

## gh コマンド
- `gh`コマンドには必ず`-R owner/repo`オプションを付けること

## 重要なルール
- **毎回の応答の末尾に、コンテキストウィンドウの残量（使用率）を表示すること。**
```

### 2.3 .gitignore

```
node_modules
dist
.env
.env.local
*.log
.DS_Store
```

---

## 3. Claude Code Actionの設定

### 3.1 ワークフローファイルの作成

`.github/workflows/claude.yml` を作成:

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
      (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Run Claude Code
        id: claude
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 3.2 GitHubシークレットの設定

```bash
# Anthropic APIキーをシークレットに設定
gh secret set ANTHROPIC_API_KEY -R <owner>/<repo>
# プロンプトで値を入力
```

---

## 4. AWS S3 + CloudFrontの設定

### 4.1 S3バケットの作成

```bash
# バケット名を変数に設定
BUCKET_NAME="<your-bucket-name>"
REGION="ap-northeast-1"

# S3バケットを作成
aws s3 mb s3://${BUCKET_NAME} --region ${REGION}

# パブリックアクセスをブロック（CloudFront OAC経由でのみアクセス）
aws s3api put-public-access-block \
  --bucket ${BUCKET_NAME} \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 4.2 CloudFront Origin Access Control (OAC)の作成

```bash
# OACを作成
aws cloudfront create-origin-access-control \
  --origin-access-control-config \
  "Name=oac-${BUCKET_NAME},SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3"

# 作成されたOACのIDをメモ（後で使用）
# 出力例: "Id": "E3OGK5AWQXR1F3"
```

### 4.3 CloudFrontディストリビューションの作成

```bash
# distribution-config.jsonを作成
cat << 'EOF' > /tmp/distribution-config.json
{
  "CallerReference": "initial-$(date +%s)",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3Origin",
        "DomainName": "<BUCKET_NAME>.s3.ap-northeast-1.amazonaws.com",
        "OriginPath": "",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        },
        "OriginAccessControlId": "<OAC_ID>"
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3Origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["HEAD", "GET"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["HEAD", "GET"]
      }
    },
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  },
  "DefaultRootObject": "index.html",
  "Enabled": true,
  "Comment": ""
}
EOF

# <BUCKET_NAME>と<OAC_ID>を実際の値に置換してから実行
aws cloudfront create-distribution \
  --distribution-config file:///tmp/distribution-config.json

# 作成されたDistribution IDをメモ
```

### 4.4 S3バケットポリシーの設定

```bash
# CloudFrontからのアクセスのみ許可するポリシー
DISTRIBUTION_ID="<your-distribution-id>"
AWS_ACCOUNT_ID="<your-account-id>"

cat << EOF > /tmp/bucket-policy.json
{
  "Version": "2008-10-17",
  "Id": "PolicyForCloudFrontPrivateContent",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "ArnLike": {
          "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket ${BUCKET_NAME} \
  --policy file:///tmp/bucket-policy.json
```

### 4.5 SPAエラーページ対応（オプション）

```bash
# 403/404エラーでindex.htmlを返す設定
# CloudFrontコンソールで以下を設定:
# Error Pages → Create custom error response
#   - HTTP Error Code: 403
#   - Response Page Path: /index.html
#   - HTTP Response Code: 200
#   - Error Caching Minimum TTL: 10
```

---

## 5. GitHub ActionsによるOIDC認証の設定

### 5.1 OIDCプロバイダーの作成（AWSアカウントで初回のみ）

```bash
# すでに存在する場合はスキップ
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 5.2 IAMロールの作成

```bash
# 信頼ポリシーを作成
cat << 'EOF' > /tmp/trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<owner>/<repo>:*"
        }
      }
    }
  ]
}
EOF

# <AWS_ACCOUNT_ID>, <owner>, <repo>を置換してから実行
aws iam create-role \
  --role-name github-actions-<repo>-deploy \
  --assume-role-policy-document file:///tmp/trust-policy.json
```

### 5.3 IAMポリシーの作成とアタッチ

```bash
# デプロイ用ポリシーを作成
cat << EOF > /tmp/deploy-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation"
      ],
      "Resource": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name github-actions-<repo>-deploy \
  --policy-name DeployToS3 \
  --policy-document file:///tmp/deploy-policy.json
```

### 5.4 GitHubシークレットにロールARNを設定

```bash
gh secret set AWS_ROLE_ARN -R <owner>/<repo>
# 値: arn:aws:iam::<AWS_ACCOUNT_ID>:role/github-actions-<repo>-deploy
```

---

## 6. デプロイワークフローの作成

### 6.1 `.github/workflows/deploy.yml`

```yaml
name: Deploy to S3

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci
      - run: npm run build

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-northeast-1

      - name: Deploy to S3
        run: aws s3 sync dist/ s3://<BUCKET_NAME> --delete

      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id <DISTRIBUTION_ID> \
            --paths "/*"
```

---

## 7. 初デプロイ

### 7.1 初回コミットとプッシュ

```bash
git add .
git commit -m "feat: initial commit"
git push -u origin main
```

### 7.2 デプロイ確認

```bash
# GitHub Actionsのステータス確認
gh run list -R <owner>/<repo> --limit 1

# CloudFront URLでアクセス確認
# https://<distribution-domain>.cloudfront.net
```

---

## チェックリスト

- [ ] GitHubリポジトリ作成
- [ ] Vite + React + TypeScript 初期化
- [ ] README.md 作成
- [ ] CLAUDE.md 作成
- [ ] `.github/workflows/claude.yml` 作成
- [ ] `ANTHROPIC_API_KEY` シークレット設定
- [ ] S3バケット作成
- [ ] CloudFront OAC作成
- [ ] CloudFrontディストリビューション作成
- [ ] S3バケットポリシー設定
- [ ] IAM OIDCプロバイダー作成（初回のみ）
- [ ] IAMロール作成
- [ ] `AWS_ROLE_ARN` シークレット設定
- [ ] `.github/workflows/deploy.yml` 作成
- [ ] 初回デプロイ実行・確認

---

## 参考: yatitama-todo-appの設定値

| 項目 | 値 |
|------|-----|
| S3バケット | `yatitama-todo-app` |
| リージョン | `ap-northeast-1` |
| CloudFront ID | `E3OEJ4XM0Z4DMO` |
| CloudFront Domain | `d1s0hmkfxdlxsi.cloudfront.net` |
| OAC ID | `E3OGK5AWQXR1F3` |
| CachePolicy | `658327ea-f89d-4fab-a63d-7e88639e58f6` (CachingOptimized) |
