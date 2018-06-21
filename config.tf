provider "aws" {
  region  = "us-east-2"
  profile = "thegrommet"
  version = "~> 1.24"
}

provider "archive" {
  version = "~> 1.0"
}

provider "external" {
  version = "~> 1.0"
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
