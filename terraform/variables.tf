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