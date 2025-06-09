#!/bin/bash
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
    gsutil cp $JAR_FILE gs://$BUCKET_NAME/templates/ || echo "GCSアップロードスキップ（バケット未作成）"
    echo "JARファイル準備完了"
fi

echo "Dataflow パイプラインビルド完了"
