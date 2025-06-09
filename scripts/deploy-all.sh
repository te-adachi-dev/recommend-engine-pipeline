#!/bin/bash
set -e

PROJECT_ID="test-recommend-engine-20250609"

# 色付きメッセージ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

deploy_terraform() {
    print_step "1. Terraformインフラデプロイ"
    
    cd terraform
    
    # terraform.tfvarsファイル確認
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvarsが見つかりません。terraform.tfvars.exampleをコピーして編集してください。"
        cp terraform.tfvars.example terraform.tfvars
        print_status "terraform.tfvarsをコピーしました。必要に応じて編集してください。"
    fi
    
    terraform init
    terraform plan
    terraform apply -auto-approve
    
    cd ..
    print_status "Terraformデプロイ完了"
}

upload_sample_data() {
    print_step "2. サンプルデータアップロード"
    
    # Cloud Storageにサンプルデータアップロード
    gsutil -m cp data/sample/*.csv gs://$PROJECT_ID-data-lake/input/
    
    print_status "サンプルデータアップロード完了"
}

build_dataflow() {
    print_step "3. Dataflow パイプラインビルド"
    
    cd dataflow
    chmod +x build.sh
    ./build.sh
    cd ..
    
    print_status "Dataflow パイプラインビルド完了"
}

deploy_cloud_functions() {
    print_step "4. Cloud Functions デプロイ"
    
    cd cloud-functions
    chmod +x deploy.sh
    ./deploy.sh
    cd ..
    
    print_status "Cloud Functions デプロイ完了"
}

deploy_app_engine() {
    print_step "5. App Engine API デプロイ"
    
    cd app-engine
    gcloud app deploy --quiet
    cd ..
    
    print_status "App Engine デプロイ完了"
}

show_endpoints() {
    print_step "デプロイ完了！"
    
    echo ""
    echo "=== アクセス可能なエンドポイント ==="
    echo "📱 App Engine API:"
    echo "   https://$PROJECT_ID.appspot.com"
    echo ""
    echo "🔧 Cloud Functions:"
    echo "   https://asia-northeast1-$PROJECT_ID.cloudfunctions.net/data-ingestion"
    echo ""
    echo "=== テスト用コマンド ==="
    echo "# ヘルスチェック:"
    echo "curl https://$PROJECT_ID.appspot.com/health"
    echo ""
    echo "# レコメンド取得:"
    echo "curl 'https://$PROJECT_ID.appspot.com/recommend?user_id=1001'"
    echo ""
}

main() {
    print_status "=== レコメンドエンジンパイプライン デプロイ開始 ==="
    
    deploy_terraform
    upload_sample_data
    build_dataflow
    deploy_cloud_functions
    deploy_app_engine
    show_endpoints
    
    print_status "=== デプロイ完了 ==="
}

main "$@"
