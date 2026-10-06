terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # 값은 backend.hcl로 넘긴다: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "sky:managed-by"  = "sky-infra"
      "sky:environment" = local.environment
    }
  }
}

locals {
  environment = "dev"
  org         = var.github_org
}

data "aws_caller_identity" "current" {}

module "github_oidc" {
  source          = "../../modules/aws/github-oidc"
  name_prefix     = "sky-${local.environment}"
  create_provider = var.create_github_oidc_provider

  roles = {
    # PR에서 plan만 한다. 읽기 전용.
    infra-plan = {
      description         = "sky-infra PR plan (read-only)"
      subjects            = ["repo:${local.org}/sky-infra:pull_request"]
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
    # main 반영 후 GitHub environment 승인을 거친 작업만 apply한다.
    infra-apply = {
      description         = "sky-infra apply (environment-gated)"
      subjects            = ["repo:${local.org}/sky-infra:environment:${local.environment}"]
      managed_policy_arns = var.infra_apply_policy_arns
    }
  }
}

module "published_outputs" {
  source           = "../../modules/aws/published-outputs"
  environment      = local.environment
  contract_version = 1
  values = {
    "aws/region"     = var.region
    "aws/account_id" = data.aws_caller_identity.current.account_id
  }
}
