# app-engine/main.py

import os
import logging
from flask import Flask, request, jsonify
from google.cloud import storage
from google.cloud import bigquery
import joblib
import json
from datetime import datetime, timezone
import tempfile
from functools import lru_cache
import traceback

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Flask アプリ初期化
app = Flask(__name__)

# 設定
PROJECT_ID = "test-recommend-engine-20250609"
DATASET_ID = "recommend_data"
BUCKET_NAME = f"{PROJECT_ID}-data-lake"
MODEL_PATH = "models/recommend_model.pkl"

# グローバル変数
model = None
product_cache = {}

class RecommendationAPI:
    """レコメンドAPI"""
    
    def __init__(self):
        self.model = None
        self.bq_client = bigquery.Client(project=PROJECT_ID)
        self.storage_client = storage.Client(project=PROJECT_ID)
        
    def load_model(self):
        """モデル読み込み"""
        if self.model is not None:
            return self.model
            
        try:
            logger.info("モデル読み込み開始")
            
            # GCSからモデルダウンロード
            bucket = self.storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(MODEL_PATH)
            
            if not blob.exists():
                logger.warning("モデルファイルが見つかりません。ダミーモデルを使用します。")
                return self.create_dummy_model()
            
            # 一時ファイルにダウンロード
            with tempfile.NamedTemporaryFile(delete=False, suffix='.pkl') as tmp_file:
                blob.download_to_filename(tmp_file.name)
                model_data = joblib.load(tmp_file.name)
                os.unlink(tmp_file.name)
            
            # モデルデータを復元
            self.model = {
                'svd_model': model_data['svd_model'],
                'scaler': model_data['scaler'],
                'user_features': model_data['user_features'],
                'user_mapping': model_data['user_mapping'],
                'item_mapping': model_data['item_mapping'],
                'reverse_user_mapping': model_data['reverse_user_mapping'],
                'reverse_item_mapping': model_data['reverse_item_mapping'],
                'user_item_matrix': model_data['user_item_matrix'],
                'trained_at': model_data.get('trained_at', 'unknown')
            }
            
            logger.info(f"モデル読み込み完了: {self.model['trained_at']}")
            return self.model
            
        except Exception as e:
            logger.error(f"モデル読み込みエラー: {str(e)}")
            return self.create_dummy_model()
    
    def create_dummy_model(self):
        """ダミーモデル作成"""
        logger.info("ダミーモデル作成")
        
        self.model = {
            'dummy': True,
            'popular_items': [2001, 2002, 2003, 2004, 2005],
            'trained_at': datetime.now(timezone.utc).isoformat()
        }
        return self.model
    
    def get_recommendations(self, user_id, n_recommendations=5):
        """レコメンド取得"""
        model = self.load_model()
        
        if model.get('dummy'):
            # ダミーモデルの場合
            return [
                {'product_id': pid, 'score': 1.0 - i * 0.1} 
                for i, pid in enumerate(model['popular_items'][:n_recommendations])
            ]
        
        try:
            # 実際のモデルでレコメンド
            from sklearn.metrics.pairwise import cosine_similarity
            import numpy as np
            
            if user_id not in model['user_mapping']:
                # 新規ユーザーの場合、人気商品を返す
                return self.get_popular_items(n_recommendations)
            
            user_idx = model['user_mapping'][user_id]
            user_vector = model['user_features'][user_idx].reshape(1, -1)
            
            # 全ユーザーとの類似度計算
            similarities = cosine_similarity(user_vector, model['user_features'])[0]
            
            # 類似ユーザー取得
            similar_users = np.argsort(similarities)[::-1][1:11]  # 上位10人
            
            # 類似ユーザーの購入履歴から推薦
            recommendations = {}
            for similar_user_idx in similar_users:
                similar_user_purchases = model['user_item_matrix'].iloc[similar_user_idx]
                for item_idx, score in similar_user_purchases.items():
                    if score > 0:  # 購入済み
                        if item_idx not in recommendations:
                            recommendations[item_idx] = 0
                        recommendations[item_idx] += score * similarities[similar_user_idx]
            
            # 既に購入済みの商品を除外
            user_purchases = model['user_item_matrix'].iloc[user_idx]
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
                product_id = model['reverse_item_mapping'][item_idx]
                result.append({
                    'product_id': int(product_id),
                    'score': float(score)
                })
            
            return result
            
        except Exception as e:
            logger.error(f"レコメンド生成エラー: {str(e)}")
            return self.get_popular_items(n_recommendations)
    
    def get_popular_items(self, n_items=5):
        """人気商品取得"""
        model = self.load_model()
        
        if model.get('dummy'):
            return [
                {'product_id': pid, 'score': 1.0 - i * 0.1} 
                for i, pid in enumerate(model['popular_items'][:n_items])
            ]
        
        try:
            # アイテムの総購入スコア計算
            item_scores = model['user_item_matrix'].sum(axis=0).sort_values(ascending=False)
            
            result = []
            for item_idx, score in item_scores.head(n_items).items():
                product_id = model['reverse_item_mapping'][item_idx]
                result.append({
                    'product_id': int(product_id),
                    'score': float(score)
                })
            
            return result
            
        except Exception as e:
            logger.error(f"人気商品取得エラー: {str(e)}")
            # フォールバック
            return [
                {'product_id': 2001 + i, 'score': 1.0 - i * 0.1} 
                for i in range(n_items)
            ]

