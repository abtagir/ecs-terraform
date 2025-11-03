# # --- ECS Cluster ---
# resource "aws_ecs_cluster" "vote_cluster" {
#   name = "vote-cluster"

#   setting {
#     name  = "containerInsights"
#     value = "enabled"
#   }

#   service_connect_defaults {
#     namespace = aws_service_discovery_private_dns_namespace.vote_ns.arn
#   }
# }

# resource "aws_ecs_cluster_capacity_providers" "ecs_capacity" {
#   cluster_name = aws_ecs_cluster.vote_cluster.name

#   capacity_providers = ["FARGATE"]

#   default_capacity_provider_strategy {
#     base              = 1
#     weight            = 100
#     capacity_provider = "FARGATE"
#   }
# }

# # --- Service Discovery Namespace ---
# resource "aws_service_discovery_private_dns_namespace" "vote_ns" {
#   name        = "vote.local"
#   description = "Private DNS namespace for ECS services"
#   vpc         = "vpc-0d31decf8a4f43b3f"
# }

# # --- Service Discovery for Redis ---
# resource "aws_service_discovery_service" "redis_sd" {
#   name = "redis"

#   dns_config {
#     namespace_id = aws_service_discovery_private_dns_namespace.vote_ns.id
#     dns_records {
#       type = "A"
#       ttl  = 10
#     }
#     routing_policy = "MULTIVALUE"
#   }  
# }

# # --- Redis Task ---
# resource "aws_ecs_task_definition" "redis" {
#   family                   = "redis-task"
#   requires_compatibilities = ["FARGATE"]
#   network_mode             = "awsvpc"
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_task_exec.arn

#   container_definitions = jsonencode([
#     {
#       name         = "redis"
#       image        = "redis:latest"
#       essential    = true
#       portMappings = [{ containerPort = 6379 }]
#     }
#   ])
# }

# # --- Vote Server (Flask) ---
# resource "aws_ecs_task_definition" "server" {
#   family                   = "vote-server-task"
#   requires_compatibilities = ["FARGATE"]
#   network_mode             = "awsvpc"
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_task_exec.arn

#   container_definitions = jsonencode([
#     {
#       name         = "vote-server"
#       image        = "abtagir/vote-server:latest"
#       essential    = true
#       portMappings = [{ containerPort = 5000 }]
#       environment = [
#         { name = "REDIS_HOST", value = "redis.vote.local" }
#       ]

#       logConfiguration = {
#         logDriver = "awslogs",
#         options = {
#           "awslogs-group"         = "/ecs/vote-server",
#           "awslogs-region"        = "eu-central-1",
#           "awslogs-stream-prefix" = "ecs"
#         }
#      }

#     }
#   ])
# }

# # --- Vote Client (Node.js) ---
# resource "aws_ecs_task_definition" "client" {
#   family                   = "vote-client-task"
#   requires_compatibilities = ["FARGATE"]
#   network_mode             = "awsvpc"
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_task_exec.arn

#   container_definitions = jsonencode([
#     {
#       name         = "vote-client"
#       image        = "abtagir/vote-client:latest"
#       essential    = true
#       portMappings = [{ containerPort = 3000 }]
#       environment = [
#         { name = "VOTE_SERVER_URL", value = "http://vote-server:5000" }
#       ]
#     }
#   ])
# }

# resource "aws_ecs_service" "redis_service" {
#   name            = "redis"
#   cluster         = aws_ecs_cluster.vote_cluster.id
#   task_definition = aws_ecs_task_definition.redis.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"

#   network_configuration {
#     subnets          = ["subnet-01d044c1b449976ed", "subnet-02d3843dac4378d47"]
#     security_groups  = ["sg-0926150e1f3a73505"]
#     assign_public_ip = false
#   }

#   service_registries {
#     registry_arn = aws_service_discovery_service.redis_sd.arn
#   }
# }

# resource "aws_ecs_service" "server_service" {
#   name            = "vote-server"
#   cluster         = aws_ecs_cluster.vote_cluster.id
#   task_definition = aws_ecs_task_definition.server.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#   depends_on      = [aws_ecs_service.redis_service]

#   network_configuration {
#     subnets          = ["subnet-01d044c1b449976ed", "subnet-02d3843dac4378d47"]
#     security_groups  = ["sg-0926150e1f3a73505"]
#     assign_public_ip = false
#   }
# }

# resource "aws_ecs_service" "client_service" {
#   name            = "vote-client"
#   cluster         = aws_ecs_cluster.vote_cluster.id
#   task_definition = aws_ecs_task_definition.client.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#   depends_on      = [aws_ecs_service.server_service]

#   network_configuration {
#     subnets          = ["subnet-01d044c1b449976ed", "subnet-02d3843dac4378d47"]
#     security_groups  = ["sg-0926150e1f3a73505"]
#     assign_public_ip = false
#   }
#   load_balancer {
#     target_group_arn = aws_lb_target_group.vote_client_tg.arn
#     container_name   = "vote-client"
#     container_port   = 3000
#   }
# }

