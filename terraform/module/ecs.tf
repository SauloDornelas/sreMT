resource "aws_ecs_cluster" "this" {
  name               = var.id
  tags               = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.id
  container_definitions    = jsonencode(local.container)
  execution_role_arn       = aws_iam_role.this.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  tags                     = var.tags
}

resource "aws_ecs_service" "this" {
  name                              = var.id
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  propagate_tags                    = "SERVICE"
  health_check_grace_period_seconds = 30
  tags                              = var.tags

  load_balancer {
    target_group_arn = aws_lb_target_group.this.id
    container_name   = local.container[0].name
    container_port   = local.container[0].portMappings[0].containerPort
  }

  network_configuration {
    security_groups = [aws_security_group.ecs.id]
    assign_public_ip = true
    subnets         = tolist(var.public_subnet_ids_2)
  }
}


resource "aws_appautoscaling_target" "ecs_target" {
  min_capacity       = var.task_count.min
  max_capacity       = var.task_count.max
  resource_id        = "service/${var.id}/${var.id}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "memory_scalling_policy" {
  name               = "${var.id}-memory-scalling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value = 70
  }
}

resource "aws_appautoscaling_policy" "cpu_scalling_policy" {
  name               = "${var.id}-cpu-scalling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = 70
  }
}

data "aws_region" "this" {}

locals {
  container = [
    {
      name        = "metabase"
      image       = var.image
      essential   = true
      environment = concat(local.environment, var.environment)

      secrets = [
        {
          name      = "MB_DB_PASS"
          valueFrom = aws_ssm_parameter.this.name
        },
      ]

      portMappings = [
        {
          containerPort = 3000
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.this.name
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ]

  environment = [
    {
      name  = "JAVA_TIMEZONE"
      value = var.java_timezone
    },
    {
      name  = "MB_DB_TYPE"
      value = "postgres"
    },
    {
      name  = "MB_DB_DBNAME"
      value = aws_rds_cluster.this.database_name
    },
    {
      name  = "MB_DB_PORT"
      value = tostring(aws_rds_cluster.this.port)
    },
    {
      name  = "MB_DB_USER"
      value = aws_rds_cluster.this.master_username
    },
    {
      name  = "MB_DB_HOST"
      value = aws_rds_cluster.this.endpoint
    },
  ]
}

resource "aws_iam_role" "this" {
  name_prefix        = var.id
  assume_role_policy = data.aws_iam_policy_document.ecs.json
  tags               = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "ecs" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.this.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
  role       = aws_iam_role.this.name
}

resource "aws_lb_target_group" "this" {
  name        = var.id
  port        = local.container[0].portMappings[0].containerPort
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  tags        = var.tags

  health_check {
    path = "/"
  }
}

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = aws_ecs_task_definition.this.id
  port             = local.container[0].portMappings[0].containerPort
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.id
  retention_in_days = var.log_retention
  tags              = var.tags
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.id}-ecs"
  vpc_id      = var.vpc_id
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ecs_egress_internet" {
  count             = var.internet_egress ? 1 : 0
  description       = "Internet"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.ecs.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ecs_egress_rds" {
  description              = "ALB"
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.ecs.id
  source_security_group_id = aws_security_group.rds.id
}

resource "aws_security_group_rule" "ecs_ingress_alb" {
  description              = "ALB"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.ecs.id
  source_security_group_id = aws_security_group.alb.id
}
