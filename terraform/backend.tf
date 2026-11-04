terraform {
  #Uncomment when you have a remote backend set up
  backend "s3" {
    bucket         = "top-secret-terraform-state"
    key            = "terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    use_lockfile   = true
  }
}