packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.9"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "histomics-worker" {
  instance_type = "t3.medium"
  region        = "us-east-1"
  source_ami    = "ami-026457321d1cd1b49"
  ssh_username  = "ubuntu"
  ami_name      = "${source.name}-${formatdate("YYYY.MM.DD-hh.mm.ss", timestamp())}"
}

build {
  name = "worker-release"

  source "source.amazon-ebs.histomics-worker" {
    name            = "worker-release"
  }

  provisioner "ansible" {
    playbook_file = "${path.root}/provision/ec2-playbook.yml"

    user      = build.User
    use_proxy = false
  }
}
