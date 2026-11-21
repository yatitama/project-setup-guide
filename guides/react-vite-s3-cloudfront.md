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
- **手元の Claude Code で作業するときは、メインのコンテキストを小さく保つため、リポジトリの検索とテスト実行は Haiku のサブエージェントに任せる**（`.claude/agents/` の search＝全体像、grep＝呼び出し箇所、audit＝diff の確認とビルド・テスト）。メインは結果の要約だけを受け取る。
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

### 2.4 Claude Code のモデルとサブエージェント

メインは Sonnet、アドバイザーは Opus、検索・呼び出し箇所・diff の確認は Haiku のサブエージェントに任せる構成。

`.claude/settings.json`

````json
{
  "model": "sonnet",
  "advisorModel": "opus"
}
````

`.claude/agents/search.md`

````markdown
---
name: search
description: リポジトリの全体像を読み取り専用で調べる。どこに何があるか、関係するファイルや文書を知りたいときに使う。
tools: Read, Grep, Glob
model: haiku
---

リポジトリを読み取り専用で調べ、頼まれた事柄の全体像を報告する。

- 最初に CLAUDE.md と、そこに名前が出ている docs/ の文書から当たりを付ける。
- 報告は結論を先に、関係するファイルを `パス:行番号` で挙げ、役割を1行ずつ添える。
- ファイルの中身を長く貼らない。必要な数行だけ引用する。
- 分からなかったことは「分からなかった」と書く。推測には推測と書く。
````

`.claude/agents/grep.md`

````markdown
---
name: grep
description: 関数・型・設定キー・文字列の呼び出し箇所や使われている場所を全部見つける。名前が分かっているものの検索に使う。
tools: Grep, Glob, Read
model: haiku
---

渡された名前の定義と、使っている箇所を漏れなく見つける。

- 別名での import、文字列での参照、テスト、スクリプト、ドキュメントも探す。
- 結果は `パス:行番号` とその1行だけを、定義・呼び出し・テスト・その他に分けて並べる。
- 件数を最後に書く。見つからなければ、試した検索語を書く。
- 解釈や修正案は書かない。
````

`.claude/agents/audit.md`

````markdown
---
name: audit
description: 作業ブランチの diff を使い捨ての worktree で確認する。コミット済みの変更のレビューと、ビルド・テストの実行に使う。
tools: Read, Grep, Glob, Bash
model: haiku
isolation: worktree
---

使い捨ての worktree の中で、渡されたブランチの変更を確認する。

- worktree は既定のブランチから作られる。最初に `git diff origin/main...<渡されたブランチ>` で差分を読み、
  テストを頼まれたら `git checkout --detach <渡されたブランチ>` してから実行する。
- 見るのはコミット済みの変更だけ。呼び出し元の未コミットの変更は見えない。
- ビルド・テストを頼まれたら `npm ci` のあとに実行し、失敗したテスト名とエラーの要点だけを返す。
- ファイルを編集しない。コミット・push・ブランチの作成や削除をしない。
- 報告は 重大な問題／気になる点／問題なし の順。それぞれ `パス:行番号` と理由を1〜2行で。
- CLAUDE.md の決まりに反する変更があれば必ず挙げる。
````

注意:
- `settings.json` のモデルとアドバイザーが効くのは、手元の Claude Code と、リポジトリ1つで開いたクラウドのセッション。
- アドバイザーは実験的な機能で、いつ相談するかは Claude が決める。
- audit は使い捨ての worktree で動くので作業ブランチに影響しない。見えるのはコミット済みの変更だけで、テストの前に `npm ci` が要る。
- 項目名の出典: https://code.claude.com/docs/en/sub-agents ／ https://code.claude.com/docs/en/advisor

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
# 引用符なしのEOFにすること('EOF'だと$(date)が展開されない)
cat << EOF > /tmp/distribution-config.json
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

> 4〜5章のAWSリソースは、[一括作成スクリプト](scripts/aws-setup.sh)でまとめて作成できる（AWS CloudShell推奨）。先頭の変数を編集して実行し、最後に出力される4行（バケット名・Distribution ID・ドメイン・ロールARN）を控える。

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
# ※ 新しいリポジトリではsubの形式が異なる場合がある。5.5を参照
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

### 5.5 トラブルシューティング

#### `Not authorized to perform sts:AssumeRoleWithWebIdentity`

信頼ポリシーの `sub` がGitHubが実際に送る値と一致していない。新しいリポジトリでは `sub` が既定で次の形式になる場合がある。

- 想定: `repo:<owner>/<repo>:ref:refs/heads/main`
- 実際: `repo:<owner>@<ownerID>/<repo>@<repoID>:ref:refs/heads/main`

実際の値は、一時的に次のステップを `configure-aws-credentials` の前に追加して確認する（原因特定後に削除する）。

```yaml
      - name: Debug OIDC claims
        run: |
          TOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r .value)
          echo "$TOKEN" | cut -d. -f2 | tr '_-' '/+' | { read p; echo "${p}==" | base64 -d 2>/dev/null; } | jq '{sub, aud, ref, repository, iss}'
```

表示された `sub` で信頼ポリシーを更新する。

```bash
aws iam update-assume-role-policy --role-name github-actions-<repo>-deploy \
  --policy-document file://trust-policy.json   # subを実際の値に書き換えたもの
```

それでも失敗する場合の確認項目:
- シークレット `AWS_ROLE_ARN` がロールの実ARNと完全一致しているか（前後の空白・改行に注意。入れ直すのが確実）
- IAMのIDプロバイダー `token.actions.githubusercontent.com` の対象者に `sts.amazonaws.com` があるか
- 失敗した実行が `main` ブランチのものか（信頼ポリシーは `main` のみ許可）

#### `AccessDenied ... s3:ListBucket ... no identity-based policy allows`

ロールにデプロイ用ポリシー（5.3の `DeployToS3`）が付いていない。ロール作成後にスクリプトが止まっていた場合に起こる。次で確認・付与する。

```bash
aws iam get-role-policy --role-name github-actions-<repo>-deploy --policy-name DeployToS3
# NoSuchEntityなら5.3を実行
```

#### デプロイ成功後、CloudFrontのURLが403になる

S3バケットポリシー（4.4）が未設定。`aws s3api get-bucket-policy --bucket <bucket>` で確認する。

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
