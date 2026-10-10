# [IAM] 서비스 서버(Sky)가 쓰는 IAM 역할

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition

  log_group_arn      = "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${var.log_group_name}"
  exec_log_group_arn = "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${var.exec_log_group_name}"

  managed_role_arns = [
    "arn:${local.partition}:iam::${local.account}:role/sky-core-*",
    "arn:${local.partition}:iam::${local.account}:role/sky-db-*",
  ]
  managed_stack_arns = [
    "arn:${local.partition}:cloudformation:${local.region}:${local.account}:stack/sky-core/*",
    "arn:${local.partition}:cloudformation:${local.region}:${local.account}:stack/sky-db-*/*",
    "arn:${local.partition}:cloudformation:${local.region}:${local.account}:stack/sky-network-*/*",
  ]
  managed_repository_arn = "arn:${local.partition}:ecr:${local.region}:${local.account}:repository/sky-managed"
  default_cluster_arn    = "arn:${local.partition}:ecs:${local.region}:${local.account}:cluster/default"

  # sky-platform CloudFormation 템플릿이 역할에 붙이는 관리형 정책. 이 외의 정책은 붙일 수 없다.
  attachable_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices",
  ]
}

# ---------------------------------------------------------------------------
# EC2 인스턴스 역할
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-ecs-instance"
  description        = "Sky ECS container instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = toset([
    "arn:${local.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-ecs-instance"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------------------
# 태스크 실행 역할 (ECS 에이전트가 쓴다)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-task-execution"
  description        = "Sky task execution: image pull, logs, secret injection"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid       = "PullPlatformImage"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = [var.platform_repository_arn]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_group_arn}:*"]
  }
  statement {
    sid       = "ReadInjectedSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name_prefix}-task-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ---------------------------------------------------------------------------
# Sky 태스크 역할 (sky-platform 프로세스가 쓴다)
# 이름이 sky-core-*, sky-db-* 와 겹치지 않게 해 자기 역할을 고칠 수 없게 한다.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-platform-task"
  description        = "Sky service server: creates and removes deployed apps"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

# 1) CloudFormation·ECS Express·ECR(sky-managed)
data "aws_iam_policy_document" "task_deploy" {
  statement {
    sid = "ManagedStacks"
    actions = [
      "cloudformation:CreateStack",
      "cloudformation:DeleteStack",
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackEvents",
      "cloudformation:ListStackResources",
      "cloudformation:UpdateTerminationProtection",
      "cloudformation:CreateChangeSet",
      "cloudformation:DescribeChangeSet",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:DeleteChangeSet",
      "cloudformation:TagResource",
    ]
    resources = concat(
      local.managed_stack_arns,
      ["arn:${local.partition}:cloudformation:${local.region}:${local.account}:changeSet/*"],
    )
  }
  statement {
    sid       = "StackReadOnly"
    actions   = ["cloudformation:ListStacks", "cloudformation:GetTemplateSummary", "cloudformation:ValidateTemplate"]
    resources = ["*"]
  }

  statement {
    sid = "ExpressServices"
    actions = [
      "ecs:CreateExpressGatewayService",
      "ecs:UpdateExpressGatewayService",
      "ecs:DeleteExpressGatewayService",
      "ecs:DescribeExpressGatewayService",
      "ecs:ListServiceDeployments",
      "ecs:DescribeServiceDeployments",
      "ecs:DescribeServiceRevisions",
      "ecs:StopServiceDeployment",
    ]
    resources = [
      local.default_cluster_arn,
      "arn:${local.partition}:ecs:${local.region}:${local.account}:service/default/sky-*",
      "arn:${local.partition}:ecs:${local.region}:${local.account}:service-deployment/default/sky-*/*",
      "arn:${local.partition}:ecs:${local.region}:${local.account}:service-revision/default/sky-*/*",
    ]
  }
  statement {
    sid       = "ExpressDefaultCluster"
    actions   = ["ecs:CreateCluster"]
    resources = [local.default_cluster_arn]
  }
  statement {
    sid = "OneOffTasks"
    # 마이그레이션(sky-migrate-*)과 복원 검사(sky-restore-verify-*) 태스크만 default 클러스터에서 실행한다.
    actions = ["ecs:RunTask"]
    resources = [
      "arn:${local.partition}:ecs:${local.region}:${local.account}:task-definition/sky-migrate-*:*",
      "arn:${local.partition}:ecs:${local.region}:${local.account}:task-definition/sky-restore-verify-*:*",
    ]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [local.default_cluster_arn]
    }
  }
  statement {
    sid       = "RegisterOwnedTaskDefinitions"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/sky-managed"
      values   = ["true"]
    }
  }
  statement {
    sid       = "TagOnCreate"
    actions   = ["ecs:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["CreateExpressGatewayService", "RunTask", "RegisterTaskDefinition"]
    }
  }
  statement {
    sid = "EcsReadOnly"
    # 아래 작업은 자원 수준 제한을 지원하지 않거나 조회 전용이다.
    actions = [
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:ListServices",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "ManagedRepository"
    # sky-core 스택이 레포를 만들고, Sky가 사용자 앱 이미지를 푸시·정리한다.
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:PutImageScanningConfiguration",
      "ecr:TagResource",
      "ecr:ListTagsForResource",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:ListImages",
      "ecr:BatchDeleteImage",
    ]
    resources = [local.managed_repository_arn]
  }

  statement {
    sid       = "RdsPricing"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }
}

