terraform {
  required_version = ">= 1.6, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Projeto     = "curso-kubernetes"
      Ambiente    = "laboratorio"
      Modulo      = var.module_id
      ManagedBy   = "terraform"
      ClusterName = var.cluster_name
      Owner       = var.owner
      CostCenter  = var.cost_center
      LabRun      = var.lab_run
      ExpiresOn   = var.expires_on
    }
  }
}
