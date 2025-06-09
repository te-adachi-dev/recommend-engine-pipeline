# レコメンドエンジンパイプライン

GCPを使用したECサイト購買データのレコメンドシステム

## 🚀 クイックスタート

### 事前準備
```bash
# 1. 新しいGCPプロジェクト作成
gcloud projects create [新しいプロジェクトID] --name="recommend-engine"

# 2. プロジェクトIDを全ファイルで置換
# 下記コマンドで一括置換（[新しいプロジェクトID]を実際のIDに変更）
find . -type f -name "*.sh" -o -name "*.py" -o -name "*.tf" -o -name "*.yaml" -o -name "*.md" -o -name "*.java" | \
xargs sed -i 's/test-recommend-engine-20250609/[新しいプロジェクトID]/g'

# 3. プロジェクト設定
gcloud config set project [新しいプロジェクトID]
```

### デプロイ手順
```bash
# 1. セットアップ実行
chmod +x scripts/setup.sh
./scripts/setup.sh

# 2. 一括デプロイ
chmod +x scripts/deploy-all.sh
./scripts/deploy-all.sh
```

### テスト
```bash
# APIテスト（[新しいプロジェクトID]を実際のIDに変更）
curl "https://[新しいプロジェクトID].appspot.com/health"
curl "https://[新しいプロジェクトID].appspot.com/recommend?user_id=1001"
```

### クリーンアップ
```bash
# 完全削除
gcloud projects delete [新しいプロジェクトID]
```

## 📊 システム構成

- **データ基盤**: BigQuery + Cloud Storage
- **ETL**: Dataflow (Apache Beam)
- **機械学習**: Vertex AI (協調フィルタリング)
- **API**: App Engine (Flask)
- **インフラ**: Terraform

## 🔧 技術スタック

- **Python**: Flask, scikit-learn, pandas
- **Java**: Apache Beam (Dataflow)
- **Infrastructure**: Terraform
- **Database**: BigQuery
- **Storage**: Cloud Storage

## 💰 コスト最適化

- 最小リソース設定（App Engine: 0.5GB RAM）
- 自動スケーリング（0-2インスタンス）
- データ保持期間30日制限
- 即座削除機能

## 🎯 学習目標

- GCPマルチサービス連携
- Terraformインフラ管理
- MLパイプライン構築
- コスト効率的な運用

## 📝 ライセンス

MIT License