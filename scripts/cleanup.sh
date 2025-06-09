#!/bin/bash
# scripts/cleanup.sh - 改善版

set -e

PROJECT_ID="test-recommend-engine-20250609"
REGION="asia-northeast1"

# 色付きメッセージ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# プロジェクト存在確認
check_project() {
    if ! gcloud projects describe $PROJECT_ID &>/dev/null; then
        print_error "プロジェクト $PROJECT_ID が見つかりません"
        exit 1
    fi
    
    # プロジェクト設定
    gcloud config set project $PROJECT_ID
    print_status "プロジェクト設定: $PROJECT_ID"
}

cleanup_cloud_scheduler() {
    print_step "1. Cloud Scheduler ジョブ削除"
    
    # スケジューラージョブ一覧取得・削除
    gcloud scheduler jobs list --location=$REGION --format="value(name)" 2>/dev/null | while read job; do
        if [ ! -z "$job" ]; then
            print_status "Schedulerジョブ削除: $job"
            gcloud scheduler jobs delete $job --location=$REGION --quiet || print_warning "ジョブ削除失敗: $job"
        fi
    done
    
    print_status "Cloud Scheduler クリーンアップ完了"
}

cleanup_cloud_functions() {
    print_step "2. Cloud Functions 削除"
    
    # Cloud Functions一覧取得・削除
    functions=$(gcloud functions list --region=$REGION --format="value(name)" 2>/dev/null || echo "")
    
    if [ ! -z "$functions" ]; then
        echo "$functions" | while read func; do
            if [ ! -z "$func" ]; then
                func_name=$(basename "$func")
                print_status "Cloud Function削除: $func_name"
                gcloud functions delete $func_name --region=$REGION --quiet || print_warning "関数削除失敗: $func_name"
            fi
        done
    else
        print_status "削除するCloud Functionsはありません"
    fi
    
    print_status "Cloud Functions クリーンアップ完了"
}

cleanup_app_engine() {
    print_step "3. App Engine クリーンアップ"
    
    # App Engineサービス確認
    if gcloud app services list --format="value(id)" 2>/dev/null | grep -q "default"; then
        print_status "App Engine トラフィック停止中..."
        
        # 全トラフィックを停止（削除はできないが停止は可能）
        # App Engineのdefaultサービスは削除できないため、トラフィックを0にする
        gcloud app services set-traffic default --splits=__no-version=1 --quiet 2>/dev/null || true
        
        # 非defaultサービスがあれば削除
        services=$(gcloud app services list --format="value(id)" 2>/dev/null | grep -v "default" || echo "")
        if [ ! -z "$services" ]; then
            echo "$services" | while read service; do
                if [ ! -z "$service" ]; then
                    print_status "App Engineサービス削除: $service"
                    gcloud app services delete $service --quiet || print_warning "サービス削除失敗: $service"
                fi
            done
        fi
        
        print_status "App Engine クリーンアップ完了（defaultサービスは停止）"
    else
        print_status "App Engineサービスはありません"
    fi
}

