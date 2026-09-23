resource "proxmox_download_file" "import_image" {
  for_each = var.import_images

  content_type = "import"
  datastore_id = each.value.datastore_id
  node_name    = var.target_node_name

  url            = each.value.url
  file_name      = each.value.file_name
  overwrite      = false
  upload_timeout = var.download_timeout_seconds
}
