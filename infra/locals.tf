locals {
  subdomain = var.environment == "prod" ? "quest" : "quest-${var.environment}"
}