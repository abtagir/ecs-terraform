# --- ECS Cluster ---
resource "aws_ecs_cluster" "vote_cluster" {
  name = "vote-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  service_connect_defaults {
    namespace = aws_service_discovery_private_dns_namespace.vote_ns.arn
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs_capacity" {
  cluster_name = aws_ecs_cluster.vote_cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# --- Service Discovery Namespace ---
resource "aws_service_discovery_private_dns_namespace" "vote_ns" {
  name        = "vote.local"
  description = "Private DNS namespace for ECS services"
  vpc         = aws_vpc.vote_vpc.id
}

# --- Service Discovery for Redis ---
resource "aws_service_discovery_service" "redis_sd" {
  name = "redis"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.vote_ns.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
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

  container_definitions = jsonencode([
    {
      name         = "redis"
      image        = "redis:latest"
      essential    = true
      portMappings = [{ containerPort = 6379 }]
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

  container_definitions = jsonencode([
    {
      name         = "vote-server"
      image        = "abtagir/vote-server:latest"
      essential    = true
      portMappings = [{ containerPort = 5000 }]
      environment = [
        { name = "REDIS_HOST", value = "redis.vote.local" }
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

  container_definitions = jsonencode([
    {
      name         = "vote-client"
      image        = "abtagir/vote-client:latest"
      essential    = true
      portMappings = [{ containerPort = 3000 }]
      environment = [
        { name = "VOTE_SERVER_URL", value = "http://vote-server:5000" }
      ]
    }
  ])
}

resource "aws_ecs_service" "redis_service" {
  name            = "redis"
  cluster         = aws_ecs_cluster.vote_cluster.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.redis_sd.arn
  }
}

resource "aws_ecs_service" "server_service" {
  name            = "vote-server"
  cluster         = aws_ecs_cluster.vote_cluster.id
  task_definition = aws_ecs_task_definition.server.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  depends_on      = [aws_ecs_service.redis_service]

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "client_service" {
  name            = "vote-client"
  cluster         = aws_ecs_cluster.vote_cluster.id
  task_definition = aws_ecs_task_definition.client.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  depends_on      = [aws_ecs_service.server_service]

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
}