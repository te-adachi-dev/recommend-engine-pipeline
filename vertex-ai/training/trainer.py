# vertex-ai/training/trainer.py

import os
import logging
import pandas as pd
import numpy as np
from sklearn.decomposition import TruncatedSVD
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.preprocessing import StandardScaler
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import aiplatform
import joblib
import json
from datetime import datetime

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 設定
PROJECT_ID = "test-recommend-engine-20250609"
DATASET_ID = "recommend_data"
BUCKET_NAME = f"{PROJECT_ID}-data-lake"
MODEL_DIR = "models"

class RecommendationModel:
    """シンプルな協調フィルタリングレコメンドモデル"""
    
    def __init__(self):
        self.user_item_matrix = None
        self.svd_model = None
        self.scaler = None
        self.user_mapping = {}
        self.item_mapping = {}
        self.reverse_user_mapping = {}
        self.reverse_item_mapping = {}
        
    def prepare_data(self):
        """BigQueryからデータを取得して前処理"""
        logger.info("データ準備開始")
        
        # BigQueryクライアント
        client = bigquery.Client(project=PROJECT_ID)
        
        # 取引データ取得
        query = f"""
        SELECT 
            user_id,
            product_id,
            SUM(quantity) as total_quantity,
            AVG(price) as avg_price,
            COUNT(*) as purchase_count
        FROM `{PROJECT_ID}.{DATASET_ID}.transactions`
        WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
        GROUP BY user_id, product_id
        HAVING total_quantity > 0
        """
        
        df = client.query(query).to_dataframe()
        logger.info(f"取引データ取得: {len(df)}件")
        
        if len(df) == 0:
            # サンプルデータ生成
            df = self.generate_sample_data()
        
        # ユーザー・アイテムマッピング作成
        unique_users = df['user_id'].unique()
        unique_items = df['product_id'].unique()
        
        self.user_mapping = {user: idx for idx, user in enumerate(unique_users)}
        self.item_mapping = {item: idx for idx, item in enumerate(unique_items)}
        self.reverse_user_mapping = {idx: user for user, idx in self.user_mapping.items()}
        self.reverse_item_mapping = {idx: item for item, idx in self.item_mapping.items()}
        
        # ユーザー-アイテム行列作成
        matrix_data = []
        for _, row in df.iterrows():
            user_idx = self.user_mapping[row['user_id']]
            item_idx = self.item_mapping[row['product_id']]
            # スコア計算（購入回数と金額を考慮）
            score = row['purchase_count'] * np.log1p(row['avg_price'])
            matrix_data.append([user_idx, item_idx, score])
        
        matrix_df = pd.DataFrame(matrix_data, columns=['user', 'item', 'score'])
        
        # ピボットテーブル作成
        self.user_item_matrix = matrix_df.pivot_table(
            index='user', 
            columns='item', 
            values='score', 
            fill_value=0
        )
        
        logger.info(f"ユーザー-アイテム行列: {self.user_item_matrix.shape}")
        return self.user_item_matrix
    
    def generate_sample_data(self):
        """サンプルデータ生成（データがない場合）"""
        logger.info("サンプルデータ生成")
        
        np.random.seed(42)
        
        # ユーザーとアイテムの設定
        n_users = 100
        n_items = 50
        n_transactions = 500
        
        data = []
        for _ in range(n_transactions):
            user_id = np.random.randint(1001, 1001 + n_users)
            product_id = np.random.randint(2001, 2001 + n_items)
            quantity = np.random.randint(1, 5)
            price = np.random.uniform(500, 5000)
            purchase_count = np.random.randint(1, 3)
            
            data.append({
                'user_id': user_id,
                'product_id': product_id,
                'total_quantity': quantity,
                'avg_price': price,
                'purchase_count': purchase_count
            })
        
        return pd.DataFrame(data)
    
    def train(self):
        """モデル訓練"""
        logger.info("モデル訓練開始")
        
        # データ準備
        matrix = self.prepare_data()
        
        # データ正規化
        self.scaler = StandardScaler()
        scaled_matrix = self.scaler.fit_transform(matrix)
        
        # SVD次元削減
        n_components = min(50, min(matrix.shape) - 1)
        self.svd_model = TruncatedSVD(n_components=n_components, random_state=42)
        user_features = self.svd_model.fit_transform(scaled_matrix)
        
        # ユーザー特徴量を保存
        self.user_features = user_features
        
        # モデル評価（簡易）
        reconstructed = self.svd_model.inverse_transform(user_features)
        mse = np.mean((scaled_matrix - reconstructed) ** 2)
        logger.info(f"再構成MSE: {mse:.4f}")
        
        logger.info("モデル訓練完了")
        
    def get_recommendations(self, user_id, n_recommendations=5):
        """レコメンド生成"""
        if user_id not in self.user_mapping:
            # 新規ユーザーの場合、人気商品を返す
            return self.get_popular_items(n_recommendations)
        
        user_idx = self.user_mapping[user_id]
        user_vector = self.user_features[user_idx].reshape(1, -1)
        
        # 全ユーザーとの類似度計算
        similarities = cosine_similarity(user_vector, self.user_features)[0]
        
        # 類似ユーザー取得
        similar_users = np.argsort(similarities)[::-1][1:11]  # 上位10人
        
        # 類似ユーザーの購入履歴から推薦
        recommendations = {}
        for similar_user_idx in similar_users:
            similar_user_purchases = self.user_item_matrix.iloc[similar_user_idx]
            for item_idx, score in similar_user_purchases.items():
                if score > 0:  # 購入済み
                    if item_idx not in recommendations:
                        recommendations[item_idx] = 0
                    recommendations[item_idx] += score * similarities[similar_user_idx]
        
        # 既に購入済みの商品を除外
        user_purchases = self.user_item_matrix.iloc[user_idx]
        for item_idx in user_purchases[user_purchases > 0].index:
            recommendations.pop(item_idx, None)
        
        # スコア順でソート
        sorted_recommendations = sorted(
            recommendations.items(), 
            key=lambda x: x[1], 
            reverse=True
        )[:n_recommendations]
        
        # 商品IDに変換
        result = []
        for item_idx, score in sorted_recommendations:
            product_id = self.reverse_item_mapping[item_idx]
            result.append({
                'product_id': int(product_id),
                'score': float(score)
            })
        
        return result
    
    def get_popular_items(self, n_items=5):
        """人気商品取得（新規ユーザー向け）"""
        # アイテムの総購入スコア計算
        item_scores = self.user_item_matrix.sum(axis=0).sort_values(ascending=False)
        
        result = []
        for item_idx, score in item_scores.head(n_items).items():
            product_id = self.reverse_item_mapping[item_idx]
            result.append({
                'product_id': int(product_id),
                'score': float(score)
            })
        
        return result
    
    def save_model(self, model_path):
        """モデル保存"""
        logger.info(f"モデル保存: {model_path}")
        
        model_data = {
            'svd_model': self.svd_model,
            'scaler': self.scaler,
            'user_features': self.user_features,
            'user_mapping': self.user_mapping,
            'item_mapping': self.item_mapping,
            'reverse_user_mapping': self.reverse_user_mapping,
            'reverse_item_mapping': self.reverse_item_mapping,
            'user_item_matrix': self.user_item_matrix,
            'trained_at': datetime.now().isoformat()
        }
        
        joblib.dump(model_data, model_path)
        
    def load_model(self, model_path):
        """モデル読み込み"""
        logger.info(f"モデル読み込み: {model_path}")
        
        model_data = joblib.load(model_path)
        self.svd_model = model_data['svd_model']
        self.scaler = model_data['scaler']
        self.user_features = model_data['user_features']
        self.user_mapping = model_data['user_mapping']
        self.item_mapping = model_data['item_mapping']
        self.reverse_user_mapping = model_data['reverse_user_mapping']
        self.reverse_item_mapping = model_data['reverse_item_mapping']
        self.user_item_matrix = model_data['user_item_matrix']

