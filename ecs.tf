# --- Service Discovery Namespace ---
resource "aws_service_discovery_private_dns_namespace" "vote_ns" {
  name        = "vote.local"
  description = "Private DNS namespace for ECS Service Connect"
  vpc         = aws_vpc.vote_vpc.id
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "vote_cluster" {
  name = "vote-cluster"
  depends_on = [aws_service_discovery_private_dns_namespace.vote_ns]
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  service_connect_defaults {
    namespace = aws_service_discovery_private_dns_namespace.vote_ns.arn
  }
}

# --- Redis Task ---
resource "aws_ecs_task_definition" "redis" {
  family                   = "redis-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  task_role_arn            = aws_iam_role.ecs_task_exec.arn
  container_definitions = jsonencode([
    {
      name      = "redis"
      image     = "redis:latest"
      essential = true
      portMappings = [{
        containerPort = 6379
        name          = "redis-port"
      }]
    }
  ])
}

# --- Vote Server (Flask) ---
resource "aws_ecs_task_definition" "server" {
  family                   = "vote-server-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  task_role_arn            = aws_iam_role.ecs_task_exec.arn
  container_definitions = jsonencode([
    {
      name      = "vote-server"
      image     = "662793765491.dkr.ecr.eu-central-1.amazonaws.com/vote-app:server-latest"
      essential = true
      portMappings = [{
        containerPort = 5000
        name          = "server-port"
      }]
      environment = [
        { name = "REDIS_HOST", value = "redis.vote.local" },
        { name = "REDIS_PORT", value = "6379" }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = "/ecs/vote-server",
          "awslogs-region"        = "eu-central-1",
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# --- Vote Client (Node.js) ---
resource "aws_ecs_task_definition" "client" {
  family                   = "vote-client-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  task_role_arn            = aws_iam_role.ecs_task_exec.arn
  container_definitions = jsonencode([
    {
      name      = "vote-client"
      image     = "662793765491.dkr.ecr.eu-central-1.amazonaws.com/vote-app:client-latest"
      essential = true
      portMappings = [{
        containerPort = 3000
        name          = "client-port"
      }]
      environment = [
        { name = "VOTE_SERVER_URL", value = "http://${aws_lb.vote_alb.dns_name}/api" }
      ]
    }
  ])
}

# --- Redis Service ---
resource "aws_ecs_service" "redis_service" {
  name                   = "redis"
  cluster                = aws_ecs_cluster.vote_cluster.id
  task_definition        = aws_ecs_task_definition.redis.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.vote_ns.arn

    service {
      discovery_name = "redis"
      port_name      = "redis-port"

      client_alias {
        port = 6379
      }
    }
  }
}

# --- Vote Server Service ---
resource "aws_ecs_service" "server_service" {
  name                   = "vote-server"
  cluster                = aws_ecs_cluster.vote_cluster.id
  task_definition        = aws_ecs_task_definition.server.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true
  depends_on             = [aws_ecs_service.redis_service]

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  # Connect service to ALB
  load_balancer {
    target_group_arn = aws_lb_target_group.vote_server_tg.arn
    container_name   = "vote-server"
    container_port   = 5000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.vote_ns.arn

    service {
      discovery_name = "vote-server"
      port_name      = "server-port"

      client_alias {
        port = 5000
      }
    }
  }
}

# --- Vote Client Service (Frontend) ---
resource "aws_ecs_service" "client_service" {
  name                   = "vote-client"
  cluster                = aws_ecs_cluster.vote_cluster.id
  task_definition        = aws_ecs_task_definition.client.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true
  depends_on             = [aws_ecs_service.server_service]

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.vote_client_tg.arn
    container_name   = "vote-client"
    container_port   = 3000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.vote_ns.arn

    service {
      discovery_name = "vote-client"
      port_name      = "client-port"

      client_alias {
        port = 3000
      }
    }
  }
}
