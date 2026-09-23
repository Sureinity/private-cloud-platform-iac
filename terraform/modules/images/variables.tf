variable "target_node_name" {
  type = string
}

variable "download_timeout_seconds" {
  type = number
}

variable "import_images" {
  type = map(object({
    datastore_id = string
    url          = string
    file_name    = string
  }))
}
