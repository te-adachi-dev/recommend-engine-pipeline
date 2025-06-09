#!/bin/bash

# terraform/outputs.tf
cat > terraform/outputs.tf << 'EOT'
output "project_id" {
  description = "プロジェクトID"
  value       = var.project_id
}

output "bucket_name" {
  description = "データレイクバケット名"
  value       = google_storage_bucket.data_lake.name
}

output "dataset_id" {
  description = "BigQueryデータセットID"
  value       = google_bigquery_dataset.recommend_dataset.dataset_id
}
EOT

# terraform/terraform.tfvars.example
cat > terraform/terraform.tfvars.example << 'EOT'
project_id = "test-recommend-engine-20250609"
region     = "asia-northeast1"
zone       = "asia-northeast1-a"
app_engine_location = "asia-northeast1"
service_account_email = "terraform-sa@test-recommend-engine-20250609.iam.gserviceaccount.com"
environment = "dev"
cost_threshold = 5.0
EOT

# app-engine/app.yaml
cat > app-engine/app.yaml << 'EOT'
runtime: python39
service: default

basic_scaling:
  max_instances: 1
  idle_timeout: 5m

resources:
  cpu: 0.5
  memory_gb: 0.5

env_variables:
  GOOGLE_CLOUD_PROJECT: test-recommend-engine-20250609
EOT

# app-engine/requirements.txt
cat > app-engine/requirements.txt << 'EOT'
Flask==3.0.0
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
pandas==2.1.4
numpy==1.24.4
scikit-learn==1.3.2
joblib==1.3.2
gunicorn==21.2.0
EOT

# cloud-functions/data-ingestion/requirements.txt
cat > cloud-functions/data-ingestion/requirements.txt << 'EOT'
functions-framework==3.5.0
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
pandas==2.1.4
EOT

# vertex-ai/training/requirements.txt
cat > vertex-ai/training/requirements.txt << 'EOT'
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
pandas==2.1.4
numpy==1.24.4
scikit-learn==1.3.2
joblib==1.3.2
EOT

# scripts/deploy-all.sh
cat > scripts/deploy-all.sh << 'EOT'
#!/bin/bash
set -e

PROJECT_ID="test-recommend-engine-20250609"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 1. プロジェクト設定
print_status "GCPプロジェクト設定..."
gcloud config set project $PROJECT_ID

# API有効化
print_status "必要なAPIを有効化..."
gcloud services enable compute.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable appengine.googleapis.com

# 2. Terraformデプロイ
print_status "Terraformデプロイ..."
cd terraform

if [ ! -f "terraform.tfvars" ]; then
    cp terraform.tfvars.example terraform.tfvars
    print_warning "terraform.tfvarsを編集してプロジェクトIDを確認してください"
fi

terraform init
terraform plan
terraform apply -auto-approve

cd ..

# 3. サンプルデータアップロード
print_status "サンプルデータアップロード..."
gsutil -m cp data/sample/*.csv gs://$PROJECT_ID-data-lake/input/

# 4. Cloud Functions デプロイ
print_status "Cloud Functionsデプロイ..."
cd cloud-functions/data-ingestion
gcloud functions deploy data-ingestion \
    --runtime python39 \
    --trigger-http \
    --entry-point data_ingestion \
    --memory 256MB \
    --timeout 60s \
    --region asia-northeast1 \
    --allow-unauthenticated

cd ../..

# 5. App Engine デプロイ
print_status "App Engineデプロイ..."
cd app-engine
gcloud app deploy --quiet
cd ..

print_status "デプロイ完了！"
echo "API URL: https://$PROJECT_ID.appspot.com"
EOT

# scripts/cleanup.sh
cat > scripts/cleanup.sh << 'EOT'
#!/bin/bash
set -e

PROJECT_ID="test-recommend-engine-20250609"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "=== 高速クリーンアップ開始 ==="

# App Engine無効化
print_status "App Engine停止..."
gcloud app services set-traffic default --splits=0.0.0=1 --quiet || true

# Cloud Functions削除
print_status "Cloud Functions削除..."
gcloud functions delete data-ingestion --region=asia-northeast1 --quiet || true

# Terraform削除
print_status "Terraformリソース削除..."
cd terraform
terraform destroy -auto-approve || true
cd ..

# ローカルファイル削除
print_status "ローカル状態ファイル削除..."
rm -rf terraform/.terraform*
rm -f terraform/terraform.tfstate*

print_status "クリーンアップ完了！コストは最小限に抑えられました。"
EOT

# .gitignore
cat > .gitignore << 'EOT'
# Terraform
terraform/terraform.tfstate*
terraform/.terraform/
terraform/.terraform.lock.hcl
terraform/terraform.tfvars

# Python
__pycache__/
*.pyc
venv/
.env

# Java/Maven
dataflow/target/
*.jar

# GCP
terraform-key.json
*.json
!package.json

# IDE
.vscode/
.idea/

# Logs
*.log
EOT

# README.md
cat > README.md << 'EOT'
# レコメンドエンジンパイプライン

GCPを使用したコスト最小限のレコメンドエンジン練習用プロジェクト

## 🚀 クイックスタート

```bash
# 1. 環境準備
chmod +x scripts/*.sh

# 2. デプロイ（5分で完了）
./scripts/deploy-all.sh

# 3. テスト
curl "https://test-recommend-engine-20250609.appspot.com/health"

# 4. 即座にクリーンアップ
./scripts/cleanup.sh
```

## 💰 コスト管理

- **予想コスト**: $1-2/日（最小構成）
- **即座削除**: `./scripts/cleanup.sh` で全リソース削除
- **再デプロイ**: `./scripts/deploy-all.sh` で5分で復元

## 🔧 技術スタック

- **インフラ**: Terraform
- **API**: App Engine (Python)
- **データ**: BigQuery + Cloud Storage
- **ML**: 協調フィルタリング

## 📊 エンドポイント

- `/health` - ヘルスチェック
- `/recommend?user_id=1001` - レコメンド取得
- `/popular` - 人気商品

## ⚠️ 注意

使用後は必ず `./scripts/cleanup.sh` を実行してコストを抑制してください！
EOT

chmod +x scripts/*.sh

echo "不足ファイル作成完了！"
