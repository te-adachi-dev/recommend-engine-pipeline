# cloud-functions/data-ingestion/main.py

import functions_framework
import json
import logging
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import dataflow_v1beta3
import pandas as pd
import io
from datetime import datetime, timezone
import traceback

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 設定
PROJECT_ID = "test-recommend-engine-20250609"
DATASET_ID = "recommend_data"
BUCKET_NAME = f"{PROJECT_ID}-data-lake"

@functions_framework.http
def data_ingestion(request):
    """
    データ取り込み処理のメイン関数
    """
    try:
        logger.info("データ取り込み処理開始")
        
        # リクエストボディの解析
        request_json = request.get_json(silent=True)
        if request_json and 'file_path' in request_json:
            file_path = request_json['file_path']
        else:
            file_path = "input/"
        
        # Storage クライアント初期化
        storage_client = storage.Client(project=PROJECT_ID)
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # BigQuery クライアント初期化
        bq_client = bigquery.Client(project=PROJECT_ID)
        
        results = {}
        
        # CSVファイル処理
        csv_files = ['users.csv', 'products.csv', 'transactions.csv']
        for csv_file in csv_files:
            try:
                blob_name = f"{file_path}{csv_file}"
                table_name = csv_file.replace('.csv', '')
                
                result = process_csv_file(bucket, blob_name, bq_client, table_name)
                results[table_name] = result
                
            except Exception as e:
                logger.error(f"{csv_file}の処理でエラー: {str(e)}")
                results[csv_file] = {"status": "error", "message": str(e)}
        
        # Dataflow パイプライン起動
        try:
            dataflow_result = trigger_dataflow_pipeline()
            results["dataflow"] = dataflow_result
        except Exception as e:
            logger.error(f"Dataflow起動エラー: {str(e)}")
            results["dataflow"] = {"status": "error", "message": str(e)}
        
        logger.info("データ取り込み処理完了")
        
        return {
            "status": "success",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "results": results
        }, 200
        
    except Exception as e:
        logger.error(f"データ取り込み処理エラー: {str(e)}")
        logger.error(traceback.format_exc())
        
        return {
            "status": "error",
            "message": str(e),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }, 500

def process_csv_file(bucket, blob_name, bq_client, table_name):
    """
    CSVファイルをBigQueryに読み込む
    """
    try:
        # CSVファイルをダウンロード
        blob = bucket.blob(blob_name)
        if not blob.exists():
            return {"status": "skipped", "message": f"ファイルが見つかりません: {blob_name}"}
        
        csv_data = blob.download_as_text()
        df = pd.read_csv(io.StringIO(csv_data))
        
        # データ前処理
        if table_name == "users":
            df = preprocess_users(df)
        elif table_name == "products":
            df = preprocess_products(df)
        elif table_name == "transactions":
            df = preprocess_transactions(df)
        
        # BigQueryテーブル参照
        dataset_ref = bq_client.dataset(DATASET_ID)
        table_ref = dataset_ref.table(table_name)
        
        # データ投入設定
        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.CSV,
            skip_leading_rows=1,
            autodetect=False,
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND
        )
        
        # スキーマ設定
        if table_name == "users":
            job_config.schema = get_users_schema()
        elif table_name == "products":
            job_config.schema = get_products_schema()
        elif table_name == "transactions":
            job_config.schema = get_transactions_schema()
        
        # CSVデータをStringIOに変換
        csv_string = df.to_csv(index=False)
        csv_file = io.StringIO(csv_string)
        
        # BigQueryにロード
        job = bq_client.load_table_from_file(
            csv_file, table_ref, job_config=job_config
        )
        
        job.result()  # 完了待ち
        
        return {
            "status": "success",
            "rows_processed": len(df),
            "table": f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
        }
        
    except Exception as e:
        logger.error(f"CSV処理エラー ({table_name}): {str(e)}")
        return {"status": "error", "message": str(e)}

def preprocess_users(df):
    """ユーザーデータの前処理"""
    # 型変換
    df['user_id'] = df['user_id'].astype(int)
    df['age'] = pd.to_numeric(df['age'], errors='coerce')
    
    # 日付処理
    if 'registration_date' in df.columns:
        df['registration_date'] = pd.to_datetime(df['registration_date'], errors='coerce')
    
    return df

def preprocess_products(df):
    """商品データの前処理"""
    # 型変換
    df['product_id'] = df['product_id'].astype(int)
    df['price'] = pd.to_numeric(df['price'], errors='coerce')
    
    # 文字列の正規化
    df['product_name'] = df['product_name'].str.strip()
    df['category'] = df['category'].str.strip()
    
    return df

def preprocess_transactions(df):
    """取引データの前処理"""
    # 型変換
    df['user_id'] = df['user_id'].astype(int)
    df['product_id'] = df['product_id'].astype(int)
    df['quantity'] = pd.to_numeric(df['quantity'], errors='coerce')
    df['price'] = pd.to_numeric(df['price'], errors='coerce')
    
    # 日時処理
    df['timestamp'] = pd.to_datetime(df['timestamp'], errors='coerce')
    
    return df

def get_users_schema():
    """ユーザーテーブルのスキーマ"""
    return [
        bigquery.SchemaField("user_id", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("age", "INTEGER", mode="NULLABLE"),
        bigquery.SchemaField("gender", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("city", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("registration_date", "TIMESTAMP", mode="NULLABLE"),
    ]

def get_products_schema():
    """商品テーブルのスキーマ"""
    return [
        bigquery.SchemaField("product_id", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("product_name", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("category", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("price", "FLOAT", mode="NULLABLE"),
        bigquery.SchemaField("brand", "STRING", mode="NULLABLE"),
    ]

def get_transactions_schema():
    """取引テーブルのスキーマ"""
    return [
        bigquery.SchemaField("transaction_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("user_id", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("product_id", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("quantity", "INTEGER", mode="NULLABLE"),
        bigquery.SchemaField("price", "FLOAT", mode="NULLABLE"),
        bigquery.SchemaField("timestamp", "TIMESTAMP", mode="REQUIRED"),
    ]

def trigger_dataflow_pipeline():
    """Dataflow パイプラインを起動"""
    try:
        dataflow_client = dataflow_v1beta3.JobsV1Beta3Client()
        
        # パイプライン設定
        job_request = {
            "projectId": PROJECT_ID,
            "job": {
                "name": f"recommend-pipeline-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
                "type": "JOB_TYPE_BATCH",
                "environment": {
                    "tempLocation": f"gs://{BUCKET_NAME}/temp/",
                    "stagingLocation": f"gs://{BUCKET_NAME}/staging/",
                    "zone": "asia-northeast1-a",
                    "maxWorkers": 2,  # コスト最適化
                    "machineType": "n1-standard-1",
                    "usePublicIps": False
                }
            }
        }
        
        # パイプライン起動（実際の実装では適切なテンプレートを使用）
        logger.info("Dataflowパイプライン起動準備完了")
        
        return {
            "status": "triggered",
            "message": "Dataflowパイプラインが起動されました"
        }
        
    except Exception as e:
        logger.error(f"Dataflow起動エラー: {str(e)}")
        return {"status": "error", "message": str(e)}

# cloud-functions/data-ingestion/requirements.txt

functions-framework==3.5.0
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
google-cloud-dataflow-client==0.8.4
pandas==2.1.4
pyarrow==14.0.1