# resource "aws_appautoscaling_target" "ecs_autoscaling_target" {
#   max_capacity       = 4
#   min_capacity       = 1
#   resource_id        = "service/${aws_ecs_cluster.vote_cluster.name}/${aws_ecs_service.client_service.name}"
#   scalable_dimension = "ecs:service:DesiredCount"
#   service_namespace  = "ecs"
# }

# resource "aws_appautoscaling_policy" "vote_client_scale_down" {
#   name               = "vote-client-scale-down"
#   policy_type        = "StepScaling"
#   resource_id        = aws_appautoscaling_target.ecs_autoscaling_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_autoscaling_target.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.ecs_autoscaling_target.service_namespace

#   step_scaling_policy_configuration {
#     adjustment_type         = "ChangeInCapacity"
#     cooldown                = 60
#     metric_aggregation_type = "Maximum"

#     step_adjustment {
#       metric_interval_upper_bound = 0
#       scaling_adjustment          = -1
#     }
#   }
# }

# resource "aws_appautoscaling_policy" "vote_client_scale_up" {
#   name               = "vote-client-scale-up"
#   policy_type        = "StepScaling"
#   resource_id        = aws_appautoscaling_target.ecs_autoscaling_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_autoscaling_target.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.ecs_autoscaling_target.service_namespace

#   step_scaling_policy_configuration {
#     adjustment_type         = "ChangeInCapacity"
#     cooldown                = 60
#     metric_aggregation_type = "Maximum"

#     step_adjustment {
#       metric_interval_lower_bound = 0
#       scaling_adjustment          = 1
#     }
#   }
# }

# resource "aws_cloudwatch_metric_alarm" "vote_client_cpu_high" {
#   alarm_name          = "vote-client-cpu-high"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 2
#   metric_name         = "CPUUtilization"
#   namespace           = "AWS/ECS"
#   period              = 60
#   statistic           = "Average"
#   threshold           = 70
#   alarm_description   = "Scale up vote-client if CPU > 70% for 2 minutes"
#   dimensions = {
#     ClusterName = aws_ecs_cluster.vote_cluster.name
#     ServiceName = aws_ecs_service.client_service.name
#   }
#   alarm_actions = [aws_appautoscaling_policy.vote_client_scale_up.arn]
# }

# resource "aws_cloudwatch_metric_alarm" "vote_client_cpu_low" {
#   alarm_name          = "vote-client-cpu-low"
#   comparison_operator = "LessThanThreshold"
#   evaluation_periods  = 2
#   metric_name         = "CPUUtilization"
#   namespace           = "AWS/ECS"
#   period              = 60
#   statistic           = "Average"
#   threshold           = 30
#   alarm_description   = "Scale down vote-client if CPU < 30% for 2 minutes"
#   dimensions = {
#     ClusterName = aws_ecs_cluster.vote_cluster.name
#     ServiceName = aws_ecs_service.client_service.name
#   }
#   alarm_actions = [aws_appautoscaling_policy.vote_client_scale_down.arn]
# }

# # Application Load Balancer
# resource "aws_lb" "vote_alb" {
#   name               = "vote-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = ["sg-0926150e1f3a73505"]
#   subnets            = ["subnet-02d3843dac4378d47", "subnet-01d044c1b449976ed"]
# }

# # Target Group for vote-client (frontend)
# resource "aws_lb_target_group" "vote_client_tg" {
#   name        = "vote-client-tg"
#   port        = 3000
#   protocol    = "HTTP"
#   target_type = "ip"
#   vpc_id      = "vpc-0d31decf8a4f43b3f"

#   health_check {
#     path                = "/"
#     interval            = 30
#     timeout             = 5
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#     matcher             = "200-499"
#   }
# }

# # ALB Listener (port 80 → frontend target group)
# resource "aws_lb_listener" "vote_alb_listener" {
#   load_balancer_arn = aws_lb.vote_alb.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.vote_client_tg.arn
#   }
# }

# # IAM Role for ECS Task Execution
# resource "aws_iam_role" "ecs_task_exec" {
#   name = "ecsTaskExecutionRole-tst"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Principal = {
#         Service = "ecs-tasks.amazonaws.com"
#       }
#       Effect = "Allow"
#     }]
#   })
# }

# resource "aws_cloudwatch_log_group" "vote_server_logs" {
#   name              = "/ecs/vote-server"
#   retention_in_days = 1
# }

# resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy" {
#   role       = aws_iam_role.ecs_task_exec.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# # Output the DNS Name of the Application Load Balancer
# output "alb_dns_name" {
#   description = "The DNS name of the Application Load Balancer used to access the ECS service."
#   value       = aws_lb.vote_alb.dns_name
# }