# 빈 계정 첫 plan 회귀 검사. 자격 증명 없이 mock provider로 plan만 한다.
# 계산값(ID, ARN)이 unknown인 상태에서 for_each/count 키가 정해지는지 확인한다.
# 실행: terraform -chdir=envs/dev init -backend=false && terraform -chdir=envs/dev test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-2", name = "ap-northeast-2" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  aws_account_id          = "123456789012"
  infra_apply_policy_arns = []
  platform_image_tag      = "0000000" # platform-image.auto.tfvars 값과 무관하게 돈다
}

run "first_plan" {
  command = plan
}
