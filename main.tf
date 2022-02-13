#S3 bucket to store terraform state files
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


#VPC
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


#Subnets
resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.32.0/20"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}


#Route tables and associations
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


#RDS
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

resource "aws_db_instance" "default" {
  identifier = "mejuri-db"
  instance_class = "db.t2.micro"
  allocated_storage = 5
  username = "mejuriuser"
  password = "test12345"
  port = 5432
  engine    = "postgres"
  engine_version = "11.6"
  storage_type  = "gp2"
  iam_database_authentication_enabled = false
  storage_encrypted = false
  vpc_security_group_ids = [aws_security_group.rdssc.id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet.id
  availability_zone   = "us-east-1"
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
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
}
