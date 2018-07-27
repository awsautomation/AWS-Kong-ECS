# ECS Cluster
resource "aws_security_group" "ecs_sg" {
  name        = "${var.app_name}-ECS-SG"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress = {
    description       = "all from alb"
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    security_groups   = ["${module.alb_sg.this_security_group_id}"]
    self              = true
  }
  egress = {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags  = [
    {
      Name = "${var.app_name}-ECS-SG"
    }
  ]
}
data "aws_ami" "ecs" {
  most_recent = true
  filter {
    name      = "owner-alias"
    values    = ["amazon"]
  }
  filter {
    name      = "name"
    values    = ["amzn-ami-*-amazon-ecs-optimized"]
  }
}
module "ecs_cluster_iam" {
  source = "modules/ecs_cluster_iam"
}
data "template_file" "ecs_user_data" {
  template = <<EOF
#!/bin/bash
cat << EOF_CONFIG > /etc/ecs/ecs.config
ECS_CLUSTER=${var.app_name}
ECS_DISABLE_PRIVILEGED=true
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_AWSVPC_BLOCK_IMDS=true
EOF_CONFIG
EOF
}
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}"
}
module "asg" {
  source = "modules/asg"

  name = "${var.app_name}-ECS-ASG"

  # Launch configuration
  lc_name = "${var.app_name}-ECS-LC"

  image_id        = "${data.aws_ami.ecs.id}"
  instance_type   = "${var.ecs_cluster_instance_type}"
  security_groups = ["${aws_security_group.ecs_sg.id}"]
  key_name        = "${var.ssh_key_name}"

  # block devices - use defaults

  # Auto scaling group
  asg_name                  = "${var.app_name}-ECS-ASG"
  vpc_zone_identifier       = ["${module.vpc.public_subnets}"]
  iam_instance_profile      = "${module.ecs_cluster_iam.ecs_instance_profile_id}"
  user_data                 = "${data.template_file.ecs_user_data.rendered}"
  health_check_type         = "EC2"
  min_size                  = 1
  max_size                  = 2
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

  tags = [
    {
      key                 = "Environment"
      value               = "dev"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "kong demo"
      propagate_at_launch = true
    },
  ]
}
output "ami_id" {
  value = "${data.aws_ami.ecs.id}"
}
