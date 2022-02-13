terraform {
  backend "s3" {
    bucket         = "terrafrom-state.app.canadaveinclinics.ca"
    key            = "infra-github/terraform.tfstate"
    region         = "us-east-1"
    access_key     = ${{ secrets.AWS_ACCESS_KEY_ID }}
    secret_key     = ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  }
}



locals {
  base_name = "devops-challenge"
  region = "us-east-1"
  base_description = "devops-challenge-rubyrails"
}

provider "aws" {
   region         = "us-east-1"
   access_key     = ${{ secrets.AWS_ACCESS_KEY_ID }}
   secret_key     = ${{ secrets.AWS_SECRET_ACCESS_KEY }}
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
  vpc_id            = aws_vpc.main.vpc_id
  cidr_block        = "10.1.32.0/20"
  availability_zone = [us-east-1a, us-east-1b]
  map_public_ip_on_launch = true
}

#Route tables and associations
resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.main.vpc_id
  tags = merge(
    {
      "Name" = "igw"
    },
    var.extra_tags,
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.vpc_id
  tags = merge(
    {
      "Name" = "routetbl-public"
    },
    var.extra_tags,
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


