terraform {
  backend "s3" {
    bucket = "sremt"
    key    = "metabase/terraform.tfstate"
    region = "us-east-1"
  }
}

module "metabase" {
  source             = "./module"
  public_subnet_ids  = ["${aws_subnet.a.id}","${aws_subnet.b.id}"]
  private_subnet_ids = ["${aws_subnet.a.id}","${aws_subnet.b.id}"]
  vpc_id             = aws_vpc.this.id
  domain             = "metabase.sremt.com"
  certificate_arn    = ""
  zone_id            = "metabase"
}

resource "aws_vpc" "this" {
  cidr_block = "172.31.0.0/16"
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet("172.31.32.0/20", 4, 0)
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet("172.31.0.0/20", 4, 1)
  availability_zone = "us-east-1b"
}

provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "aws"
      version = "5.32.1"
    }
  }
}
