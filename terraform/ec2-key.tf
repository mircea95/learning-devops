resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "generated_key" {
  key_name   = "windows-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
  depends_on = [tls_private_key.ec2_key]
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.ec2_key.private_key_pem
  filename = "${path.module}/windows-key.pem"
  depends_on = [aws_key_pair.generated_key]
}