cleanup_storage() {
    print_step "4. Cloud Storage クリーンアップ"
    
    # バケット一覧取得
    buckets=$(gsutil ls -p $PROJECT_ID 2>/dev/null | grep "gs://$PROJECT_ID" || echo "")
    
    if [ ! -z "$buckets" ]; then
        echo "$buckets" | while read bucket; do
            if [ ! -z "$bucket" ]; then
                bucket_name=$(echo $bucket | sed 's|gs://||' | sed 's|/||')
                print_status "バケット削除: $bucket_name"
                
                # バケット内容削除
                gsutil -m rm -r $bucket/** 2>/dev/null || true
                # バケット削除
                gsutil rb $bucket || print_warning "バケット削除失敗: $bucket_name"
            fi
        done
    else
        print_status "削除するCloud Storageバケットはありません"
    fi
    
    print_status "Cloud Storage クリーンアップ完了"
}

cleanup_bigquery() {
    print_step "5. BigQuery クリーンアップ"
    
    # データセット一覧取得・削除
    datasets=$(bq ls -d --format=csv --max_results=1000 | tail -n +2 | cut -d',' -f1 2>/dev/null || echo "")
    
    if [ ! -z "$datasets" ]; then
        echo "$datasets" | while read dataset; do
            if [ ! -z "$dataset" ] && [ "$dataset" != "datasetId" ]; then
                print_status "BigQueryデータセット削除: $dataset"
                bq rm -r -f -d $PROJECT_ID:$dataset || print_warning "データセット削除失敗: $dataset"
            fi
        done
    else
        print_status "削除するBigQueryデータセットはありません"
    fi
    
    print_status "BigQuery クリーンアップ完了"
}

cleanup_artifact_registry() {
    print_step "6. Artifact Registry クリーンアップ"
    
    # リポジトリ一覧取得・削除
    repos=$(gcloud artifacts repositories list --location=$REGION --format="value(name)" 2>/dev/null || echo "")
    
    if [ ! -z "$repos" ]; then
        echo "$repos" | while read repo; do
            if [ ! -z "$repo" ]; then
                repo_name=$(basename "$repo")
                print_status "Artifact Registryリポジトリ削除: $repo_name"
                gcloud artifacts repositories delete $repo_name --location=$REGION --quiet || print_warning "リポジトリ削除失敗: $repo_name"
            fi
        done
    else
        print_status "削除するArtifact Registryリポジトリはありません"
    fi
    
    print_status "Artifact Registry クリーンアップ完了"
}

cleanup_terraform() {
    print_step "7. Terraform リソース削除"
    
    if [ -f "terraform/terraform.tfstate" ] && [ -s "terraform/terraform.tfstate" ]; then
        print_status "Terraformでリソース削除中..."
        
        cd terraform
        
        # Terraform初期化（状態ファイルがある場合）
        terraform init || print_warning "Terraform初期化失敗"
        
        # 削除実行
        terraform destroy -auto-approve || print_warning "Terraform削除で一部失敗"
        
        cd ..
        print_status "Terraform クリーンアップ完了"
    else
        print_status "Terraformの状態ファイルがないため、スキップ"
    fi
}

cleanup_iam() {
    print_step "8. サービスアカウント削除"
    
    # カスタムサービスアカウント削除
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email ~ .*@$PROJECT_ID.iam.gserviceaccount.com" 2>/dev/null || echo "")
    
    if [ ! -z "$service_accounts" ]; then
        echo "$service_accounts" | while read sa; do
            if [ ! -z "$sa" ] && [[ $sa == *"@$PROJECT_ID.iam.gserviceaccount.com" ]]; then
                print_status "サービスアカウント削除: $sa"
                gcloud iam service-accounts delete $sa --quiet || print_warning "サービスアカウント削除失敗: $sa"
            fi
        done
    else
        print_status "削除するカスタムサービスアカウントはありません"
    fi
    
    print_status "サービスアカウント クリーンアップ完了"
}

show_remaining_resources() {
    print_step "9. 残存リソース確認"
    
    echo ""
    print_status "=== 残存リソース確認 ==="
    
    # Compute Engine
    instances=$(gcloud compute instances list --format="value(name)" 2>/dev/null || echo "")
    if [ ! -z "$instances" ]; then
        print_warning "残存Compute Engineインスタンス:"
        echo "$instances"
    fi
    
    # Cloud SQL
    sql_instances=$(gcloud sql instances list --format="value(name)" 2>/dev/null || echo "")
    if [ ! -z "$sql_instances" ]; then
        print_warning "残存Cloud SQLインスタンス:"
        echo "$sql_instances"
    fi
    
    # その他の確認
    print_status "手動確認推奨: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
}

confirm_deletion() {
    echo ""
    print_warning "⚠️  警告: このスクリプトは以下のリソースを削除します:"
    echo "  - Cloud Functions"
    echo "  - App Engine サービス"
    echo "  - Cloud Storage バケット"
    echo "  - BigQuery データセット"
    echo "  - Artifact Registry リポジトリ"
    echo "  - Cloud Scheduler ジョブ"
    echo "  - サービスアカウント"
    echo "  - その他のTerraformリソース"
    echo ""
    print_warning "プロジェクト完全削除: gcloud projects delete $PROJECT_ID"
    echo ""
    
    read -p "リソース削除を続行しますか？ (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "キャンセルされました"
        exit 0
    fi
}

main() {
    print_status "=== GCPリソース完全クリーンアップ開始 ==="
    echo ""
    
    check_project
    confirm_deletion
    
    cleanup_cloud_scheduler
    cleanup_cloud_functions
    cleanup_app_engine
    cleanup_storage
    cleanup_bigquery
    cleanup_artifact_registry
    cleanup_terraform
    cleanup_iam
    show_remaining_resources
    
    echo ""
    print_status "=== クリーンアップ完了 ==="
    echo ""
    echo "💰 完全なコスト削除のため、プロジェクト削除を推奨:"
    echo ""
    echo "    gcloud projects delete $PROJECT_ID"
    echo ""
    echo "📝 次回作業時:"
    echo "    1. 新しいプロジェクト作成"
    echo "    2. 課金アカウントリンク"
    echo "    3. git pull && ./scripts/deploy-all.sh"
    echo ""
}

main "$@"