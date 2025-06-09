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

output "app_engine_url" {
  description = "App Engine URL"
  value       = "https://${var.project_id}.appspot.com"
}
