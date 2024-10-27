packer {
  required_plugins {
    tart = {
      version = ">= 1.14.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "username" {
  type    = string
  default = "distiller"
}

variable "password" {
  type    = string
  default = "distiller"
}

variable "disk_free_mb" {
  type    = number
  default = 30000
}

variable "node_versions" {
  type    = list(string)
  default = ["20.18"]
}

variable "ruby_version" {
  type    = string
  default = "3.3.5"
}

variable "python_version" {
  type    = string
  default = "3.12"
}

variable "xcode_versions" {
  type    = list(string)
  default = ["15.2", "16"]
}

source "tart-cli" "tart" {
  vm_base_name = "sonoma-base"
  vm_name      = "sonoma-circleci"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 100
  ssh_password = var.password
  ssh_username = var.username
  ssh_timeout  = "120s"
}

locals {
  xcode_install_provisioners = [
    for version in reverse(sort(var.xcode_versions)) : {
      type = "shell"
      inline = [
        "source ~/.zprofile",
        "sudo xcodes install ${version} --experimental-unxip --path /Users/${var.username}/Downloads/Xcode_${version}.xip --select --empty-trash",
        "INSTALLED_PATH=$(xcodes select -p)",
        "CONTENTS_DIR=$(dirname $INSTALLED_PATH)",
        "APP_DIR=$(dirname $CONTENTS_DIR)",
        "sudo mv $APP_DIR /Applications/Xcode_${version}.app",
        "sudo xcode-select -s /Applications/Xcode_${version}.app",
        "xcodebuild -downloadPlatform iOS visionOS",
        "xcodebuild -runFirstLaunch",
      ]
    }
  ]
  node_install_provisioners = [
    for version in reverse(sort(var.node_versions)) : {
      type = "shell"
      inline = [
        "source ~/.zprofile",
        "nvm install ${version}",
      ]
    }
  ]
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh"
    ]
  }
  provisioner "file" {
    source      = "data/.ssh/config"
    destination = "~/.ssh/config"
  }
  # Create a symlink for bash compatibility
  provisioner "shell" {
    inline = [
      "touch ~/.zprofile",
      "ln -s ~/.zprofile ~/.profile",
    ]
  }
  provisioner "shell" {
    inline = [
      "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
      "echo \"export LANG=en_US.UTF-8\" >> ~/.zprofile",
      "echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile",
      "echo \"export HOMEBREW_NO_AUTO_UPDATE=1\" >> ~/.zprofile",
      "echo \"export HOMEBREW_NO_INSTALL_CLEANUP=1\" >> ~/.zprofile",
      "source ~/.zprofile",
      "brew --version",
      "brew update",
      "brew install autoconf ca-certificates carthage gettext git git-lfs jq libidn2 libunistring libyaml m4 nvm oniguruma openssl@3 pcre2 pyenv rbenv readline wget xz yarn temurin xcodesorg/made/xcodes",
      "sudo softwareupdate --install-rosetta --agree-to-license"
    ]
  }
  # Ruby
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "echo 'eval \"$(rbenv init -)\"' >> ~/.zprofile",
      "source ~/.zprofile",
      "rbenv install ${var.ruby_version}",
      "rbenv global ${var.ruby_version}",
      "gem install bundler",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "gem update",
      "gem install fastlane:2.222 cocoapods:1.15",
      "gem uninstall --ignore-dependencies ffi && gem install ffi -- --enable-libffi-alloc"
    ]
  }
  # Node
  provisioner "shell" {
    inline = [
      "echo 'export NVM_DIR=\"$HOME/.nvm\"' >> ~/.zprofile",
      "echo '[ -s \"/opt/homebrew/opt/nvm/nvm.sh\" ] && . \"/opt/homebrew/opt/nvm/nvm.sh\"' >> ~/.zprofile",
    ]
  }
  dynamic "provisioner" {
    for_each = local.node_install_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "nvm use '${var.node_versions[0]}'",
    ]
  }
  # Python
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "echo 'eval \"$(pyenv init -)\"' >> ~/.zprofile",
      "pyenv install ${var.python_version}",
      "pyenv rehash",
      "pyenv global ${var.python_version}",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "curl -o AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
      "curl -o DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer",
      "curl -o add-certificate.swift https://raw.githubusercontent.com/actions/runner-images/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/add-certificate.swift",
      "swiftc -suppress-warnings add-certificate.swift",
      "sudo ./add-certificate AppleWWDRCAG3.cer",
      "sudo ./add-certificate DeveloperIDG2CA.cer",
      "rm add-certificate* *.cer"
    ]
  }
  provisioner "shell" {
    inline = [
      "curl -so circleci-runner.tar.gz -L https://circleci-binary-releases.s3.amazonaws.com/circleci-runner/current/circleci-runner_darwin_arm64.tar.gz",
      "tar -xzf circleci-runner.tar.gz --directory ~/",
      "rm -f circleci-runner.tar.gz"
    ]
  }
  provisioner "file" {
    sources     = [for version in var.xcode_versions : pathexpand("~/Downloads/Xcode_${version}.xip")]
    destination = "/Users/${var.username}/Downloads/"
  }
  dynamic "provisioner" {
    for_each = local.xcode_install_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "sudo xcodes select '${var.xcode_versions[0]}'",
    ]
  }
  provisioner "shell" {
    inline = [
      "sudo chsh -s /bin/bash ${var.username}"
    ]
  }
  // check there is at least 30GB of free space and fail if not
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "df -h",
      "export FREE_MB=$(df -m | awk '{print $4}' | head -n 2 | tail -n 1)",
      "[[ $FREE_MB -gt ${var.disk_free_mb} ]] && echo OK || exit 1"
    ]
  }
}
