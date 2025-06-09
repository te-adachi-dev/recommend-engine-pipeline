#!/bin/bash
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
