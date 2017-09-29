# You can have multiple ECS clusters in the same account with different resources.
# Therefore all resources created here have the name containing the name of the:
# environment, cluster name en the instance_group name.
# That is also the reason why ecs_instances is a seperate module and not everything is created here.

resource "aws_security_group" "instance" {
  name        = "${var.cluster}_inst_sg"
  description = "Used in ${var.cluster}"
  vpc_id      = "${var.vpc_id}"

  tags {
    Name          = "${var.cluster}_inst_sg"
  }
}

# We separate the rules from the aws_security_group because then we can manipulate the
# aws_security_group outside of this module
resource "aws_security_group_rule" "outbound_internet_access" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.instance.id}"
}

# Default disk size for Docker is 22 gig, see http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
resource "aws_launch_configuration" "launch" {
  name_prefix          = "${var.cluster}_lnch_cfg_"
  image_id             = "${var.aws_ami}"
  instance_type        = "${var.instance_type}"
  security_groups      = ["${aws_security_group.instance.id}"]
  user_data            = "${data.template_file.user_data.rendered}"
  iam_instance_profile = "${var.iam_instance_profile_id}"
  key_name             = "${var.key_name}"

  # aws_launch_configuration can not be modified.
  # Therefore we use create_before_destroy so that a new modified aws_launch_configuration can be created
  # before the old one get's destroyed. That's why we use name_prefix instead of name.
  lifecycle {
    create_before_destroy = true
  }
}

# Instances are scaled across availability zones http://docs.aws.amazon.com/autoscaling/latest/userguide/auto-scaling-benefits.html
resource "aws_autoscaling_group" "asg" {
  name                 = "${var.cluster}_asg"
  max_size             = "${var.max_size}"
  min_size             = "${var.min_size}"
  health_check_grace_period = "${var.EC2_hc_graceperiod}"
  desired_capacity     = "${var.desired_capacity}"
  force_delete         = true
  launch_configuration = "${aws_launch_configuration.launch.id}"
  vpc_zone_identifier  = ["${var.private_subnet_ids}"]
  load_balancers       = ["${var.load_balancers}"]

  tag {
    key                 = "Name"
    value               = "${var.cluster}_asg_inst"
    propagate_at_launch = "true"
  }

  # EC2 instances require internet connectivity to boot. Thus EC2 instances must not start before NAT is available.
  # For info why see description in the network module.
  tag {
    key                 = "DependsId"
    value               = "${var.depends_id}"
    propagate_at_launch = "false"
  }
}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/user_data.sh")}"

  vars {
    ecs_config        = "${var.ecs_config}"
    ecs_logging       = "${var.ecs_logging}"
    cluster_name      = "${var.cluster}_ecs_cluster"
    cluster           = "${var.cluster}"
    custom_userdata   = "${var.custom_userdata}"
    cloudwatch_prefix = "${var.cloudwatch_prefix}"
  }
}
