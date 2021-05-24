# ****** ACM ******
data "aws_acm_certificate" "default" {
  domain   = "nicholashofbauer.com"
}

# ****** VPC ******
data "aws_vpc" "default" {
  state = "available"
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

# ****** ROUTE53 ******
data "aws_route53_zone" "default" {
  name         = "nicholashofbauer.com."
}