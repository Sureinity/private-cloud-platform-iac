output "import_images" {
  value = {
    for name, image in proxmox_download_file.import_image : name => {
      file_id   = image.id
      file_name = image.file_name
    }
  }
}
