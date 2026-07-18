# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Optional external Application Load Balancer (ALB) in front of the Nomad
# clients, for the "Load Balancer Integrations" tutorial:
# https://developer.hashicorp.com/nomad/tutorials/load-balancing
#
# Disabled by default (var.enable_load_balancer = false). When enabled, an
# ALB forwards HTTP traffic on port 80 to a fixed application port on every
# Nomad client instance (var.load_balancer_target_port, default 9002 — the
# Countdash demo app's web UI port already opened via extra_ingress_ports).
#
# ALBs require at least two subnets in two different Availability Zones,
# but this repo's compute nodes live in a single subnet/AZ (see network.tf).
# A second, instance-free subnet is created here purely to satisfy that AWS
# requirement — it carries no EC2 instances and does not affect existing
# server/client placement.

resource "aws_subnet" "alb_subnet" {
  count                   = var.enable_load_balancer ? 1 : 0
  vpc_id                  = aws_vpc.nomad_consul_vpc.id
  cidr_block              = var.alb_subnet_cidr
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[1]

  tags = {
    Name  = "${var.project_name}-alb-subnet"
    Owner = var.owner
  }
}

resource "aws_security_group" "alb_sg" {
  count       = var.enable_load_balancer ? 1 : 0
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the optional external ALB"
  vpc_id      = aws_vpc.nomad_consul_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from the internet"
  }

  egress {
    from_port   = var.load_balancer_target_port
    to_port     = var.load_balancer_target_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "To Nomad clients on the target application port"
  }

  tags = {
    Name  = "${var.project_name}-alb-sg"
    Owner = var.owner
  }
}

resource "aws_lb" "nomad_clients" {
  count              = var.enable_load_balancer ? 1 : 0
  name               = "${var.project_name}-clients-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg[0].id]
  subnets            = [aws_subnet.subnet.id, aws_subnet.alb_subnet[0].id]

  tags = {
    Name  = "${var.project_name}-clients-alb"
    Owner = var.owner
  }
}

resource "aws_lb_target_group" "nomad_clients" {
  count       = var.enable_load_balancer ? 1 : 0
  name        = "${var.project_name}-clients-tg"
  port        = var.load_balancer_target_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.nomad_consul_vpc.id
  target_type = "instance"

  health_check {
    path                = "/"
    port                = var.load_balancer_target_port
    matcher             = "200-399"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name  = "${var.project_name}-clients-tg"
    Owner = var.owner
  }
}

resource "aws_lb_target_group_attachment" "nomad_clients" {
  count            = var.enable_load_balancer ? var.client_count : 0
  target_group_arn = aws_lb_target_group.nomad_clients[0].arn
  target_id        = aws_instance.clients[count.index].id
  port             = var.load_balancer_target_port
}

resource "aws_lb_listener" "nomad_clients" {
  count             = var.enable_load_balancer ? 1 : 0
  load_balancer_arn = aws_lb.nomad_clients[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad_clients[0].arn
  }
}
