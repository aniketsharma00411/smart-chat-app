terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable APIs
resource "google_project_service" "cloudrun_api" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry_api" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Artifact Registry Repository
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.repo_name

  description = "Docker repository for Smart Chat App"
  format      = "DOCKER"

  depends_on = [google_project_service.artifactregistry_api]
}

# Cloud Run Service
# Note: In a real CI/CD, the image is built and pushed first. 
# For Terraform to pass initial validation, we might need a placeholder or 
# rely on the user to build/push before applying this resource fully, 
# or use a null_resource to build it (simplest for hackathons).

resource "null_resource" "docker_build" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<EOT
      gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
      docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${var.repo_name}/${var.service_name}:latest ../backend --platform linux/amd64
      docker push ${var.region}-docker.pkg.dev/${var.project_id}/${var.repo_name}/${var.service_name}:latest
    EOT
  }

  depends_on = [google_artifact_registry_repository.repo]
}

resource "google_cloud_run_v2_service" "gateway" {
  name                = var.service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    containers {
      # This image path assumes you will push to this location tag.
      # Format: region-docker.pkg.dev/project_id/repo_name/image_name:tag
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repo_name}/${var.service_name}:latest"

      env {
        name  = "GEMINI_MODEL_NAME"
        value = var.gemini_model_name
      }

      # Secrets should ideally be in Secret Manager, but for hackathon:
      env {
        name  = "GEMINI_API_KEY"
        value = var.gemini_api_key
      }
    }
  }

  depends_on = [google_project_service.cloudrun_api, null_resource.docker_build]
}

# Allow unauthenticated invocations (public API for hackathon demo)
resource "google_cloud_run_service_iam_binding" "default" {
  location = google_cloud_run_v2_service.gateway.location
  service  = google_cloud_run_v2_service.gateway.name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}

output "service_url" {
  value = google_cloud_run_v2_service.gateway.uri
}
