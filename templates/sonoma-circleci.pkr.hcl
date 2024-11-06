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
  default = "distiller" # TODO: CHANGE PASSWORD
}

variable "disk_free_mb" {
  type    = number
  default = 30000
}

variable "node_versions" {
  type    = list(string)
  # First version is default
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

variable "xcodes" {
  type    = list(string)
  # First version (xcodes[0]) is default
  default = [
    "15.2",
    "16",
    # We need to install Xcode 16.1 in order to download runtimes
    # We'll remove it later on to save disk space
    "16.1",
  ] 
}

variable "uninstall_xcode_16_1_after_runtime_downloads" {
  type    = bool
  default = true
}

variable "xcode_runtimes" {
  type = map(list(string))
  default = {
    "iOS" = [
      "17.2",
      "18.0"
    ]
    "visionOS" = [
      "1.0",
      "2.0"
    ]
  }
}

variable "fastlane_gem_version" {
  type    = string
  default = "2.222"
}

variable "cocoapods_gem_version" {
  type    = string
  default = "1.15"
}

variable "circleci_machine_runner_version" {
  type    = string
  default = "current"
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
  # Get all Xcode versions sorted in reverse order
  xcode_versions = reverse(sort(var.xcodes))
  
  # Create installation steps for each Xcode version
  xcode_install_commands = [
    for version in local.xcode_versions : {
      type = "shell"
      inline = [
          "source ~/.bash_profile",
          "sudo xcodes install ${version} --experimental-unxip --path /Users/${var.username}/Downloads/Xcode_${version}.xip --select --empty-trash  --no-color",
          "INSTALLED_PATH=$(xcode-select -p)",
          "CONTENTS_DIR=$(dirname $INSTALLED_PATH)",
          "APP_DIR=$(dirname $CONTENTS_DIR)",
          "sudo mv $APP_DIR /Applications/Xcode_${version}.app",
          "sudo xcode-select -s /Applications/Xcode_${version}.app",
          "xcodebuild -runFirstLaunch",
        ]
    }
  ]

  runtime_pairs = flatten([
    for platform, versions in var.xcode_runtimes : [
      for version in versions : {
        platform = platform
        version  = version
      }
    ]
  ])

  xcode_runtime_provisioners = concat(
    [
      for pair in local.runtime_pairs : {
        type = "shell"
        inline = [
          "source ~/.bash_profile",
          "export DEVELOPER_DIR=/Applications/Xcode_16.1.app",
          "xcodebuild -downloadPlatform ${pair.platform} -buildVersion ${pair.version}",
          "xcrun simctl runtime list"
          # "xcrun simctl runtime list | grep '${pair.platform} ${pair.version} ' || (echo 'Runtime ${pair.platform} ${pair.version} is missing' && exit 1)"
        ]
      }
    ],
  )
  node_install_provisioners = [
    for version in reverse(sort(var.node_versions)) : {
      type = "shell"
      inline = [
        "source ~/.bash_profile",
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
  provisioner "file" {
    source      = "data/.bash_profile"
    destination = "~/.bash_profile"
  }
  provisioner "file" {
    source      = "data/.bashrc"
    destination = "~/.bashrc"
  }
  provisioner "file" {
    source      = "data/.zshrc"
    destination = "~/.zshrc"
  }
  provisioner "shell" {
    inline = [
      "sudo chsh -s /bin/bash ${var.username}"
    ]
  }
  provisioner "shell" {
    inline = [
      "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
      "eval \"$(/opt/homebrew/bin/brew shellenv)\"",
      "brew analytics off",
      "brew install aria2 autoconf ca-certificates carthage chruby gettext git git-lfs jq libidn2 libunistring libyaml m4 nvm oniguruma openssl@3 pcre2 pyenv rbenv readline ruby-build wget xz yarn temurin xcodesorg/made/xcodes",
    ]
  }
  # Ruby
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "RUBY_CONFIGURE_OPTS=--disable-install-doc rbenv install ${var.ruby_version}",
      "rbenv rehash",
      "rbenv global ${var.ruby_version}",
      "gem install bundler",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "gem install fastlane:${var.fastlane_gem_version} cocoapods:${var.cocoapods_gem_version}",
    ]
  }
  # Node
  dynamic "provisioner" {
    for_each = local.node_install_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "nvm use '${var.node_versions[0]}'",
    ]
  }
  # Python
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "pyenv install ${var.python_version} && pyenv rehash",
      "pyenv global ${var.python_version}",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
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
      "curl -so circleci-runner.tar.gz -L https://circleci-binary-releases.s3.amazonaws.com/circleci-runner/${var.circleci_machine_runner_version}/circleci-runner_darwin_arm64.tar.gz",
      "tar -xzf circleci-runner.tar.gz --directory ~/",
      "rm -f circleci-runner.tar.gz"
    ]
  }
  provisioner "file" {
    sources     = [for version in local.xcode_versions : pathexpand("~/Xcode_${version}.xip")]
    destination = "/Users/${var.username}/Downloads/"
  }
  dynamic "provisioner" {
    for_each = local.xcode_install_commands
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }
  dynamic "provisioner" {
    for_each = local.xcode_runtime_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }
  provisioner "shell" {
    inline = var.uninstall_xcode_16_1_after_runtime_downloads ? [
      "source ~/.bash_profile",
      "sudo rm -rf /Applications/Xcode_16.1.app",
      "echo 'Xcode 16.1 uninstalled'"
    ] : [
      "echo 'Keeping Xcode 16.1'"
    ]
  }
  // check there is at least 30GB of free space and fail if not
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "df -h",
      "export FREE_MB=$(df -m | awk '{print $4}' | head -n 2 | tail -n 1)",
      "[[ $FREE_MB -gt ${var.disk_free_mb} ]] && echo OK || exit 1"
    ]
  }
}
