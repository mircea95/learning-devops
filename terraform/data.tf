data "aws_subnet" "public" {
  filter {
    name   = "tag:Name"
    values = ["peg-shared-public-euw1-az3"]
  }
}

data "aws_vpc" "by_tag" {
  filter {
    name   = "tag:Environment"
    values = ["shared"]
  }
}

