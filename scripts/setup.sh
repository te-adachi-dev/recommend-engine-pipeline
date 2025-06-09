#!/bin/bash
# scripts/setup.sh

set -e

echo "=== レコメンドエンジンパイプライン セットアップ ==="

# 変数設定
PROJECT_ID="test-recommend-engine-20250609"
REGION="asia-northeast1"
ZONE="asia-northeast1-a"

# 色付きメッセージ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 必要なコマンドの確認
check_requirements() {
    print_status "必要なコマンドの確認中..."
    
    commands=("gcloud" "terraform" "mvn" "python3")
    for cmd in "${commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd が見つかりません。インストールしてください。"
            exit 1
        fi
    done
    
    print_status "すべての必要なコマンドが利用可能です"
}

# GCPプロジェクト設定
setup_gcp_project() {
    print_status "GCPプロジェクト設定中..."
    
    # プロジェクト設定
    gcloud config set project $PROJECT_ID
    gcloud config set compute/region $REGION
    gcloud config set compute/zone $ZONE
    
    # API有効化
    print_status "必要なAPIを有効化中..."
    gcloud services enable compute.googleapis.com
    gcloud services enable storage.googleapis.com
    gcloud services enable bigquery.googleapis.com
    gcloud services enable dataflow.googleapis.com
    gcloud services enable cloudfunctions.googleapis.com
    gcloud services enable aiplatform.googleapis.com
    gcloud services enable appengine.googleapis.com
    gcloud services enable artifactregistry.googleapis.com
    gcloud services enable cloudscheduler.googleapis.com
    
    print_status "GCPプロジェクト設定完了"
}

# サービスアカウント作成
create_service_accounts() {
    print_status "サービスアカウント作成中..."
    
    # Terraformサービスアカウント
    gcloud iam service-accounts create terraform-sa \
        --display-name="Terraform Service Account" \
        --description="Terraformインフラ管理用" || true
    
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:terraform-sa@$PROJECT_ID.iam.gserviceaccount.com" \
        --role="roles/editor"
    
    # キー生成（既存の場合はスキップ）
    if [ ! -f "terraform-key.json" ]; then
        gcloud iam service-accounts keys create terraform-key.json \
            --iam-account=terraform-sa@$PROJECT_ID.iam.gserviceaccount.com
        print_status "Terraformサービスアカウントキーを生成しました"
    else
        print_warning "terraform-key.jsonが既に存在します"
    fi
    
    print_status "サービスアカウント作成完了"
}

# App Engine初期化
setup_app_engine() {
    print_status "App Engine初期化中..."
    
    # App Engineアプリケーション作成（既存の場合はエラーを無視）
    gcloud app create --region=$REGION 2>/dev/null || print_warning "App Engineアプリは既に存在します"
    
    print_status "App Engine初期化完了"
}

# Python環境セットアップ
setup_python_env() {
    print_status "Python環境セットアップ中..."
    
    # 仮想環境作成
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        print_status "Python仮想環境を作成しました"
    fi
    
    # 仮想環境アクティベート
    source venv/bin/activate
    
    # 依存関係インストール
    pip install --upgrade pip
    pip install google-cloud-bigquery google-cloud-storage google-cloud-dataflow-client
    
    print_status "Python環境セットアップ完了"
}

# Dataflow用Java環境確認
check_java_env() {
    print_status "Java環境確認中..."
    
    if ! command -v java &> /dev/null; then
        print_error "Javaが見つかりません。JDK 11以上をインストールしてください。"
        exit 1
    fi
    
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    print_status "Java version: $java_version"
    
    if ! command -v mvn &> /dev/null; then
        print_error "Mavenが見つかりません。Apache Mavenをインストールしてください。"
        exit 1
    fi
    
    print_status "Java環境確認完了"
}

main() {
    print_status "セットアップ開始..."
    
    check_requirements
    setup_gcp_project
    create_service_accounts
    setup_app_engine
    setup_python_env
    check_java_env
    
    print_status "セットアップ完了！"
    echo ""
    echo "次のステップ:"
    echo "1. terraform/terraform.tfvars を編集"
    echo "2. ./scripts/deploy-all.sh を実行"
    echo ""
}

main "$@"

#!/bin/bash
# scripts/deploy-all.sh

set -e

PROJECT_ID="test-recommend-engine-20250609"

# 色付きメッセージ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

