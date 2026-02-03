variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "repo_name" {
  description = "Artifact Registry Repository Name"
  type        = string
  default     = "smart-chat-repo"
}

variable "service_name" {
  description = "Cloud Run Service Name"
  type        = string
  default     = "gateway-api"
}

variable "gemini_api_key" {
  description = "Gemini API Key"
  type        = string
  sensitive   = true
}

variable "gemini_model_name" {
  description = "Gemini Model Name"
  type        = string
  default     = "gemini-3-flash-preview"
}
