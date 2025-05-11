output "public_ip" {
  value = aws_instance.windows.public_ip
}

output "private_key_path" {
  value = local_file.private_key_pem.filename
}
