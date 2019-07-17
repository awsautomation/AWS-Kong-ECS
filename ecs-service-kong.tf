# KONG ECS Task IAM roles
resource "aws_iam_role" "ecs_task" {
  name = "ecs-task-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": "1"
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "ecs_task_execution_role_policy" {
    name = "ecs_task_execution_role_policy-attachment"
    roles = ["${aws_iam_role.ecs_task.name}"]
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# Cloudwatch
resource "aws_cloudwatch_log_group" "kong" {
  name = "kong"

  tags = {
    Environment = "dev"
    Application = "kong"
  }
}
# Kong ECS Service & Task Definition
resource "aws_ecs_task_definition" "kong" {
  family                = "${var.app_name}"
  task_role_arn         = "${aws_iam_role.ecs_task.arn}"
  execution_role_arn    = "${aws_iam_role.ecs_task.arn}"
  network_mode          = "awsvpc"
  volume {
    name      = "kong-vol"
    host_path = "/ecs/kong-vol"
  }
  container_definitions = <<EOF
[
  {
    "name": "${var.app_name}",
    "container_name": "${var.app_name}",
    "image": "${var.app_image}",
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-region": "${var.region}",
        "awslogs-group": "${aws_cloudwatch_log_group.kong.name}",
        "awslogs-stream-prefix": "kong-ecs"
      }
    },
    "mountPoints": [
                {
                    "sourceVolume": "kong-vol",
                    "containerPath": "/usr/local/kong/declarative",
                    "readOnly": false
                }
    ],
    "memoryReservation": ${var.container_memory_reservation},
    "portMappings": [
      {
        "ContainerPort": 8000,
        "hostPort": 8000
      },
      {
        "ContainerPort": 8001,
        "hostPort": 8001
      },
      {
        "ContainerPort": 8443,
        "hostPort": 8443
      },
      {
        "ContainerPort": 8444,
        "hostPort": 8444
      }
    ],
    "environment": [
      {
        "name"  : "KONG_ADMIN_LISTEN",
        "value" : "0.0.0.0:8001, 0.0.0.0:8444 ssl"
      },
      {
        "name"  : "KONG_DATABASE",
        "value" : "off"
      },
      {
        "name"  : "KONG_PROXY_ACCESS_LOG",
        "value" : "/dev/stdout"
      },
      {
        "name"  : "KONG_ADMIN_ACCESS_LOG",
        "value" : "/dev/stdout"
      },
      {
        "name"  : "KONG_PROXY_ERROR_LOG",
        "value" : "/dev/stderr"
      },
      {
        "name"  : "KONG_ADMIN_ERROR_LOG",
        "value" : "/dev/stderr"
      },
      {
        "name"  : "KONG_DECLARATIVE_CONFIG",
        "value" : "/usr/local/kong/declarative/kong.yml"
      },
      {
        "name"  : "KONG_LOG_LEVEL",
        "value" : "debug"
      }
    ]
  }
]
EOF
}
resource "aws_ecs_service" "kong" {
  name                = "${var.app_name}"
  launch_type         = "EC2"
  cluster             = "${aws_ecs_cluster.main.id}"
  task_definition     = "${aws_ecs_task_definition.kong.arn}"
  desired_count       = "${var.ecs_service_desired_count}"
  scheduling_strategy = "REPLICA"

  load_balancer {
    target_group_arn  = "${aws_alb_target_group.main.id}"
    container_name    = "${var.app_name}"
    container_port    = "8000"
  }
  service_registries {
    registry_arn      = "${aws_service_discovery_service.kong.arn}"
    container_name    = "${var.app_name}"
  }
  network_configuration {
    subnets             = "${module.vpc.private_subnets}"
    assign_public_ip    = false
    security_groups     = ["${aws_security_group.ecs_service_kong.id}"]
  }
  depends_on = [
    "aws_alb.main"
  ]
}
resource "aws_service_discovery_service" "kong" {
  name = "kong"
  dns_config {
    namespace_id = "${aws_service_discovery_private_dns_namespace.main.id}"
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
resource "aws_security_group" "ecs_service_kong" {
  name        = "${var.app_name}-ECS-SG-kong"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress  {
    description       = "all from self + alb "
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    security_groups   = [
      "${module.alb_sg.this_security_group_id}",
    ]
    self              = true
  }
  egress  {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags  = {

    Name = "${var.app_name}-ECS-SG-kong"

  }   
}