def upload_to_gcs(local_path, gcs_path):
    """GCSにファイルアップロード"""
    storage_client = storage.Client(project=PROJECT_ID)
    bucket = storage_client.bucket(BUCKET_NAME)
    blob = bucket.blob(gcs_path)
    blob.upload_from_filename(local_path)
    logger.info(f"GCSアップロード完了: gs://{BUCKET_NAME}/{gcs_path}")

def main():
    """メイン訓練処理"""
    try:
        logger.info("レコメンドモデル訓練開始")
        
        # モデル初期化
        model = RecommendationModel()
        
        # 訓練実行
        model.train()
        
        # ローカル保存
        local_model_path = "recommend_model.pkl"
        model.save_model(local_model_path)
        
        # GCSにアップロード
        gcs_model_path = f"{MODEL_DIR}/recommend_model.pkl"
        upload_to_gcs(local_model_path, gcs_model_path)
        
        # テストレコメンド
        test_user_id = list(model.user_mapping.keys())[0] if model.user_mapping else 1001
        recommendations = model.get_recommendations(test_user_id)
        logger.info(f"テストレコメンド (user_id: {test_user_id}): {recommendations}")
        
        # モデル統計情報保存
        stats = {
            'n_users': len(model.user_mapping),
            'n_items': len(model.item_mapping),
            'matrix_shape': list(model.user_item_matrix.shape),
            'n_components': model.svd_model.n_components,
            'trained_at': datetime.now().isoformat()
        }
        
        stats_path = "model_stats.json"
        with open(stats_path, 'w') as f:
            json.dump(stats, f, indent=2)
        
        upload_to_gcs(stats_path, f"{MODEL_DIR}/model_stats.json")
        
        logger.info("モデル訓練完了")
        
    except Exception as e:
        logger.error(f"訓練エラー: {str(e)}")
        raise

if __name__ == "__main__":
    main()

# vertex-ai/training/requirements.txt

google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
google-cloud-aiplatform==1.38.1
pandas==2.1.4
numpy==1.24.4
scikit-learn==1.3.2
joblib==1.3.2
