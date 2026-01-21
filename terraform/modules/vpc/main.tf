variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    name        = "${var.project_name}-${var.environment}-vpc"
    Environment = var.environment
  }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    name        = "${var.project_name}-${var.environment}-igw"
    Environment = var.environment
  }
}

#PUBLIC SUBNET (FOR NAT GATEWAY, IF NEEDED)
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index] # Fixed

  tags = {
    name        = "${var.project_name}-${var.environment}-public-${count.index + 1}"
    Environment = var.environment
    type        = "public"
  }
}

#PRIVATE SUBNET (FOR LAMBDA, IF VPC ACCESS NEEDED)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index] # Fixed

  tags = {
    name        = "${var.project_name}-${var.environment}-private-${count.index + 1}"
    Environment = var.environment
    type        = "private"
  }
}

#ROUTE TABLE FOR PUBLIC SUBNETS
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    name        = "${var.project_name}-${var.environment}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id # Fixed
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

#VPC ENDPOINTS FOR AWS SERVICES
resource "aws_vpc_endpoint" "S3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  route_table_ids = [aws_route_table.public.id]

  tags = {
    name = "${var.project_name}-${var.environment}-s3-endpoint"
  }
}

data "aws_region" "current" {}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id # Fixed
}

output "public_subnet_ids" {
  value = aaws_subnet.public[*].id # Fixed
}