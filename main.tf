terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

# Provider
provider "aws" {
  region = "ap-south-1"
  profile = "default"
}
  
# FOR INSTANCES

# resource "<provider>_<resource_type" "name" {
#   config options....
#   key - values pairs.
# }

# VPC
resource "aws_vpc" "main-vpc" {
    cidr_block = "10.0.0.0/16"

    tags = {
        Name = "Main VPC"
    }
}

# Internet Gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main-vpc.id

  tags = {
    Name = "IGW"
  }
}

# Route Table

resource "aws_route_table" "route-table" {
  vpc_id = aws_vpc.main-vpc.id

  # For IPv4
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  # For IPv6
  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Route-Table"
  }
}

# Security Group for ELB

resource "aws_security_group" "elb" {
  name        = "elb_sg"
  description = "Used in the terraform"

  vpc_id = aws_vpc.main-vpc.id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ensure the VPC has an Internet gateway or this step will fail
  depends_on = [aws_internet_gateway.gw]
}

# Elastic Load Balancer

resource "aws_elb" "ec2-elb" {
  name               = "foobar-terraform-elb"

  subnets = [aws_subnet.ec2-subnet.id]
  security_groups = [aws_security_group.elb.id]

  # access_logs {
  #   bucket        = "foo"
  #   bucket_prefix = "bar"
  #   interval      = 60
  # }

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  # listener {
  #   instance_port      = 8000
  #   instance_protocol  = "http"
  #   lb_port            = 443
  #   lb_protocol        = "https"
  #   ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  # }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  instances                   = [aws_instance.ec-2[0].id, aws_instance.ec-2[1].id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "Elastic Load Balancer"
  }
}

# Subnet

resource "aws_subnet" "ec2-subnet" {
  vpc_id     = aws_vpc.main-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "EC2 subnet"
  }
}

# Route Table Assosciation for subnet

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.ec2-subnet.id
  route_table_id = aws_route_table.route-table.id
}

# Security group
# PORTS {22 - > SSH, 80 - > HTTP, 443 - > TCP, 3306 - > AWS DB}
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24", "10.0.3.0/24"]
  }

  tags = {
    Name = "Allow web"
  }
}

# Network Interface

# resource "aws_network_interface" "ni" {
#   subnet_id       = aws_subnet.ec2-subnet.id
#   private_ips     = ["10.0.1.50"]
#   security_groups = [aws_security_group.allow_web.id]
# }

# # EIP Assosciation

# resource "aws_eip_association" "myeip-1" {
#   instance_id   = aws_instance.ec-2[0].id
#   allocation_id = aws_eip.elastic_ip.id
# }

# resource "aws_eip_association" "myeip-2" {
#   instance_id   = aws_instance.ec-2[1].id
#   allocation_id = aws_eip.elastic_ip.id
# }

# EC2 Instance 

resource "aws_instance" "ec-2" {
  ami           = "ami-0d758c1134823146a"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "terra-key"
  count = 2

  # network_interface {
  #   network_interface_id = aws_network_interface.ni.id
  #   device_index         = 0
  # }

  # NEW
  vpc_security_group_ids = [aws_security_group.allow_web.id]
  subnet_id              = aws_subnet.ec2-subnet.id

  tags = {
    Name = "Database Server"
  }

  # provisioner "file" {
  #   source      = "./node"
  #   destination = "/home/ec2-user/app"

  #   connection {
  #     type     = "ssh"
  #     host = self.public_ip
  #     user     = "ec2-user"
  #     private_key = "${file("~/.ssh/id_rsa")}"
  #   }
  # }

  # provisioner "remote-exec" {
  #   inline = [
  #     "sudo apt-get update",
  #     "sudo apt-get install nodejs",
  #     "sudo apt-get install npm",
  #     "sudo npm install express",
  #     "sudo npm install mysql",
  #     "cd /home/ec2-user/app",
  #     "node index.js"
  #   ]

  #   connection {
  #     type     = "ssh"
  #     host = self.public_ip
  #     user     = "ec2-user"
  #     private_key = "${file("~/.ssh/id_rsa")}"
  #   }
  # }
}

# Elastic IP

# resource "aws_eip" "elastic_ip" {
#   vpc                       = true
#   network_interface         = aws_network_interface.ni.id
#   associate_with_private_ip = "10.0.1.50"
#   depends_on = [aws_internet_gateway.gw]
# }

# ------------------------------------------------------------------------------

# Subnet for DB
resource "aws_subnet" "DB-subnet-1" {
  vpc_id = aws_vpc.main-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "DB Subnet"
  }
}

resource "aws_subnet" "DB-subnet-2" {
  vpc_id = aws_vpc.main-vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "DB Subnet"
  }
}

resource "aws_db_subnet_group" "DB-subnet-group" {
  name       = "main"
  subnet_ids = [aws_subnet.DB-subnet-1.id,aws_subnet.DB-subnet-2.id]

  tags = {
    Name = "DB subnet group"
  }
}

# Security group
# PORTS {3306 - > SQL}
resource "aws_security_group" "allow_db" {
  name        = "allow_db_traffic"
  description = "Allow Database traffic"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description = "SQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.2.0/24"]
  }

  tags = {
    Name = "Allow DB"
  }
}

resource "aws_db_instance" "DB" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0.20"
  instance_class       = "db.t2.micro"
  name                 = "mydb"
  username             = "admin"
  password             = "adminadmin"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.DB-subnet-group.id
  vpc_security_group_ids = [aws_security_group.allow_db.id]
}

