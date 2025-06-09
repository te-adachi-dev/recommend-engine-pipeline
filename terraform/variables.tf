# terraform/variables.tf

variable "project_id" {
  description = "GCPプロジェクトID"
  type        = string
  default     = "test-recommend-engine-20250609"
}

variable "region" {
  description = "GCPリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "GCPゾーン"
  type        = string
  default     = "asia-northeast1-a"
}

variable "app_engine_location" {
  description = "App Engineのロケーション"
  type        = string
  default     = "asia-northeast1"
}

variable "service_account_email" {
  description = "サービスアカウントのEメール"
  type        = string
  default     = "terraform-sa@test-recommend-engine-20250609.iam.gserviceaccount.com"
}

variable "environment" {
  description = "環境名"
  type        = string
  default     = "dev"
}

variable "cost_threshold" {
  description = "コストアラートの閾値（USD）"
  type        = number
  default     = 10.0
}

# terraform/outputs.tf

output "project_id" {
  description = "プロジェクトID"
  value       = var.project_id
}

output "bucket_name" {
  description = "データレイクバケット名"
  value       = google_storage_bucket.data_lake.name
}

output "dataset_id" {
  description = "BigQueryデータセットID"
  value       = google_bigquery_dataset.recommend_dataset.dataset_id
}

output "cloud_functions_sa_email" {
  description = "Cloud Functions サービスアカウント"
  value       = google_service_account.cloud_functions_sa.email
}

output "dataflow_sa_email" {
  description = "Dataflow サービスアカウント"
  value       = google_service_account.dataflow_sa.email
}

output "vertex_ai_sa_email" {
  description = "Vertex AI サービスアカウント"
  value       = google_service_account.vertex_ai_sa.email
}

output "artifact_registry_url" {
  description = "Artifact Registry URL"
  value       = google_artifact_registry_repository.docker_repo.name
}

output "app_engine_url" {
  description = "App Engine URL"
  value       = "https://${var.project_id}.appspot.com"
}

# terraform/terraform.tfvars.example

# プロジェクト設定
project_id = "test-recommend-engine-20250609"
region     = "asia-northeast1"
zone       = "asia-northeast1-a"

# App Engine設定
app_engine_location = "asia-northeast1"

# サービスアカウント
service_account_email = "terraform-sa@test-recommend-engine-20250609.iam.gserviceaccount.com"

# 環境設定
environment = "dev"

# コスト設定
cost_threshold = 10.0
