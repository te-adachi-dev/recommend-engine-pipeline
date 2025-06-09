#!/bin/bash
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

cleanup_app_engine() {
    print_status "App Engine サービス停止中..."
    gcloud app services set-traffic default --splits=0.0.0=1 --quiet || true
    print_status "App Engine クリーンアップ完了"
}

cleanup_cloud_functions() {
    print_status "Cloud Functions 削除中..."
    gcloud functions delete data-ingestion --region=asia-northeast1 --quiet || print_warning "関数削除失敗またはスキップ"
    print_status "Cloud Functions クリーンアップ完了"
}

cleanup_terraform() {
    print_status "Terraform リソース削除中..."
    
    cd terraform
    terraform destroy -auto-approve
    cd ..
    
    print_status "Terraform クリーンアップ完了"
}

confirm_deletion() {
    echo ""
    print_warning "警告: このスクリプトは全てのGCPリソースを削除します！"
    echo ""
    
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "キャンセルされました"
        exit 0
    fi
}

main() {
    print_status "=== リソースクリーンアップ開始 ==="
    
    confirm_deletion
    
    cleanup_app_engine
    cleanup_cloud_functions
    cleanup_terraform
    
    print_status "=== クリーンアップ完了 ==="
    echo ""
    echo "プロジェクト完全削除:"
    echo "gcloud projects delete $PROJECT_ID"
    echo ""
}

main "$@"
