resource "aws_instance" "windows" {
  ami                         = var.windows_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.generated_key.key_name
  subnet_id                   = data.aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.windows_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size
    delete_on_termination = true
  }

  tags = {
    Name = "WebApp"
  }
  user_data = templatefile("${path.module}/files/user_data.tpl", {
    generate_send_prometheus_data_script = file("${path.module}/files/Send-PrometheusData.ps1"),
    generate_iis_dump_script             = file("${path.module}/files/Generate-IIS-Dump.ps1"),
    generate_iis_report_script           = file("${path.module}/files/Generate-IIS-Report.ps1"),
    configure_winrm_script               = file("${path.module}/files/Confiure-WinRM.sp1"),
    install_iss                          = file("${path.module}/files/Install-IIS.sp1"),
    install_app                          = file("${path.module}/files/Install-app.sp1"),
    scheduled_task                       = file("${path.module}/files/Scheduled-Task.sp1")
  })

  # lifecycle {
  #   create_before_destroy = false
  # }

  depends_on = [
    tls_private_key.ec2_key,
    aws_security_group.windows_sg
  ]
}
