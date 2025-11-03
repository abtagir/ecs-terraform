output "alb_dns_name" {
  description = "Application Load Balancer URL"
  value       = aws_lb.vote_alb.dns_name
}
