# terraform/main.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Cloud Storage バケット
resource "google_storage_bucket" "data_lake" {
  name     = "${var.project_id}-data-lake"
  location = var.region
  
  # コスト最適化
  storage_class = "STANDARD"
  
  # 自動削除設定
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # バージョニング無効
  versioning {
    enabled = false
  }
  
  # 強制削除許可
  force_destroy = true
}

# BigQuery データセット
resource "google_bigquery_dataset" "recommend_dataset" {
  dataset_id  = "recommend_data"
  description = "レコメンド用データセット"
  location    = var.region
  
  # データ保持期間設定（コスト最適化）
  default_table_expiration_ms = 2592000000 # 30日
  
  # アクセス制御を修正
  access {
    role          = "OWNER"
    user_by_email = var.service_account_email
  }
  
  # プロジェクトエディターにも権限付与
  access {
    role         = "OWNER"
    special_group = "projectOwners"
  }
  
  access {
    role         = "WRITER"
    special_group = "projectEditors"
  }
}

# BigQuery テーブル - ユーザー
resource "google_bigquery_table" "users" {
  dataset_id = google_bigquery_dataset.recommend_dataset.dataset_id
  table_id   = "users"
  
  schema = jsonencode([
    {
      name = "user_id"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "age"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "gender"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "city"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "registration_date"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    }
  ])
}

# BigQuery テーブル - 商品
resource "google_bigquery_table" "products" {
  dataset_id = google_bigquery_dataset.recommend_dataset.dataset_id
  table_id   = "products"
  
  schema = jsonencode([
    {
      name = "product_id"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "product_name"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "category"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "price"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "brand"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}

# BigQuery テーブル - 取引
resource "google_bigquery_table" "transactions" {
  dataset_id = google_bigquery_dataset.recommend_dataset.dataset_id
  table_id   = "transactions"
  
  schema = jsonencode([
    {
      name = "transaction_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "user_id"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "product_id"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "quantity"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "price"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    }
  ])
}

# Cloud Functions用のサービスアカウント
resource "google_service_account" "cloud_functions_sa" {
  account_id   = "cloud-functions-sa"
  display_name = "Cloud Functions Service Account"
}

# Cloud Functions用のIAM
resource "google_project_iam_member" "cloud_functions_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cloud_functions_sa.email}"
}

resource "google_project_iam_member" "cloud_functions_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.cloud_functions_sa.email}"
}

# Dataflow用のサービスアカウント
resource "google_service_account" "dataflow_sa" {
  account_id   = "dataflow-sa"
  display_name = "Dataflow Service Account"
}

resource "google_project_iam_member" "dataflow_worker" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "dataflow_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "dataflow_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Vertex AI用のサービスアカウント
resource "google_service_account" "vertex_ai_sa" {
  account_id   = "vertex-ai-sa"
  display_name = "Vertex AI Service Account"
}

resource "google_project_iam_member" "vertex_ai_admin" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.vertex_ai_sa.email}"
}

resource "google_project_iam_member" "vertex_ai_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.vertex_ai_sa.email}"
}

# App Engine アプリケーション
resource "google_app_engine_application" "app" {
  project     = var.project_id
  location_id = var.app_engine_location
  
  # 課金設定
  serving_status = "SERVING"
}

# Artifact Registry（Dockerイメージ用）
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "recommend-engine"
  description   = "レコメンドエンジン用Dockerリポジトリ"
  format        = "DOCKER"
}

# Cloud Scheduler（定期実行用）
resource "google_cloud_scheduler_job" "daily_pipeline" {
  name        = "daily-recommend-pipeline"
  description = "毎日のレコメンドパイプライン実行"
  schedule    = "0 2 * * *" # 毎日午前2時
  time_zone   = "Asia/Tokyo"
  
  http_target {
    http_method = "POST"
    uri         = "https://asia-northeast1-${var.project_id}.cloudfunctions.net/data-ingestion"
  }
}

