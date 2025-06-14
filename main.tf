terraform {
  required_version = ">= 1.1.0"

  required_providers {
    aws = {
      source  = "registry.opentofu.org/hashicorp/aws"
      version = "5.99.1"  # Match provider version recorded in state
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# RDS PostgreSQL instance
resource "aws_db_instance" "postgresql" {
  identifier                = "db-xyd"
  engine                    = "postgres"
  engine_version            = "17.4"
  instance_class            = "db.t3.micro"
  allocated_storage         = 20
  storage_type              = "gp2"

  db_name                   = "devdb"
  username                  = "postgresadmin"
  password                  = "SuperSecure123!"
  port                      = 5432

  publicly_accessible       = false
  skip_final_snapshot       = true
  deletion_protection       = false
  backup_retention_period   = 0
  multi_az                  = false
  auto_minor_version_upgrade = true
}

# Data source: default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Ubuntu 20.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

# Security group for EC2 to access RDS and SSH
resource "aws_security_group" "ec2_sg" {
  name        = "allow_postgres_accessXYD"
  description = "Allow SSH inbound and Postgres outbound"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
}

# Ubuntu EC2 instance that writes dummy data to RDS
resource "aws_instance" "ubuntu" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]


  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y postgresql-client
    export PGPASSWORD="SuperSecure123!"
    psql -h ${aws_db_instance.postgresql.address} -U postgresadmin -d devdb -p 5432 -c "CREATE TABLE IF NOT EXISTS dummy_data (id SERIAL PRIMARY KEY, info TEXT);"
    psql -h ${aws_db_instance.postgresql.address} -U postgresadmin -d devdb -p 5432 -c "INSERT INTO dummy_data (info) VALUES ('Automated dummy data from Terraform');"
  EOF

  tags = {
    Name = "Ubuntu-For-RDS-Dummy"
  }
}

# Outputs
output "rds_endpoint" {
  value = aws_db_instance.postgresql.endpoint
}

output "ubuntu_public_ip" {
  value = aws_instance.ubuntu.public_ip
}
