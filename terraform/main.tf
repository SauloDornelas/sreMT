terraform {
  backend "s3" {
    bucket = "sremt"
    key    = "metabase/terraform.tfstate"
    region = "us-east-1"
  }
}

module "metabase" {
  source             = "./module"
  public_subnet_ids  = data.aws_subnets.a.ids
  public_subnet_ids_2 = data.aws_subnets.b.ids
  vpc_id             = data.aws_vpc.this.id
  domain             = ""
  certificate_arn    = ""
  zone_id            = ""
}

data "aws_vpc" "this" {
  default = true
}

data "aws_subnets" "a" {
  filter {
    name   = "tag:Name"    
    values = ["subnet-us-east-*"]
  }
}

data "aws_subnets" "b" {
  filter {
    name   = "tag:Name"
    values = ["subnet-us-east-*"]
  }
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
