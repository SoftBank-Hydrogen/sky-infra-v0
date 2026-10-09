# [ECS] ECS on EC2 1대에서 sky-platform 태스크 하나를 돌림
# 확장 시 이 모듈만 교체할 것. 태스크는 aws vpc, 타깃 그룹은 ip 타입이라 앞단은 그대로

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_region" "current" {}

# 클러스터와 용량 (EC2 1대)
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = var.exec_log_group_name
      }
    }
  }
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_security_group" "instance" {
  name        = "${var.name_prefix}-ecs-instance"
  description = "Sky ECS container instance (egress only)"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-ecs-instance" }
}

resource "aws_vpc_security_group_egress_rule" "instance_all" {
  security_group_id = aws_security_group.instance.id
  description       = "ECS agent, image pulls, docker build"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_launch_template" "this" {
  name                   = "${var.name_prefix}-ecs"
  image_id               = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.instance.id]
  update_default_version = true

  iam_instance_profile {
    name = var.instance_profile_name
  }

  # IMDSv2 필수. 홉 1이면 docker build 컨테이너가 인스턴스 역할 자격 증명을 못 가져감
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_gib
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<'CONFIG'
    ECS_CLUSTER=${aws_ecs_cluster.this.name}
    ECS_AWSVPC_BLOCK_IMDS=true
    CONFIG
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name_prefix}-ecs" }
  }
}

resource "aws_autoscaling_group" "this" {
  name                = "${var.name_prefix}-ecs"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.app_subnet_ids
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name_prefix}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn
    managed_termination_protection = "DISABLED"

    # 대수는 ASG에서 1로 고정함
    managed_scaling {
      status = "DISABLED"
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }
}

# .sky/ 영구 저장소 (EFS)
resource "aws_efs_file_system" "state" {
  creation_token = "${var.name_prefix}-state"
  encrypted      = true

  tags = { Name = "${var.name_prefix}-state" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_efs_backup_policy" "state" {
  file_system_id = aws_efs_file_system.state.id
  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.name_prefix}-efs"
  description = "Sky state EFS"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-efs" }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_app" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from Sky tasks only"
  referenced_security_group_id = var.app_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
}

resource "aws_efs_mount_target" "state" {
  # 서브넷 ID는 apply 전에 unknown이라 키로 쓸 수 없다. 목록 순서(인덱스)를 키로 쓴다.
  for_each        = { for i, id in var.app_subnet_ids : tostring(i) => id }
  file_system_id  = aws_efs_file_system.state.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# 태스크 정의와 서비스
locals {
  container_name = "sky-platform"
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.service_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # 이미지가 바뀌면 새 리비전을 만들고 이전 리비전은 등록 해제하지 않는다 (롤백 대상으로 남김)
  skip_destroy = true

  volume {
    name = "state"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.state.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }

  # 사용자 앱을 호스트 Docker로 빌드 (내부·데모용)
  volume {
    name      = "docker-socket"
    host_path = "/var/run/docker.sock"
  }

  container_definitions = jsonencode([{
    name      = local.container_name
    image     = var.image
    essential = true

    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

    environment = [for k, v in var.environment : { name = k, value = v }]
    secrets     = [for k, arn in var.secrets : { name = k, valueFrom = arn }]

    mountPoints = [
      { sourceVolume = "state", containerPath = var.state_path, readOnly = false },
      { sourceVolume = "docker-socket", containerPath = "/var/run/docker.sock", readOnly = false },
    ]

    linuxParameters = { initProcessEnabled = true }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "platform"
      }
    }
  }])
}

# 대상 그룹이 ALB 리스너에 연결된 뒤에 서비스를 만듦
resource "terraform_data" "listener_ready" {
  input = var.alb_listener_arn
}

resource "aws_ecs_service" "this" {
  name                   = var.service_name
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = 1
  enable_execute_command = true
  propagate_tags         = "SERVICE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 120

  # 새 태스크가 뜨지 못하면 ECS가 직전 태스크 정의로 되돌림
  # 이때 state는 새 리비전을 가리키므로 다음 plan에 서비스 차이가 보임
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }

  network_configuration {
    subnets         = var.app_subnet_ids
    security_groups = [var.app_security_group_id]
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  depends_on = [
    terraform_data.listener_ready,
    aws_ecs_cluster_capacity_providers.this,
    aws_efs_mount_target.state,
  ]
}
