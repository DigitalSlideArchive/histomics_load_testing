provider "aws" {
  region = "us-east-1"
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_efs_file_system" "assetstore_fs" {
}

# TODO grab or import default subnets

resource "aws_service_discovery_http_namespace" "internal" {
  name = "internal"
}

resource "aws_cloudwatch_log_group" "histomics_logs" {
  name = "histomics-logs"
}

resource "aws_cloudwatch_log_group" "mongo_logs" {
  name = "mongo-logs"
}

resource "aws_security_group" "efs_mount_target_sg" {
  name = "efs-mount-target-sg"

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/20", "172.31.80.0/20"] # TODO don't hardcode (these are the CIDR blocks of our two subnets)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lb_sg" {
  name   = "lb-sg"
  vpc_id = aws_default_vpc.default.id

  ingress {
    description      = "Open 80 to the internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "histomics_sg" {
  name = "histomics-sg"

  vpc_id = aws_default_vpc.default.id

  ingress {
    description = "Allow members of this security group to talk to port 27017"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Allow load balancer SG to talk to port 8080"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_lb" "ecs_lb" {
  name               = "ecs-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = ["subnet-08528e25501eede26", "subnet-04155544b5a3fdf94"] # TODO don't hardcode
  security_groups    = [aws_security_group.lb_sg.id]
}

resource "aws_efs_mount_target" "assetstore_az1" {
  file_system_id  = aws_efs_file_system.assetstore_fs.id
  subnet_id       = "subnet-08528e25501eede26" # TODO don't hardcode
  security_groups = [aws_security_group.efs_mount_target_sg.id]
}

resource "aws_efs_mount_target" "assetstore_az2" {
  file_system_id  = aws_efs_file_system.assetstore_fs.id
  subnet_id       = "subnet-04155544b5a3fdf94" # TODO don't hardcode
  security_groups = [aws_security_group.efs_mount_target_sg.id]
}

resource "aws_lb_target_group" "ecs_target_group" {
  name        = "ecs-target-group"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default.id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "ecs_lb_listener" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
    type             = "forward"
  }
}

resource "aws_ecs_cluster" "histomics_cluster" {
  name = "histomics"
}

resource "aws_ecs_task_definition" "mongo_task" {
  family                   = "mongo-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2048
  memory                   = 8192
  execution_role_arn       = "arn:aws:iam::951496264182:role/ecsTaskExecutionRole" # TODO terraform this
  container_definitions = jsonencode([
    {
      name      = "mongo-service"
      image     = "mongo:latest"
      cpu       = 2048
      memory    = 8192
      essential = true
      portMappings = [
        {
          name          = "mongod"
          containerPort = 27017
          hostPort      = 27017
        }
      ],
      mountPoints = [
        {
          sourceVolume  = "mongo-data"
          containerPath = "/data/db"
          readOnly      = false
        }
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.mongo_logs.id
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  volume {
    name = "mongo-data"
  }
}

resource "aws_ecs_task_definition" "histomics_task" {
  family                   = "histomics-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 4096
  memory                   = 8192
  execution_role_arn       = "arn:aws:iam::951496264182:role/ecsTaskExecutionRole" # TODO terraform this
  container_definitions = jsonencode(
    [
      {
        name  = "histomics-server"
        image = "zachmullen/histomics-load-test"
        entryPoint = [
          "gunicorn",
          "histomicsui.wsgi:app",
          "--bind=0.0.0.0:8080",
          "--workers=4",
          "--preload"
        ],
        cpu       = 4096
        memory    = 8192
        essential = true
        portMappings = [
          {
            containerPort = 8080
            hostPort      = 8080
          }
        ]
        environment = [
          {
            name  = "GIRDER_MONGO_URI"
            value = "mongodb://mongo-service:27017/girder"
          }
        ],
        mountPoints = [
          {
            sourceVolume  = "assetstore"
            containerPath = "/assetstore"
            readOnly      = false
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.histomics_logs.id
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
      }
    ]
  )

  volume {
    name = "assetstore"

    efs_volume_configuration {
      file_system_id = aws_efs_file_system.assetstore_fs.id
    }
  }
}

resource "aws_ecs_service" "histomics_service" {
  name            = "histomics-service"
  cluster         = aws_ecs_cluster.histomics_cluster.id
  task_definition = aws_ecs_task_definition.histomics_task.arn
  desired_count   = 2
  depends_on      = [aws_ecs_task_definition.histomics_task, aws_ecs_task_definition.mongo_task]
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.histomics_sg.id]
    subnets          = ["subnet-08528e25501eede26"] # TODO don't hardcode
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
    container_name   = "histomics-server"
    container_port   = 8080
  }
}

resource "aws_ecs_service" "mongo_service" {
  name            = "mongo-service"
  cluster         = aws_ecs_cluster.histomics_cluster.id
  depends_on      = [aws_ecs_task_definition.mongo_task]
  task_definition = aws_ecs_task_definition.mongo_task.arn

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn

    service {
      port_name = "mongod"

      client_alias {
        port     = 27017
        dns_name = "mongo-service"
      }
    }
  }

  desired_count = 1
  launch_type   = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.histomics_sg.id]
    subnets          = ["subnet-08528e25501eede26"] # TODO don't hardcode
  }
}
