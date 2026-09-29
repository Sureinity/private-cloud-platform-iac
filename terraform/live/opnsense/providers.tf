provider "opnsense" {
  uri            = var.opnsense_url
  api_key        = var.opnsense_api_key
  api_secret     = var.opnsense_api_secret
  allow_insecure = var.opnsense_allow_insecure
}
