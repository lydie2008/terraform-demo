terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.71.0"
    }
  }
}

provider "aws" {
  region = var.regions
}


# 1- Create a VPC 

resource "aws_vpc" "terraform-demo-vpc" {
  cidr_block = var.vpc_cidr_block   "10.0.0.0/16"
  tags = {
  Name = var.vpc_name "terraform_demo"
  }
}

# 2- Create an Internet Gateway
resource "aws_internet_gateway" "mygw" {
  vpc_id = aws_vpc.terraform-demo-vpc.id

  tags = {
    Name = var.igw_name "terraform-demo-mygw"
  }
}

# 3 -Create a  public Subnet

resource "aws_subnet" "public" {
   vpc_id     = aws_vpc.var.vpc_name.id
   cidr_block = "10.0.1.0/24"
   availability_zone = "us-east-1a"

   tags = {
    Name = "my public subnet"
  }
}

# 4- create a private subnet 

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.var.vpc_name.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "my Private Subnet"
  }
}


# 5-Create a Route Table


 resource "aws_route_table" "terraform-demo-vpc_us_east_1a_private" {
    vpc_id = aws_vpc.var.vpc_name.id

    tags = {
        Name = "Local Route Table for Isolated Private Subnet"
    }
}

resource "aws_route_table_association" "var.vpc_name_us_east_1a_private" {
    subnet_id = aws_subnet.private.id
    route_table_id = aws_route_table.terraform-demo-vpc_us_east_1a_private.id
}


# 5.1 -Associate private subnet with Route Table

resource "aws_route_table" "my_vpc_us_east_1a_private" {
    vpc_id = aws_vpc.terraform-demo-vpc.id

    tags = {
        Name = "Local Route Table for Isolated Private Subnet"
    }


#5.2 create a loadbalancer (ELB)

resource "aws_security_group" "elb_name" {
  name        = "terraform-demo-elb"
  description = "Allow HTTP traffic to instances through Elastic Load Balancer"
  vpc_id = aws_vpc.var.vpc_name.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP through ELB Security Group"
  }
}

resource "aws_elb" "elb_name" {
  name = "var.vpc_name"
  security_groups = [
    aws_security_group.elb_http.id
  ]
  subnets = [
    aws_subnet.public_us_east_1a.id,
  ]

  cross_zone_load_balancing   = true

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }

}


# 6-Create A security Group to allow port 22, 80, 443

resource "aws_security_group" "allow_web" {
   name        = "allow_web_traffic"
   description = "Allow Web Inbound Traffic"
   vpc_id      = aws_vpc.var.vpc_name.id 

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   =80
    to_port     =80
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7-Create A Network Interface

resource "aws_network_interface" "prod-web" {
   subnet_id       = aws_subnet.subnet-terra.id
   private_ips     = ["10.0.1.50"]
   security_groups = [aws_security_group.allow_web.id]

}

# 8-Assign an elastic IP to the network Interface created in step 7

resource "aws_eip" "prodeip" {
   vpc                       = true
   network_interface         = aws_network_interface.prod-web.id
   associate_with_private_ip = "10.0.1.50"
   depends_on                = [aws_internet_gateway.gw]
}

# 9-Create a Ubuntu server and install/enable apache

resource "aws_instance" "my_first_terra" {
   ami           = "ami-00ddb0e5626798373"
   instance_type = "t2.micro"
   availability_zone = "us-east-1a"
   key_name = "aws keypair"

   tags = {
       Name = "web-server"
   }

   network_interface {
     device_index = 0
     network_interface_id = aws_network_interface.prod-web.id
   }

    user_data = <<-EOF
                  #!/bin/bash
                  sudo apt update -y
                  sudo apt install apache2 -y
                  sudo systemctl start apache2
                  sudo systemctl enable apache2
                  sudo bash -c 'echo your very first web server on terraform > /var/www/html/index.html'
                  EOF

}

# 10- create  ec2 instance 

resource "aws_instance" "my_instance" {
  ami           = "ami-0ac019f4fcb7cb7e6"
  instance_type = "t2.micro"
  key_name = "aws keypair "
  vpc_security_group_ids = [ aws_security_group.allow_ssh.id ]
  subnet_id = aws_subnet.public.id
  associate_public_ip_address = true

  tags = {
    Name = "My_instance"
  }
}

# 11 - allow instance to have connection from outside world

output "instance_public_ip" {
  value = "${aws_instance.my_instance.public_ip}"
}

#12 - ceate an autoscalling group 

resource "aws_autoscaling_group" "web" {
  name = "${aws_launch_configuration.web.name}-asg"

  min_size             = 1
  desired_capacity     = 2
  max_size             = 4
  
  health_check_type    = "ELB"
  load_balancers = [
    aws_elb.terraform-demo-elb.id
  ]

  launch_configuration = aws_launch_configuration.web.name

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
}

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  vpc_zone_identifier  = [
    aws_subnet.public_us_east_1a.id,
    aws_subnet.public_us_east_1b.id
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }

}



# attach ebs/root volume to instance

# Root volume

resource "aws_volume_attachment" "my-instance" {
 device_name = "/dev/sdc"
 volume_id = "${aws_ebs_volume.data-vol.id}"
 instance_id = "${aws_instance.my-instance .id}"

      device_name = "/dev/xvda"
      no_device   = 0
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 20
        volume_type           = "gp2"
      }
      }, {
      device_name = "/dev/sda1"
      no_device   = 1
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 30
        volume_type           = "gp2"
      }
    }



#launch configuration 

data "aws_ami" "ubuntu" {
  most_recent = true

 
resource "aws_launch_configuration" "launch.congig" {
  name_prefix   = "launch.config"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                 = "web"
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 1
  max_size             = 2

  lifecycle {
    create_before_destroy = true
  }
}



