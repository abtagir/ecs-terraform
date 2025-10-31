resource "aws_ecs_cluster" "ecs_tst" {
  name = "ecs-tst"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs_capacity" {
  cluster_name = aws_ecs_cluster.ecs_tst.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "ecs_task_def" {
  family = "ecs-tst-service-task"
  container_definitions = jsonencode([
    {
    name      = "first"
    image     = "nginx:latest"
    essential = true
    portMappings = [{ containerPort = 80 }]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = "/ecs/ecs-tst-service-task"
        "awslogs-region"        = "eu-central-1"
        "awslogs-stream-prefix" = "ecs"
      }
   }
},
  {
    name      = "second"
    image     = "tomacat:latest"
    essential = true
    portMappings = [{ containerPort = 8080 }]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = "/ecs/ecs-tst-service-task"
        "awslogs-region"        = "eu-central-1"
        "awslogs-stream-prefix" = "ecs"
      }
   }    
  }
  ])

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  task_role_arn            = aws_iam_role.ecs_task_exec.arn
}

resource "aws_ecs_service" "ecs_service" {
  name            = "ecs-tst-service"
  cluster         = aws_ecs_cluster.ecs_tst.id
  task_definition = aws_ecs_task_definition.ecs_task_def.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets          = ["subnet-02d3843dac4378d47", "subnet-01d044c1b449976ed"]
    security_groups  = ["sg-0926150e1f3a73505"]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alb_target_group1.arn
    container_name   = "first"
    container_port   = 80
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alb_target_group2.arn
    container_name   = "second"
    container_port   = 8080
  }

  depends_on = [aws_ecs_cluster_capacity_providers.ecs_capacity]
}

resource "aws_appautoscaling_target" "ecs_autoscaling_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.ecs_tst.name}/${aws_ecs_service.ecs_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_scale_down" {
  name               = "scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_autoscaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_autoscaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_autoscaling_target.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_scale_up" {
  name               = "scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_autoscaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_autoscaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_autoscaling_target.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale up if CPU > 70% for 2 minutes"
  dimensions = {
    ClusterName = aws_ecs_cluster.ecs_tst.name
    ServiceName = aws_ecs_service.ecs_service.name
  }
  alarm_actions = [aws_appautoscaling_policy.ecs_scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale down if CPU < 30% for 2 minutes"
  dimensions = {
    ClusterName = aws_ecs_cluster.ecs_tst.name
    ServiceName = aws_ecs_service.ecs_service.name
  }
  alarm_actions = [aws_appautoscaling_policy.ecs_scale_down.arn]
}


resource "aws_lb" "alb" {
  name               = "ecs-tst-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-0926150e1f3a73505"]
  subnets            = ["subnet-02d3843dac4378d47", "subnet-01d044c1b449976ed"]
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group1.arn
  }
}

resource "aws_lb_target_group" "alb_target_group1" {
  name        = "alb-target-group-first"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "vpc-0d31decf8a4f43b3f"
}

resource "aws_lb_target_group" "alb_target_group2" {
  name        = "alb-target-group-second"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "vpc-0d31decf8a4f43b3f"
}

resource "aws_lb_listener_rule" "alb_listener_rule_2" {
  listener_arn = aws_lb_listener.alb_listener.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group2.arn
  }

  condition {
    path_pattern {
      values = ["/second*"]
    }
  }
}

resource "aws_iam_role" "ecs_task_exec" {
  name = "ecsTaskExecutionRole-tst"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
