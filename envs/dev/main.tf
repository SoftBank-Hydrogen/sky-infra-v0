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
  region              = var.region
  allowed_account_ids = [var.aws_account_id] # 다른 계정 자격 증명으로는 실행되지 않도록
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
  name_prefix = "sky-${local.environment}"
  app_port    = 8080

  cluster_name = local.name_prefix
  service_name = "${local.name_prefix}-platform"

  # bootstrap/이 만드는 버킷 이름 규칙과 같다. 키는 backend.hcl과 CI의 key와 같아야 한다.
  state_bucket_name = "sky-tfstate-${var.aws_account_id}-${var.region}"
  state_key         = "envs/${local.environment}/terraform.tfstate"
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
    # sky-platform main 브랜치에서 서비스 서버 이미지를 ECR에 push만 한다.
    platform-deploy = {
      description = "sky-platform image push to ECR"
      subjects    = ["repo:${local.org}/sky-platform:ref:refs/heads/main"]
    }
    # sky-infra main에서 platform-image.auto.tfvars가 바뀌면 태스크 정의와 ECS 서비스만 적용한다.
    # job에 environment를 걸면 sub가 environment:로 바뀌어 assume되지 않는다.
    platform-release = {
      description = "sky-infra main: apply platform image (task definition and ECS service only)"
      subjects    = ["repo:${local.org}/sky-infra:ref:refs/heads/main"]
    }
  }

  # 키는 정적인 역할 이름. 값(정책 JSON)은 apply 전에 unknown이어도 된다.
  inline_policies = {
    platform-deploy  = module.iam.github_deploy_policy_json
    platform-release = module.iam.platform_release_policy_json
  }
}

module "published_outputs" {
  source           = "../../modules/aws/published-outputs"
  environment      = local.environment
  contract_version = 1
  values = {
    "aws/region"     = var.region
    "aws/account_id" = data.aws_caller_identity.current.account_id

    # sky-platform CI가 서비스 서버 이미지를 ECR에 push할 때 쓴다.
    "aws/platform_ecr_repository_url" = module.ecr.repository_url
    "aws/platform_deploy_role_arn"    = module.github_oidc.role_arns["platform-deploy"]
  }
}

# 재사용 모듈 (Fargate 승급시)
module "network" {
  source      = "../../modules/aws/network"
  name_prefix = local.name_prefix
  app_port    = local.app_port
}

module "edge" {
  source                = "../../modules/aws/edge"
  name_prefix           = local.name_prefix
  zone_name             = var.zone_name
  service_domain        = var.service_domain
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_port              = local.app_port
  health_check_path     = var.health_check_path
  enable_auth           = var.enable_auth
}

module "ecr" {
  source = "../../modules/aws/ecr"
}

module "secrets" {
  source      = "../../modules/aws/secrets"
  name_prefix = local.name_prefix
}

module "iam" {
  source                  = "../../modules/aws/iam"
  name_prefix             = local.name_prefix
  platform_repository_arn = module.ecr.repository_arn
  secret_arns             = values(module.secrets.secret_arns)
  log_group_name          = module.observability.log_group_name
  exec_log_group_name     = module.observability.exec_log_group_name
  cluster_name            = local.cluster_name
  service_name            = local.service_name
  state_bucket_name       = local.state_bucket_name
  state_key               = local.state_key
}

# A안 전용. B안에서 Fargate 모듈로 교체한다.
module "ecs" {
  source                = "../../modules/aws/ecs"
  name_prefix           = local.name_prefix
  cluster_name          = local.cluster_name
  service_name          = local.service_name
  vpc_id                = module.network.vpc_id
  app_subnet_ids        = module.network.app_subnet_ids
  app_security_group_id = module.network.app_security_group_id
  target_group_arn      = module.edge.target_group_arn
  alb_listener_arn      = module.edge.https_listener_arn
  instance_profile_name = module.iam.instance_profile_name
  execution_role_arn    = module.iam.execution_role_arn
  task_role_arn         = module.iam.task_role_arn
  instance_type         = var.instance_type
  image                 = "${module.ecr.repository_url}:${var.platform_image_tag}"
  container_port        = local.app_port
  log_group_name        = module.observability.log_group_name
  exec_log_group_name   = module.observability.exec_log_group_name

  environment = {
    SKY_AWS_REGION     = var.region
    SKY_AWS_ACCOUNT_ID = var.aws_account_id
  }
  secrets = {
    OPENAI_API_KEY              = module.secrets.secret_arns["openai-api-key"]
    SKY_GCP_SERVICE_ACCOUNT_KEY = module.secrets.secret_arns["gcp-service-account-key"]
  }
}

module "observability" {
  source                  = "../../modules/aws/observability"
  name_prefix             = local.name_prefix
  alb_arn_suffix          = module.edge.alb_arn_suffix
  target_group_arn_suffix = module.edge.target_group_arn_suffix
}