# 2) RDS·보안 그룹·로그·RDS 관리 비밀
data "aws_iam_policy_document" "task_data" {
  statement {
    sid = "ManagedDatabases"
    actions = [
      "rds:CreateDBInstance",
      "rds:ModifyDBInstance",
      "rds:DeleteDBInstance",
      "rds:CreateDBSnapshot",
      "rds:RestoreDBInstanceFromDBSnapshot",
      "rds:CreateDBSubnetGroup",
      "rds:ModifyDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:AddTagsToResource",
      "rds:ListTagsForResource",
    ]
    resources = [
      "arn:${local.partition}:rds:${local.region}:${local.account}:db:sky-*",
      "arn:${local.partition}:rds:${local.region}:${local.account}:snapshot:sky-*",
      "arn:${local.partition}:rds:${local.region}:${local.account}:subgrp:sky-db-*",
      "arn:${local.partition}:rds:${local.region}:${local.account}:og:default*",
      "arn:${local.partition}:rds:${local.region}:${local.account}:pg:default*",
    ]
  }
  statement {
    sid       = "DeleteAutomatedBackups"
    actions   = ["rds:DeleteDBInstanceAutomatedBackup"]
    resources = ["arn:${local.partition}:rds:${local.region}:${local.account}:auto-backup:*"]
  }
  statement {
    sid = "RdsReadOnly"
    actions = [
      "rds:DescribeDBInstances",
      "rds:DescribeDBSnapshots",
      "rds:DescribeDBSubnetGroups",
      "rds:DescribeDBEngineVersions",
      "rds:DescribeOrderableDBInstanceOptions",
    ]
    resources = ["*"]
  }
  statement {
    sid = "RdsManagedMasterSecret"
    # ManageMasterUserPassword: RDS가 호출자 권한으로 rds!* 비밀을 만들고 지운다.
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:TagResource",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = ["arn:${local.partition}:secretsmanager:${local.region}:${local.account}:secret:rds!*"]
  }
  statement {
    sid       = "RdsManagedMasterSecretKey"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  statement {
    sid = "Ec2ReadOnly"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]
  }
  statement {
    sid     = "CreateSecurityGroups"
    actions = ["ec2:CreateSecurityGroup"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:${local.account}:vpc/*",
      "arn:${local.partition}:ec2:${local.region}:${local.account}:security-group/*",
    ]
  }
  statement {
    sid       = "TagSecurityGroupsOnCreate"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account}:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
  }
  statement {
    sid = "ChangeOwnedSecurityGroups"
    # sky-managed=true 표식이 있는 그룹만 고치고 지운다. 서비스 서버 자체의 그룹은 해당하지 않는다.
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DeleteSecurityGroup",
    ]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account}:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/sky-managed"
      values   = ["true"]
    }
  }

  statement {
    sid = "MigrationLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:TagLogGroup",
      "logs:ListTagsForResource",
      "logs:GetLogEvents",
    ]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account}:log-group:/sky/migrations/*"]
  }
  statement {
    sid       = "LogsReadOnly"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

# 3) 배포 서버용 IAM 역할 (sky-core, sky-db 스택) + ECS Exec
data "aws_iam_policy_document" "task_iam" {
  statement {
    sid = "ManagedRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:DetachRolePolicy",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = local.managed_role_arns
  }
  statement {
    sid       = "AttachKnownPoliciesOnly"
    actions   = ["iam:AttachRolePolicy"]
    resources = local.managed_role_arns
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = local.attachable_policy_arns
    }
  }
  statement {
    sid       = "PassManagedRolesToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = local.managed_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"]
    }
  }
  statement {
    sid       = "ServiceLinkedRolesOnFirstUse"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account}:role/aws-service-role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "ecs.application-autoscaling.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }

  # 권한 상승 경로를 명시적으로 막는다. Allow보다 우선한다.
  statement {
    sid       = "DenyAssumeManagedRoles"
    effect    = "Deny"
    actions   = ["sts:AssumeRole"]
    resources = local.managed_role_arns
  }
  statement {
    sid    = "DenyTrustAndBoundaryChanges"
    effect = "Deny"
    actions = [
      "iam:UpdateAssumeRolePolicy",
      "iam:DeleteRolePermissionsBoundary",
      "iam:CreatePolicyVersion",
    ]
    resources = ["*"]
  }

  statement {
    sid = "EcsExecChannel"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "EcsExecSessionLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${local.exec_log_group_arn}:*"]
  }
}

resource "aws_iam_policy" "task" {
  for_each = {
    deploy = data.aws_iam_policy_document.task_deploy.json
    data   = data.aws_iam_policy_document.task_data.json
    iam    = data.aws_iam_policy_document.task_iam.json
  }
  name        = "${var.name_prefix}-platform-task-${each.key}"
  description = "Sky platform task role (${each.key})"
  policy      = each.value
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each   = aws_iam_policy.task
  role       = aws_iam_role.task.name
  policy_arn = each.value.arn
}

# ---------------------------------------------------------------------------
# GitHub Actions 배포 역할의 권한 (역할 자체는 github-oidc 모듈이 만든다)
# sky-platform CI는 이미지 push만 한다. 배포는 sky-infra의 platform-image.auto.tfvars 변경으로 한다.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "PushPlatformImage"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
    ]
    resources = [var.platform_repository_arn]
  }
}

# ---------------------------------------------------------------------------
# sky-infra 이미지 배포 역할의 권한 (역할 자체는 github-oidc 모듈이 만든다)
# platform-image.auto.tfvars 변경이 main에 머지되면 태스크 정의와 ECS 서비스만 -target으로 적용한다.
# ---------------------------------------------------------------------------

locals {
  state_bucket_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  state_object_arn = "${local.state_bucket_arn}/${var.state_key}"
}

data "aws_iam_policy_document" "platform_release" {
  statement {
    sid = "StateList"
    # init이 워크스페이스 목록을 조회할 수 있어 접두어 조건을 걸지 않는다. 노출되는 것은 키 이름뿐이다.
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }
  statement {
    sid       = "StateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [local.state_object_arn]
  }
  statement {
    sid       = "StateLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_object_arn}.tflock"]
  }

  # 쓰기: 태스크 정의 등록과 서비스 갱신만
  statement {
    sid = "RegisterTaskDefinition"
    # RegisterTaskDefinition은 자원 수준 권한을 지원하지 않는다.
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }
  statement {
    sid       = "TagTaskDefinitionOnRegister"
    actions   = ["ecs:TagResource"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account}:task-definition/${var.service_name}:*"]
    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition"]
    }
  }
  statement {
    sid       = "UpdatePlatformService"
    actions   = ["ecs:UpdateService"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account}:service/${var.cluster_name}/${var.service_name}"]
  }
  statement {
    sid       = "PassPlatformRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # 배포 전 이미지 존재 확인
  statement {
    sid       = "CheckPlatformImage"
    actions   = ["ecr:DescribeImages"]
    resources = [var.platform_repository_arn]
  }

  # 읽기: -target은 의존 자원까지 refresh하므로 그 자원들의 조회 권한이 필요하다.
  # 대상: 클러스터·ASG·실행 템플릿·EFS·네트워크·ALB·ACM·Route 53·Cognito·IAM 역할·로그 그룹·ECR·비밀(메타데이터만)
  statement {
    sid = "ReadTargetDependencies"
    actions = [
      "sts:GetCallerIdentity",
      "ecs:Describe*",
      "ecs:List*",
      "ec2:Describe*",
      "autoscaling:Describe*",
      "elasticloadbalancing:Describe*",
      "elasticfilesystem:Describe*",
      "elasticfilesystem:ListTagsForResource",
      "acm:DescribeCertificate",
      "acm:ListTagsForCertificate",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
      "route53:GetChange",
      "route53:ListTagsForResource",
      "cognito-idp:DescribeUserPool",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:DescribeUserPoolDomain",
      "cognito-idp:GetUserPoolMfaConfig",
      "cognito-idp:ListTagsForResource",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
    ]
    resources = ["*"]
  }
  statement {
    sid = "ReadPlatformRoles"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetInstanceProfile",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account}:role/${var.name_prefix}-*",
      "arn:${local.partition}:iam::${local.account}:instance-profile/${var.name_prefix}-*",
    ]
  }
  statement {
    sid = "ReadSecretMetadata"
    # 값(GetSecretValue)은 읽지 않는다.
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy"]
    resources = var.secret_arns
  }
  statement {
    sid       = "ReadEcsAmiParameter"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/ecs/*"]
  }
}
