# --- Application Load Balancer ---
resource "aws_lb" "vote_alb" {
  name               = "vote-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

# --- Target Group for vote-client (Frontend) ---
resource "aws_lb_target_group" "vote_client_tg" {
  name        = "vote-client-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vote_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-499"
  }
}

# --- Target Group for vote-server (Backend) ---
resource "aws_lb_target_group" "vote_server_tg" {
  name        = "vote-server-tg"
  port        = 5000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vote_vpc.id

  health_check {
    path                = "/results"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-499"
  }
}

# --- ALB Listener (port 80) ---
resource "aws_lb_listener" "vote_alb_listener" {
  load_balancer_arn = aws_lb.vote_alb.arn
  port              = 80
  protocol          = "HTTP"

  # Default route -> Frontend
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote_client_tg.arn
  }
}

# --- Listener Rule: Route /api/* to Backend ---
resource "aws_lb_listener_rule" "vote_server_rule" {
  listener_arn = aws_lb_listener.vote_alb_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote_server_tg.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
