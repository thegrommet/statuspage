provider "aws" {
  region  = "us-west-2"
  profile = "thegrommet"
  version = "~> 2.7"
}

provider "archive" {
  version = "~> 1.2"
}

provider "external" {
  version = "~> 1.2"
}

terraform {
  backend "s3" {
    bucket     = "devops.thegrommet.com"
    key        = "terraform/statuspage.tfstate"
    region     = "us-east-1"
    profile    = "thegrommet"
    encrypt    = true
    kms_key_id = "alias/thegrommet/vault-production"
  }
}

