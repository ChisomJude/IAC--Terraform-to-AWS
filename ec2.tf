# Data source for latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# EC2 Instances
resource "aws_instance" "app" {
  count                  = var.instance_count
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_name 
  
  user_data = templatefile("${path.module}/scripts/user_data.sh", {
    github_repo   = var.github_repo
    github_branch = var.github_branch
    app_port      = var.app_port
    project_name  = var.project_name
    environment   = var.environment
  })

  monitoring = var.enable_monitoring

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-${var.environment}-root-volume-${count.index + 1}"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-instance-${count.index + 1}"
    Application = var.project_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer (optional)
resource "aws_lb" "app" {
  count              = var.create_alb ? 1 : 0
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "app" {
  count    = var.create_alb ? 1 : 0
  name     = "${var.project_name}-${var.environment}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200-299"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

# ALB Listener
resource "aws_lb_listener" "app" {
  count             = var.create_alb ? 1 : 0
  load_balancer_arn = aws_lb.app[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "app" {
  count            = var.create_alb ? var.instance_count : 0
  target_group_arn = aws_lb_target_group.app[0].arn
  target_id        = aws_instance.app[count.index].id
  port             = var.app_port
}

# Elastic IP for instances
resource "aws_eip" "app" {
  count    = var.instance_count
  instance = aws_instance.app[count.index].id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}