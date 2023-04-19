provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_efs_file_system" "assetstore" {
}

resource "aws_efs_file_system" "mongo" {
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
    cidr_blocks = [aws_default_vpc.default.cidr_block]
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

resource "aws_efs_mount_target" "mount_target_assetstore_az1" {
  file_system_id  = aws_efs_file_system.assetstore.id
  subnet_id       = "subnet-08528e25501eede26" # TODO don't hardcode
  security_groups = [aws_security_group.efs_mount_target_sg.id]
}

resource "aws_efs_mount_target" "mount_target_assetstore_az2" {
  file_system_id  = aws_efs_file_system.assetstore.id
  subnet_id       = "subnet-04155544b5a3fdf94" # TODO don't hardcode
  security_groups = [aws_security_group.efs_mount_target_sg.id]
}

resource "aws_efs_mount_target" "mount_target_mongo_az1" {
  file_system_id  = aws_efs_file_system.mongo.id
  subnet_id       = "subnet-08528e25501eede26" # TODO don't hardcode
  security_groups = [aws_security_group.efs_mount_target_sg.id]
}

resource "aws_efs_mount_target" "mount_target_mongo_az2" {
  file_system_id  = aws_efs_file_system.mongo.id
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

    efs_volume_configuration {
      file_system_id = aws_efs_file_system.mongo.id
    }
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
        image = "zachmullen/histomics-load-test@sha256:27199584248eba32a867f62c88700b4b86c2d4732b70625d8e447f5d012e87c7"
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
          },
          {
            name  = "GIRDER_BROKER_URI"
            value = "amqps://histomics:${random_password.mq_password.result}@${aws_mq_broker.jobs_queue.id}.mq.${data.aws_region.current.name}.amazonaws.com:5671"
          },
          {
            # TODO make our wsgi module use the same env var name as above.
            # Necessary due to direct use of task.delay() in slicer_cli_web.
            name  = "GIRDER_WORKER_BROKER"
            value = "amqps://histomics:${random_password.mq_password.result}@${aws_mq_broker.jobs_queue.id}.mq.${data.aws_region.current.name}.amazonaws.com:5671"
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
      file_system_id = aws_efs_file_system.assetstore.id
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
    assign_public_ip = true  # this should probably be false and we should add a NAT instead
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
    assign_public_ip = true  # this should probably be false and we should add a NAT instead
    security_groups  = [aws_security_group.histomics_sg.id]
    subnets          = ["subnet-08528e25501eede26"] # TODO don't hardcode
  }
}

### Message queue

resource "random_password" "mq_password" {
  length  = 20
  special = false # So we don't have to urlencode this further down
}

resource "aws_security_group" "mq_broker_sg" {
  name = "mq-broker-sg"

  ingress {
    from_port   = 5671
    to_port     = 5671
    protocol    = "tcp"
    cidr_blocks = [aws_default_vpc.default.cidr_block]
  }
}

resource "aws_mq_broker" "jobs_queue" {
  broker_name = "jobs_queue"

  engine_type        = "RabbitMQ"
  engine_version     = "3.10.10"
  host_instance_type = "mq.t3.micro"
  security_groups    = [aws_security_group.mq_broker_sg.id]

  user {
    username = "histomics"
    password = random_password.mq_password.result
  }
}

### Worker(s)

resource "aws_cloudwatch_log_group" "histomics_worker_logs" {
  name = "histomics-worker-logs"
}

resource "aws_ecs_task_definition" "histomics_worker_task" {
  family                   = "histomics-worker-task"
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 1024
  execution_role_arn       = "arn:aws:iam::951496264182:role/ecsTaskExecutionRole" # TODO terraform this
  container_definitions = jsonencode(
    [
      {
        name  = "histomics-worker"
        image = "zachmullen/histomics-worker@sha256:bafffe5c08a282925da2560d1af3b64020c0d085d42ac81793645d7d1b1ccaf9"
        entryPoint = [
          "girder-worker",
          "--concurrency=4",
          "-l", "info",
          "-Ofair",
          "--prefetch-multiplier=1"
        ],
        cpu       = 1024
        memory    = 1024
        essential = true
        environment = [
          {
            name  = "GW_DIRECT_PATHS"
            value = "true"
          },
          {
            name  = "GIRDER_WORKER_BROKER"
            value = "amqps://histomics:${random_password.mq_password.result}@${aws_mq_broker.jobs_queue.id}.mq.${data.aws_region.current.name}.amazonaws.com:5671"
          }
        ],
        mountPoints = [
          {
            sourceVolume  = "assetstore"
            containerPath = "/assetstore"
            readOnly      = false
          },
          {
            sourceVolume  = "bindMountHost",
            containerPath = "/var/run/docker.sock"
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.histomics_worker_logs.id
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
      file_system_id = aws_efs_file_system.assetstore.id
    }
  }

  volume {
    name = "bindMountHost"
    host_path = "/var/run/docker.sock"
  }
}

resource "aws_ecs_service" "worker_service" {
  name            = "worker-service"
  cluster         = aws_ecs_cluster.histomics_cluster.id
  task_definition = aws_ecs_task_definition.histomics_worker_task.arn
  desired_count   = 1
  launch_type     = "EC2"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn
  }

  network_configuration {
    security_groups  = [aws_security_group.histomics_worker_sg.id]
    subnets          = ["subnet-08528e25501eede26"] # TODO don't hardcode
  }
}

resource "aws_security_group" "histomics_worker_sg" {
  name = "histomics-worker-sg"

  vpc_id = aws_default_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_instance_profile" "worker" {
  name = "worker-instance-profile"
  role = "ecsTaskExecutionRole"  # TODO don't hardcode
}

resource "aws_instance" "worker" {
  ami           = "ami-0c76be34ffbfb0b14"
  instance_type = "t3.medium"
  count = 1
  vpc_security_group_ids = [aws_security_group.histomics_worker_sg.id]
  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=histomics >> /etc/ecs/ecs.config
EOF
  subnet_id = "subnet-08528e25501eede26"  # TODO don't hardcode
  iam_instance_profile = aws_iam_instance_profile.worker.name
}
