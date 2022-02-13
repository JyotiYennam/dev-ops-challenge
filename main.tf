#******************************* S3 bucket to store terraform state files **********************************
terraform {
  backend "s3" {
    bucket         = "terrafrom-state.app.devopschallenge"
    key            = "infra-github/terraform.tfstate"
    region         = "us-east-1"
  }
}

provider "aws" {
   region = "us-east-1"
 }

#****************************** DB credentials stored in AWS Secrets Manager ********************************
data "aws_secretsmanager_secret" "db-credentials" {
  name = "mejuri.db.credentials"
}
data "aws_secretsmanager_secret_version" "db-credentials" {
  secret_id = data.aws_secretsmanager_secret.db-credentials.id
}

#**************** Locals - Setting db credentials as environment variables and environment secrets ***********
locals {
  db-credentials = jsondecode(data.aws_secretsmanager_secret_version.db-credentials.secret_string)
  environment_variables = {
    host= "mejuri-db.c36vme4j5fab.us-east-1.rds.amazonaws.com" #rds endpoint
  }
  environment_secrets = {
    username = "${data.aws_secretsmanager_secret_version.db-credentials.arn}:username::"
    password = "${data.aws_secretsmanager_secret_version.db-credentials.arn}:password::"
  }
  secret_arns = [data.aws_secretsmanager_secret_version.db-credentials.arn]
  
#****Setting env vars and secrets into container definition*****
  secrets_keys = keys(local.environment_secrets)
  secrets_map = [
  for key in local.secrets_keys :  {
    name : key,
    valueFrom : local.environment_secrets[key]
  }
  ]
  secret_env_str = jsonencode(local.secrets_map)
	  
  env_keys = keys(local.environment_variables)
  env_map = [
  for key in local.env_keys :  {
    name : key,
    value : local.environment_variables[key]
  }
  ]
  env_str = jsonencode(local.env_map)
    
  #*****Defining container definition******
  container_definitions = <<EOF
  [{
      "name": "mejuri-rails-container",
      "image": "097331659702.dkr.ecr.us-east-1.amazonaws.com/mejuri-ecr",
      "essential": true,
      "environment" :  ${local.env_str},
     "secrets" :  ${local.secret_env_str},
      "cpu": 256,
      "memory": 512,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "us-east-1",
          "awslogs-group": "${aws_cloudwatch_log_group.ecs.name}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }]
  EOF
}


#************************************************ NETWORK COMPONENTS *******************************************************
#********** VPC ***********
resource "aws_vpc" "main" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    {
      "Name" = "vpc"
    }
  )
}



#********** Subnets ***********
resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.32.0/20"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}



#*********** Route tables and associations ***********
resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    {
      "Name" = "igw"
    }
  )
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    {
      "Name" = "routetbl-public"
    }
  )
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.public.id
  depends_on             = [aws_route_table.public]
}



#******************************************************** RDS - DATABASE ******************************************************
#*********** RDS (Database - postgresql 11.6)****************
resource "aws_security_group" "rdssc" {
  name   = "rds-securitygroup"
  vpc_id = aws_vpc.main.id
  description = "security group for rds"

  tags = merge(
    {
      "Name" = "DB Security Group"
    }
  )
}
# Open ingress traffic SSH port
resource "aws_security_group_rule" "open_ingress" {
  depends_on        = [aws_security_group.rdssc]
  type              = "ingress"
  description       = "Open Input for 5432 "
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["10.1.0.0/16"]
  security_group_id = aws_security_group.rdssc.id
}
# Open egress traffic
resource "aws_security_group_rule" "open_egress" {
  depends_on        = [aws_security_group.rdssc]
  type              = "egress"
  description       = "OPEN egress, all ports, all protocols"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rdssc.id
}
resource "aws_db_subnet_group" "db_subnet" {
  name_prefix = "subnet-grp"
  description = "Database subnet group for rds"
  subnet_ids  = [aws_subnet.main.id, "subnet-02e9e21ce3767b219"]
}
#RDS instance
resource "aws_db_instance" "default" {
  identifier = "mejuri-db"
  instance_class = "db.t2.micro"
  allocated_storage = 5
  username = local.db-credentials.username
  password = local.db-credentials.password
  port = 5432
  engine    = "postgres"
  engine_version = "11.6"
  storage_type  = "gp2"
  iam_database_authentication_enabled = false
  storage_encrypted = false
  vpc_security_group_ids = [aws_security_group.rdssc.id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet.id
  availability_zone   = "us-east-1a"
  multi_az            = false
  iops                = 0
  publicly_accessible = true
  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
  apply_immediately           = true
  maintenance_window          = "Mon:00:00-Mon:03:00"
  deletion_protection         = false
  copy_tags_to_snapshot       = true
  backup_retention_period = 30
  backup_window           = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}


#**************************************************** ELASTIC CONTAINER REGISTRY ******************************************
#************ ECR ****************
resource "aws_ecr_repository" "main" {
  name = "mejuri-ecr"
}

resource "aws_ecr_repository_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "new policy",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeRepositories",
                "ecr:GetRepositoryPolicy",
                "ecr:ListImages",
                "ecr:DeleteRepository",
                "ecr:BatchDeleteImage",
                "ecr:SetRepositoryPolicy",
                "ecr:DeleteRepositoryPolicy"
            ]
        }
    ]
}
EOF
}



#************************************************ ECS (Elastic Container Service)*******************************************
#****** Elastic Container Service ********
resource "aws_cloudwatch_log_group" "ecs" {
  name              =  "mejuri-rails-api-ecs-service"
  retention_in_days = 7
}
resource "aws_ecs_task_definition" "ecs" {
  family = "mejuri-api"
  requires_compatibilities = ["FARGATE"]

  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  container_definitions    = local.container_definitions
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

}
resource "aws_ecs_service" "ecs" {
  name            = "mejuri-rails-api-ecs-service"
  cluster         = aws_ecs_cluster.ecs.arn
  task_definition = aws_ecs_task_definition.ecs.arn
  desired_count = 1
  force_new_deployment = true
  launch_type = "FARGATE"
  propagate_tags = "SERVICE"
  wait_for_steady_state = false
  network_configuration {
	security_groups = [aws_security_group.ecs-sg.id]
	subnets         = [aws_subnet.main.id]
	assign_public_ip = true
  }
  lifecycle {
      ignore_changes = [desired_count]
  }
}
resource "aws_ecs_cluster" "ecs" {
  name =  "mejuri-ecs-cluster"
  capacity_providers = ["FARGATE"]
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base = 0
    weight = 1
  }
}
### Security Group
resource "aws_security_group" "ecs-sg" {
  name   = "mejuri-rails-api-sg"
  vpc_id = aws_vpc.main.id
  tags = merge(
   {
     "Name" = "ECS Security Group"
   }
 )
}
data "aws_iam_policy_document" "task-assume-role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "mejuri-ecs_task_execution_role"
  assume_role_policy = data.aws_iam_policy_document.task-assume-role.json
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "ecs_secretsmanager_policy" {
  role = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
    {
      Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
      ]
      Effect   = "Allow"
      Resource = local.secret_arns
      },
    ]
  })
}
