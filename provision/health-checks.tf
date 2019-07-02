resource "aws_route53_health_check" "secure_website" {
  fqdn              = "example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = "5"
  request_interval  = "30"
}

resource "aws_route53_health_check" "website" {
  fqdn              = "example.com"
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = "5"
  request_interval  = "30"
}
