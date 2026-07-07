terraform {
  backend "s3" {
    bucket         = "stratum-tfstate-7pbqp4"
    key            = "platform-networking.tfstate"
    region         = "us-east-1"
    dynamodb_table = "stratum-tfstate-lock"
    encrypt        = true
  }
}
