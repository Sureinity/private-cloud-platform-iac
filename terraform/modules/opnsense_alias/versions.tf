terraform {
  required_version = "= 1.10.5"

  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "= 0.26.0"
    }
  }
}
