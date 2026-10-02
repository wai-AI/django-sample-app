terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
  required_version = ">= 1.11.0"
}

provider "aws" {
  region = var.aws_region
}