# API インスタンス
recommend_api = RecommendationAPI()

@lru_cache(maxsize=100)
def get_product_info(product_id):
    """商品情報取得（キャッシュ付き）"""
    try:
        query = f"""
        SELECT product_id, product_name, category, price, brand
        FROM `{PROJECT_ID}.{DATASET_ID}.products`
        WHERE product_id = {product_id}
        LIMIT 1
        """
        
        result = recommend_api.bq_client.query(query).to_dataframe()
        if len(result) > 0:
            return result.iloc[0].to_dict()
        else:
            # ダミー商品情報
            return {
                'product_id': product_id,
                'product_name': f'テスト商品{product_id}',
                'category': 'テストカテゴリ',
                'price': 1000.0,
                'brand': 'テストブランド'
            }
    except Exception as e:
        logger.error(f"商品情報取得エラー: {str(e)}")
        return {
            'product_id': product_id,
            'product_name': f'商品{product_id}',
            'category': 'unknown',
            'price': 0.0,
            'brand': 'unknown'
        }

# API エンドポイント

@app.route('/')
def index():
    """ヘルスチェック"""
    return jsonify({
        'status': 'ok',
        'service': 'レコメンドエンジンAPI',
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'endpoints': [
            '/recommend',
            '/popular',
            '/health',
            '/model-info'
        ]
    })

@app.route('/health')
def health():
    """詳細ヘルスチェック"""
    try:
        # モデル読み込みテスト
        model = recommend_api.load_model()
        model_status = 'loaded' if model else 'failed'
        
        return jsonify({
            'status': 'healthy',
            'model_status': model_status,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'project_id': PROJECT_ID
        })
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 500

