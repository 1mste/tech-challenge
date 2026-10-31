# Mesma bucket do stack de infra, chave diferente.
terraform {
  backend "s3" {
    bucket       = "togglemaster-tfstate-698172256617"
    key          = "togglemaster/dev-addons/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
