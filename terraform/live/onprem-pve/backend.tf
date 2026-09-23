terraform {
  backend "s3" {
    bucket   = "sample-tfstate"
    key      = "live/onprem-pve/terraform.tfstate"
    region   = "us-east-1"
    endpoint = "http://192.0.2.51:8333"

    # SeaweedFS S3 compatibility requirements
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