@app.route('/model-info')
def model_info():
    """モデル情報取得"""
    try:
        model = recommend_api.load_model()
        
        if model.get('dummy'):
            return jsonify({
                'model_type': 'dummy',
                'trained_at': model['trained_at'],
                'description': 'ダミーモデル（テスト用）'
            })
        
        return jsonify({
            'model_type': 'collaborative_filtering',
            'trained_at': model['trained_at'],
            'n_users': len(model['user_mapping']),
            'n_items': len(model['item_mapping']),
            'matrix_shape': list(model['user_item_matrix'].shape),
            'n_components': model['svd_model'].n_components
        })
        
    except Exception as e:
        return jsonify({
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 500

@app.route('/recommend')
def recommend():
    """レコメンド取得"""
    try:
        # パラメータ取得
        user_id = request.args.get('user_id', type=int)
        n_recommendations = request.args.get('n_recommendations', default=5, type=int)
        include_product_info = request.args.get('include_product_info', default='true').lower() == 'true'
        
        if not user_id:
            return jsonify({
                'error': 'user_idパラメータが必要です',
                'example': '/recommend?user_id=1001'
            }), 400
        
        if n_recommendations <= 0 or n_recommendations > 20:
            return jsonify({
                'error': 'n_recommendationsは1〜20の範囲で指定してください'
            }), 400
        
        # レコメンド生成
        recommendations = recommend_api.get_recommendations(user_id, n_recommendations)
        
        # 商品情報付与（オプション）
        if include_product_info:
            for rec in recommendations:
                product_info = get_product_info(rec['product_id'])
                rec['product_info'] = product_info
        
        return jsonify({
            'user_id': user_id,
            'recommendations': recommendations,
            'count': len(recommendations),
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"レコメンドエラー: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({
            'error': 'レコメンド生成に失敗しました',
            'details': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 500

@app.route('/popular')
def popular():
    """人気商品取得"""
    try:
        # パラメータ取得
        n_items = request.args.get('n_items', default=10, type=int)
        include_product_info = request.args.get('include_product_info', default='true').lower() == 'true'
        
        if n_items <= 0 or n_items > 50:
            return jsonify({
                'error': 'n_itemsは1〜50の範囲で指定してください'
            }), 400
        
        # 人気商品取得
        popular_items = recommend_api.get_popular_items(n_items)
        
        # 商品情報付与（オプション）
        if include_product_info:
            for item in popular_items:
                product_info = get_product_info(item['product_id'])
                item['product_info'] = product_info
        
        return jsonify({
            'popular_items': popular_items,
            'count': len(popular_items),
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"人気商品取得エラー: {str(e)}")
        return jsonify({
            'error': '人気商品取得に失敗しました',
            'details': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 500

@app.route('/user-profile')
def user_profile():
    """ユーザープロファイル取得"""
    try:
        user_id = request.args.get('user_id', type=int)
        
        if not user_id:
            return jsonify({
                'error': 'user_idパラメータが必要です'
            }), 400
        
        # ユーザー情報取得
        user_query = f"""
        SELECT user_id, age, gender, city, registration_date
        FROM `{PROJECT_ID}.{DATASET_ID}.users`
        WHERE user_id = {user_id}
        LIMIT 1
        """
        
        user_result = recommend_api.bq_client.query(user_query).to_dataframe()
        
        if len(user_result) == 0:
            return jsonify({
                'error': 'ユーザーが見つかりません',
                'user_id': user_id
            }), 404
        
        # 購入履歴取得
        purchase_query = f"""
        SELECT 
            t.product_id,
            p.product_name,
            p.category,
            SUM(t.quantity) as total_quantity,
            AVG(t.price) as avg_price,
            COUNT(*) as purchase_count,
            MAX(t.timestamp) as last_purchase
        FROM `{PROJECT_ID}.{DATASET_ID}.transactions` t
        LEFT JOIN `{PROJECT_ID}.{DATASET_ID}.products` p ON t.product_id = p.product_id
        WHERE t.user_id = {user_id}
        GROUP BY t.product_id, p.product_name, p.category
        ORDER BY purchase_count DESC, last_purchase DESC
        LIMIT 10
        """
        
        purchase_result = recommend_api.bq_client.query(purchase_query).to_dataframe()
        
        user_info = user_result.iloc[0].to_dict()
        purchase_history = purchase_result.to_dict('records') if len(purchase_result) > 0 else []
        
        return jsonify({
            'user_info': user_info,
            'purchase_history': purchase_history,
            'purchase_summary': {
                'total_products': len(purchase_history),
                'total_purchases': int(purchase_result['purchase_count'].sum()) if len(purchase_result) > 0 else 0
            },
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
        
    except Exception as e:
        logger.error(f"ユーザープロファイル取得エラー: {str(e)}")
        return jsonify({
            'error': 'ユーザープロファイル取得に失敗しました',
            'details': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 500

if __name__ == '__main__':
    # 開発環境での実行
    app.run(host='127.0.0.1', port=8080, debug=True)

# app-engine/app.yaml

runtime: python39

service: default

basic_scaling:
  max_instances: 2
  idle_timeout: 10m

resources:
  cpu: 1
  memory_gb: 0.5
  disk_size_gb: 10

automatic_scaling:
  min_instances: 0
  max_instances: 2
  target_cpu_utilization: 0.6

env_variables:
  GOOGLE_CLOUD_PROJECT: test-recommend-engine-20250609

# app-engine/requirements.txt

Flask==3.0.0
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
pandas==2.1.4
numpy==1.24.4
scikit-learn==1.3.2
joblib==1.3.2
gunicorn==21.2.0
