# ****** IAM ******
resource "aws_iam_role_policy" "ecs" {
  name = "quest_${var.environment}_ecs_lambda_function_iam_role_policy"
  role = "${aws_iam_role.ecs.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "ecs" {
  name = "quest_${var.environment}_ecs_lambda_function_iam_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      }
    }
  ]
}
EOF
}

# ****** ECS ******
resource "aws_ecs_cluster" "quest" {
  name = "quest_${var.environment}_ecs_cluster"

  capacity_providers = ["FARGATE"]
}

resource "aws_ecs_task_definition" "quest" {
  family = "quest_${var.environment}_ecs_task_definition"

  container_definitions = jsonencode([
    {
      name         = "app"
      image        = "${var.image}"
      cpu          = 256
      memory       = 512
      environment  = [
        {
          name  = "SECRET_WORD"
          value = "${var.secret}"
        }
      ]
      essential    = true
      portMappings = [
        {
          "containerPort" = 3000
          "hostPort"      = 3000
          "protocol"      = "tcp"
        }
      ]
      logConfiguration = {
        "logDriver" = "awslogs"
        "options" = {
          "awslogs-group" = "${aws_cloudwatch_log_group.quest.name}"
          "awslogs-region" = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  execution_role_arn       = "${aws_iam_role.ecs.arn}"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"

  depends_on = [aws_cloudwatch_log_group.quest]
}

resource "aws_ecs_service" "quest" {
  name = "quest_${var.environment}_ecs_service"

  cluster         = aws_ecs_cluster.quest.name
  task_definition = aws_ecs_task_definition.quest.id

  launch_type = "FARGATE"

  desired_count = 1

  load_balancer {
    target_group_arn = aws_alb_target_group.default.id
    container_name   = "app"
    container_port   = "3000"
  }

  network_configuration {
    subnets          = data.aws_subnet_ids.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_ecs_task_definition.quest]
}

# ****** LOAD BALANCING ******
resource "aws_alb" "default" {
  name = "quest-${var.environment}"

  security_groups = [aws_security_group.lb.id]
  subnets         = data.aws_subnet_ids.default.ids

  tags = {
    Name        = "quest_${var.environment}_alb"
    Environment = var.environment
  }
}

resource "aws_alb_target_group" "default" {
  name = "quest-${var.environment}"

  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/"
    port                = "traffic-port"
    unhealthy_threshold = "2"
  }

  port     = "3000"
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  tags = {
    Name        = "quest_${var.environment}_alb_target_group"
    Environment = var.environment
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.default.id
  port              = "443"
  protocol          = "HTTPS"

  certificate_arn = data.aws_acm_certificate.default.arn

  default_action {
    target_group_arn = aws_alb_target_group.default.id
    type             = "forward"
  }
}

# ****** SECURITY RESOURCES ******
resource "aws_security_group" "lb" {
  name   = "quest_${var.environment}_lb_security_group"
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "https" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.lb.id

  description = "Allow https traffic from anywhere to the LB"
}

resource "aws_security_group_rule" "lb_egress_all" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.lb.id}"

  description = "Allow all traffic out from LB"
}

resource "aws_security_group" "ecs" {
  name   = "quest_${var.environment}_ecs_security_group"
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "lb_to_ecs" {
  type        = "ingress"
  from_port   = 3000
  to_port     = 3000
  protocol    = "tcp"

  security_group_id        = aws_security_group.ecs.id
  source_security_group_id = aws_security_group.lb.id

  description = "Allow traffic from the LB to ECS"
}

resource "aws_security_group_rule" "ecs_egress_all" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.ecs.id}"

  description = "Allow all traffic out from ECS"
}

# ****** CLOUDWATCH ******
resource "aws_cloudwatch_log_group" "quest" {
  name  = "/aws/ecs/quest_${var.environment}"
}

# ****** ROUTE53 ******
resource "aws_route53_record" "quest" {
  zone_id = data.aws_route53_zone.default.zone_id
  name    = "${local.subdomain}.${data.aws_route53_zone.default.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_alb.default.dns_name]
}