# Output values for Smart Chat App infrastructure

output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.gateway.uri
}

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repo_name}"
}

output "firebase_project" {
  description = "Firebase project ID"
  value       = google_firebase_project.default.project
}

output "firebase_hosting_url" {
  description = "Firebase Hosting URL for the web app"
  value       = "https://${google_firebase_hosting_site.default.site_id}.web.app"
}

output "firebase_hosting_site_id" {
  description = "Firebase Hosting site ID"
  value       = google_firebase_hosting_site.default.site_id
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    backend_url  = google_cloud_run_v2_service.gateway.uri
    frontend_url = "https://${google_firebase_hosting_site.default.site_id}.web.app"
    deployed_at  = timestamp()
  }
  depends_on = [
    null_resource.docker_build,
    null_resource.firebase_deploy
  ]
}

output "env_variables_for_local_dev" {
  description = "Environment variables needed for local development"
  value = {
    GOOGLE_PROJECT_ID     = var.project_id
    GOOGLE_CLOUD_LOCATION = "global"
    GEMINI_MODEL_NAME     = var.gemini_model_name
    GEMINI_API_KEY        = "***SENSITIVE***"
  }
  sensitive = true
}
