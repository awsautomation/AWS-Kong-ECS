provider "aws" {
    region      = "${var.region}"
    access_key = "AKIA3T3H7KH5ET6HTT55"
 secret_key = "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"
  profile = "dev"
    
}
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
