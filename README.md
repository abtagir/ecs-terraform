AWS ECS Fargate Multi-Container Setup with ALB and Auto Scaling

This repository contains Terraform code to deploy an AWS ECS Fargate service running two containers behind an Application Load Balancer (ALB) with auto-scaling and CloudWatch monitoring.

Architecture Overview

ECS Cluster: ecs-tst with container insights enabled.

Containers:

first – Nginx container, exposed on port 80.

second – Custom container (devops-app), exposed on port 8080.

ALB:

Listens on ports 80 (for Nginx) and 8080 (for the second container).

Two target groups to route traffic to the respective containers.

Auto Scaling:

ECS service scales between 1 and 4 tasks based on CPU utilization.

CloudWatch alarms trigger scale-up (CPU > 70%) and scale-down (CPU < 30%).

Logging:

Both containers are configured to send logs to CloudWatch.

Prerequisites

Terraform v1.5+ installed

AWS CLI configured with sufficient permissions

Existing VPC with subnets and security groups

Docker image pushed to ECR (for second container)

Terraform Resources
ECS Cluster
resource "aws_ecs_cluster" "ecs_tst"


Enables container insights

Configures Fargate as the default capacity provider

ECS Task Definition
resource "aws_ecs_task_definition" "ecs_task_def"


Defines two containers (first and second)

Configures CPU, memory, logging, and port mappings

ECS Service
resource "aws_ecs_service" "ecs_service"


Launch type: FARGATE

Desired count: 2

Network configuration with public subnets and security groups

Load balancer configuration for both containers

Application Load Balancer
resource "aws_lb" "alb"


Public ALB with listeners on port 80 and 8080

Two target groups for routing traffic to respective containers

Health checks configured for the second container

Auto Scaling
resource "aws_appautoscaling_target" "ecs_autoscaling_target"
resource "aws_appautoscaling_policy" "ecs_scale_up"
resource "aws_appautoscaling_policy" "ecs_scale_down"


Scales ECS tasks based on CPU utilization

Scale-up and scale-down policies configured

CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm"


Monitors CPU utilization

Triggers ECS scaling policies

IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_exec"
resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy"


Allows ECS tasks to pull images and push logs to CloudWatch

Usage

Clone the repository:

git clone https://github.com/<your-org>/ecs-fargate-multi-container.git
cd ecs-fargate-multi-container


Initialize Terraform:

terraform init


Plan the deployment:

terraform plan


Apply the deployment:

terraform apply


Access the services:

Nginx container: http://<ALB-DNS>:80/

Second container: http://<ALB-DNS>:8080/

Notes

Ensure the security group allows inbound traffic on ports 80 and 8080.

The second container image must already exist in ECR.

Health checks for the second container are configured on /
