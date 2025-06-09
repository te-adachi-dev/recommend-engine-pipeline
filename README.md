# レコメンドエンジン風データパイプライン

GCPを使用したECサイト購買データのレコメンドシステム練習用プロジェクト

## 🚀 クイックスタート

### 1. 準備
```bash
# GCPプロジェクト設定
gcloud config set project test-recommend-engine-20250609

# 必要なAPI有効化
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### 2. デプロイ
```bash
# 一括デプロイ
chmod +x scripts/deploy-all.sh
./scripts/deploy-all.sh
```

### 3. テスト
```bash
# APIテスト
curl "https://test-recommend-engine-20250609.appspot.com/health"
curl "https://test-recommend-engine-20250609.appspot.com/recommend?user_id=1001"
```

### 4. クリーンアップ
```bash
# リソース削除
chmod +x scripts/cleanup.sh
./scripts/cleanup.sh
```

## 📊 システム構成

- **データ基盤**: BigQuery + Cloud Storage
- **ETL**: Dataflow (Apache Beam)
- **機械学習**: Vertex AI
- **API**: App Engine
- **インフラ**: Terraform

## 💰 コスト最適化

- 最小リソース設定
- 自動スケーリング
- データ保持期間制限

## 📝 ライセンス

MIT License