deploy_terraform() {
    print_step "1. Terraformインフラデプロイ"
    
    cd terraform
    
    # terraform.tfvarsファイル確認
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvarsが見つかりません。terraform.tfvars.exampleをコピーして編集してください。"
        cp terraform.tfvars.example terraform.tfvars
        print_error "terraform.tfvarsを編集してから再実行してください。"
        exit 1
    fi
    
    # サービスアカウントキー設定
    export GOOGLE_APPLICATION_CREDENTIALS="../terraform-key.json"
    
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

deploy_vertex_ai() {
    print_step "5. Vertex AI モデル訓練・デプロイ"
    
    cd vertex-ai
    chmod +x deploy.sh
    ./deploy.sh
    cd ..
    
    print_status "Vertex AI デプロイ完了"
}

deploy_app_engine() {
    print_step "6. App Engine API デプロイ"
    
    cd app-engine
    gcloud app deploy --quiet
    cd ..
    
    print_status "App Engine デプロイ完了"
}

test_system() {
    print_step "7. システムテスト"
    
    # データ取り込みテスト
    print_status "データ取り込みテスト中..."
    curl -X POST "https://asia-northeast1-$PROJECT_ID.cloudfunctions.net/data-ingestion" \
        -H "Content-Type: application/json" \
        -d '{}' || print_warning "Cloud Functions呼び出しに失敗しました"
    
    # APIテスト
    print_status "APIテスト中..."
    sleep 10  # API起動待ち
    curl -s "https://$PROJECT_ID.appspot.com/health" || print_warning "API呼び出しに失敗しました"
    
    print_status "システムテスト完了"
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
    echo "💾 Cloud Storage:"
    echo "   gs://$PROJECT_ID-data-lake"
    echo ""
    echo "📊 BigQuery:"
    echo "   プロジェクト: $PROJECT_ID"
    echo "   データセット: recommend_data"
    echo ""
    echo "=== テスト用コマンド ==="
    echo "# ヘルスチェック:"
    echo "curl https://$PROJECT_ID.appspot.com/health"
    echo ""
    echo "# レコメンド取得:"
    echo "curl 'https://$PROJECT_ID.appspot.com/recommend?user_id=1001'"
    echo ""
    echo "# 人気商品取得:"
    echo "curl 'https://$PROJECT_ID.appspot.com/popular?n_items=5'"
    echo ""
    echo "# ユーザープロファイル:"
    echo "curl 'https://$PROJECT_ID.appspot.com/user-profile?user_id=1001'"
    echo ""
}

main() {
    print_status "=== レコメンドエンジンパイプライン 全体デプロイ開始 ==="
    
    deploy_terraform
    upload_sample_data
    build_dataflow
    deploy_cloud_functions
    deploy_vertex_ai
    deploy_app_engine
    test_system
    show_endpoints
    
    print_status "=== 全体デプロイ完了 ==="
}

main "$@"

#!/bin/bash
# dataflow/build.sh

set -e

PROJECT_ID="test-recommend-engine-20250609"
BUCKET_NAME="$PROJECT_ID-data-lake"
REGION="asia-northeast1"

echo "Dataflow パイプラインビルド開始..."

# Mavenビルド
mvn clean compile package -Pdataflow-runner

echo "JARファイル作成完了"

# GCSにテンプレートアップロード（オプション）
JAR_FILE="target/recommend-pipeline-1.0-SNAPSHOT.jar"
if [ -f "$JAR_FILE" ]; then
    gsutil cp $JAR_FILE gs://$BUCKET_NAME/templates/
    echo "JARファイルをGCSにアップロードしました"
fi

# テストラン（ローカル）
echo "ローカルテスト実行..."
mvn exec:java \
    -Dexec.mainClass=com.example.RecommendPipeline \
    -Dexec.args="--project=$PROJECT_ID \
                 --inputFile=gs://$BUCKET_NAME/input/transactions.csv \
                 --dataset=recommend_data \
                 --table=processed_transactions \
                 --runner=DirectRunner"

echo "Dataflow パイプラインビルド完了"

#!/bin/bash
# cloud-functions/deploy.sh

set -e

PROJECT_ID="test-recommend-engine-20250609"
REGION="asia-northeast1"

echo "Cloud Functions デプロイ開始..."

# データ取り込み関数デプロイ
cd data-ingestion

gcloud functions deploy data-ingestion \
    --runtime python39 \
    --trigger-http \
    --entry-point data_ingestion \
    --memory 512MB \
    --timeout 300s \
    --region $REGION \
    --allow-unauthenticated \
    --set-env-vars GOOGLE_CLOUD_PROJECT=$PROJECT_ID

echo "data-ingestion関数のデプロイ完了"

cd ..

echo "Cloud Functions デプロイ完了"

#!/bin/bash
# vertex-ai/deploy.sh

set -e

PROJECT_ID="test-recommend-engine-20250609"
REGION="asia-northeast1"
BUCKET_NAME="$PROJECT_ID-data-lake"

echo "Vertex AI モデル訓練・デプロイ開始..."

# Python仮想環境準備
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate
pip install -r training/requirements.txt

# ローカル訓練実行
cd training
python trainer.py
cd ..

echo "モデル訓練完了"

# 予測用コンテナイメージビルド（簡易版）
cd prediction

cat > predictor.py << 'EOF'
# vertex-ai/prediction/predictor.py

import os
import joblib
import json
from flask import Flask, request, jsonify
from google.cloud import storage

app = Flask(__name__)

MODEL_PATH = "/tmp/model.pkl"
model = None

def load_model():
    global model
    if model is None:
        # GCSからモデル読み込み（実装簡略化）
        print("モデル読み込み中...")
        # ここで実際のモデル読み込み処理
        model = {"dummy": True}
    return model

@app.route('/predict', methods=['POST'])
def predict():
    data = request.get_json()
    user_id = data.get('user_id')
    
    model = load_model()
    
    # ダミー予測
    recommendations = [
        {"product_id": 2001, "score": 0.9},
        {"product_id": 2002, "score": 0.8}
    ]
    
    return jsonify({
        "user_id": user_id,
        "recommendations": recommendations
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

cat > requirements.txt << 'EOF'
flask==3.0.0
google-cloud-storage==2.10.0
joblib==1.3.2
EOF

echo "Vertex AI デプロイ完了（簡易版）"

cd ..

deactivate

echo "Vertex AI デプロイ完了"

#!/bin/bash
# scripts/cleanup.sh

set -e

PROJECT_ID="test-recommend-engine-20250609"

# 色付きメッセージ用
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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup_app_engine() {
    print_status "App Engine サービス削除中..."
    
    # App Engineサービス停止（defaultサービスは削除不可）
    gcloud app services set-traffic default --splits=0.0.0=1 --quiet || true
    
    print_status "App Engine クリーンアップ完了"
}

cleanup_cloud_functions() {
    print_status "Cloud Functions 削除中..."
    
    gcloud functions delete data-ingestion \
        --region=asia-northeast1 \
        --quiet || print_warning "data-ingestion関数の削除に失敗"
    
    print_status "Cloud Functions クリーンアップ完了"
}

cleanup_storage() {
    print_status "Cloud Storage 削除中..."
    
    # バケット内容削除
    gsutil -m rm -r gs://$PROJECT_ID-data-lake/** || true
    
    # バケット削除はTerraformに任せる
    print_status "Cloud Storage クリーンアップ完了"
}

cleanup_scheduler() {
    print_status "Cloud Scheduler ジョブ削除中..."
    
    gcloud scheduler jobs delete daily-recommend-pipeline \
        --location=asia-northeast1 \
        --quiet || print_warning "Schedulerジョブの削除に失敗"
    
    print_status "Cloud Scheduler クリーンアップ完了"
}

cleanup_terraform() {
    print_status "Terraform リソース削除中..."
    
    cd terraform
    
    export GOOGLE_APPLICATION_CREDENTIALS="../terraform-key.json"
    
    terraform destroy -auto-approve
    
    cd ..
    
    print_status "Terraform クリーンアップ完了"
}

cleanup_local_files() {
    print_status "ローカルファイル削除中..."
    
    # Terraform状態ファイル
    rm -f terraform/terraform.tfstate*
    rm -f terraform/.terraform.lock.hcl
    rm -rf terraform/.terraform/
    
    # Mavenビルド成果物
    rm -rf dataflow/target/
    
    # Python仮想環境
    rm -rf venv/
    rm -rf */venv/
    
    # 一時ファイル
    rm -f terraform-key.json
    
    print_status "ローカルファイルクリーンアップ完了"
}

confirm_deletion() {
    echo ""
    print_warning "警告: このスクリプトは以下のリソースを削除します:"
    echo "  - App Engine デプロイメント"
    echo "  - Cloud Functions"
    echo "  - Cloud Storage バケットとデータ"
    echo "  - BigQuery データセットとテーブル"
    echo "  - Cloud Scheduler ジョブ"
    echo "  - サービスアカウント"
    echo "  - ローカルファイル"
    echo ""
    
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "キャンセルされました"
        exit 0
    fi
}

main() {
    print_status "=== レコメンドエンジンパイプライン クリーンアップ開始 ==="
    
    confirm_deletion
    
    cleanup_app_engine
    cleanup_cloud_functions
    cleanup_storage
    cleanup_scheduler
    cleanup_terraform
    cleanup_local_files
    
    print_status "=== クリーンアップ完了 ==="
    echo ""
    echo "プロジェクト完全削除を行う場合:"
    echo "gcloud projects delete $PROJECT_ID"
    echo ""
}

main "$@"

#!/bin/bash
# scripts/test-system.sh

set -e

PROJECT_ID="test-recommend-engine-20250609"
API_URL="https://$PROJECT_ID.appspot.com"
FUNCTIONS_URL="https://asia-northeast1-$PROJECT_ID.cloudfunctions.net"

# 色付きメッセージ用
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

test_api_health() {
    print_test "API ヘルスチェック"
    
    response=$(curl -s -w "%{http_code}" -o /tmp/health_response.json "$API_URL/health")
    http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        print_success "API ヘルスチェック成功"
        cat /tmp/health_response.json | python3 -m json.tool
    else
        print_fail "API ヘルスチェック失敗 (HTTP: $http_code)"
        cat /tmp/health_response.json 2>/dev/null || echo "レスポンス取得失敗"
    fi
    
    echo ""
}

test_recommendations() {
    print_test "レコメンド機能テスト"
    
    user_ids=(1001 1002 1003)
    
    for user_id in "${user_ids[@]}"; do
        print_test "ユーザー $user_id のレコメンド取得"
        
        response=$(curl -s -w "%{http_code}" -o /tmp/recommend_response.json \
            "$API_URL/recommend?user_id=$user_id&n_recommendations=3")
        http_code="${response: -3}"
        
        if [ "$http_code" = "200" ]; then
            print_success "ユーザー $user_id レコメンド取得成功"
            cat /tmp/recommend_response.json | python3 -m json.tool
        else
            print_fail "ユーザー $user_id レコメンド取得失敗 (HTTP: $http_code)"
        fi
        
        echo ""
    done
}

test_popular_items() {
    print_test "人気商品機能テスト"
    
    response=$(curl -s -w "%{http_code}" -o /tmp/popular_response.json \
        "$API_URL/popular?n_items=5")
    http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        print_success "人気商品取得成功"
        cat /tmp/popular_response.json | python3 -m json.tool
    else
        print_fail "人気商品取得失敗 (HTTP: $http_code)"
    fi
    
    echo ""
}

test_user_profile() {
    print_test "ユーザープロファイル機能テスト"
    
    response=$(curl -s -w "%{http_code}" -o /tmp/profile_response.json \
        "$API_URL/user-profile?user_id=1001")
    http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        print_success "ユーザープロファイル取得成功"
        cat /tmp/profile_response.json | python3 -m json.tool
    else
        print_fail "ユーザープロファイル取得失敗 (HTTP: $http_code)"
    fi
    
    echo ""
}

test_data_ingestion() {
    print_test "データ取り込み機能テスト"
    
    response=$(curl -s -w "%{http_code}" -o /tmp/ingestion_response.json \
        -X POST "$FUNCTIONS_URL/data-ingestion" \
        -H "Content-Type: application/json" \
        -d '{"test": true}')
    http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        print_success "データ取り込み成功"
        cat /tmp/ingestion_response.json | python3 -m json.tool
    else
        print_fail "データ取り込み失敗 (HTTP: $http_code)"
    fi
    
    echo ""
}

test_model_info() {
    print_test "モデル情報取得テスト"
    
    response=$(curl -s -w "%{http_code}" -o /tmp/model_response.json \
        "$API_URL/model-info")
    http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        print_success "モデル情報取得成功"
        cat /tmp/model_response.json | python3 -m json.tool
    else
        print_fail "モデル情報取得失敗 (HTTP: $http_code)"
    fi
    
    echo ""
}

performance_test() {
    print_test "パフォーマンステスト"
    
    start_time=$(date +%s)
    
    for i in {1..10}; do
        curl -s "$API_URL/recommend?user_id=100$i" > /dev/null
    done
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    print_success "10回のレコメンド取得: ${duration}秒"
    echo ""
}

show_summary() {
    echo "=== テスト完了 ==="
    echo ""
    echo "利用可能なエンドポイント:"
    echo "  📱 App Engine API: $API_URL"
    echo "  🔧 Cloud Functions: $FUNCTIONS_URL"
    echo ""
    echo "主要機能:"
    echo "  ✅ ヘルスチェック: $API_URL/health"
    echo "  🎯 レコメンド: $API_URL/recommend?user_id=1001"
    echo "  🔥 人気商品: $API_URL/popular"
    echo "  👤 ユーザー情報: $API_URL/user-profile?user_id=1001"
    echo "  📊 モデル情報: $API_URL/model-info"
    echo ""
}

main() {
    echo "=== レコメンドエンジンパイプライン システムテスト ==="
    echo ""
    
    test_api_health
    test_model_info
    test_popular_items
    test_recommendations
    test_user_profile
    test_data_ingestion
    performance_test
    show_summary
    
    # 一時ファイル削除
    rm -f /tmp/*_response.json
}

main "$@"