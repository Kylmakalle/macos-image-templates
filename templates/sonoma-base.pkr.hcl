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

source "tart-cli" "tart" {
  from_ipsw    = "https://updates.cdn-apple.com/2024SummerFCS/fullrestores/062-52859/932E0A8F-6644-4759-82DA-F8FA8DEA806A/UniversalMac_14.6.1_23G93_Restore.ipsw"
  vm_name      = "sonoma-base"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 40
  ssh_password = var.password
  ssh_username = var.username
  ssh_timeout  = "120s"
  boot_command = [
    # hello, hola, bonjour, etc.
    "<wait30s><spacebar>",
    # Language: most of the times we have a list of "English"[1], "English (UK)", etc. with
    # "English" language already selected. If we type "english", it'll cause us to switch
    # to the "English (UK)", which is not what we want. To solve this, we switch to some other
    # language first, e.g. "Italiano" and then switch back to "English". We'll then jump to the
    # first entry in a list of "english"-prefixed items, which will be "English".
    #
    # [1]: should be named "English (US)", but oh well 🤷
    "<wait15s>italiano<esc>english<enter>",
    # Select Your Country and Region
    "<wait15s>united states<leftShiftOn><tab><leftShiftOff><spacebar>",
    # Written and Spoken Languages
    "<wait5s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Accessibility
    "<wait5s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Data & Privacy
    "<wait5s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Migration Assistant
    "<wait5s><tab><tab><tab><spacebar>",
    # Sign In with Your Apple ID
    "<wait5s><leftShiftOn><tab><leftShiftOff><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Are you sure you want to skip signing in with an Apple ID?
    "<wait5s><tab><spacebar>",
    # Terms and Conditions
    "<wait5s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # I have read and agree to the macOS Software License Agreement
    "<wait5s><tab><spacebar>",
    # Create a Computer Account
    "<wait5s>${var.username}<tab><tab>${var.password}<tab>${var.password}<tab><tab><tab><spacebar>",
    # Enable Location Services
    "<wait20s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Are you sure you don't want to use Location Services?
    "<wait5s><tab><spacebar>",
    # Select Your Time Zone
    "<wait5s><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Analytics
    "<wait5s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Screen Time
    "<wait5s><tab><spacebar>",
    # Siri
    "<wait5s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Choose Your Look
    "<wait5s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Enable Voice Over
    "<wait5s><leftAltOn><f5><leftAltOff><wait5s>v",
    # Now that the installation is done, open "System Settings"
    "<wait5s><leftAltOn><spacebar><leftAltOff>System Settings<enter>",
    # Navigate to "Sharing"
    "<wait5s><leftAltOn>f<leftAltOff>sharing<enter>",
    # Navigate to "Remote Login" and enable it
    "<wait5s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>",
    # Disable Voice Over
    "<leftAltOn><f5><leftAltOff>",
  ]

  // A (hopefully) temporary workaround for Virtualization.Framework's
  // installation process not fully finishing in a timely manner
  create_grace_time = "60s"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    inline = [
      // Enable passwordless sudo
      "echo ${var.username} | sudo -S sh -c \"mkdir -p /etc/sudoers.d/; echo '${var.username} ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/admin-nopasswd\"",
      // Enable auto-login
      //
      // See https://github.com/xfreebird/kcpassword for details.
      "echo '00000000: 19e0 2157 bbd0 b18f d1b9 1f' | sudo xxd -r - /etc/kcpassword",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser ${var.username}",
      // Disable screensaver at login screen
      "sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0",
      // Disable screensaver for user
      "defaults -currentHost write com.apple.screensaver idleTime 0",
      // Prevent the VM from sleeping
      "sudo systemsetup -setdisplaysleep Off 2>/dev/null",
      "sudo systemsetup -setsleep Off 2>/dev/null",
      "sudo systemsetup -setcomputersleep Off 2>/dev/null",
      // Launch Safari to populate the defaults
      "/Applications/Safari.app/Contents/MacOS/Safari &",
      "SAFARI_PID=$!",
      "disown",
      "sleep 30",
      "kill -9 $SAFARI_PID",
      // Enable Safari's remote automation
      "sudo safaridriver --enable",
      // Disable screen lock
      //
      // Note that this only works if the user is logged-in,
      // i.e. not on login screen.
      "sysadminctl -screenLock off -password ${var.username}",
    ]
  }

  provisioner "file" {
    source      = "data/disable-tso.plist"
    destination = "~/disable-tso.plist"
  }
  provisioner "file" {
    source      = "data/limit.maxfiles.plist"
    destination = "~/limit.maxfiles.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'Configuring maxfiles...'",
      "sudo mv ~/limit.maxfiles.plist ~/disable-tso.plist /Library/LaunchDaemons/",
      "sudo chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist /Library/LaunchDaemons/disable-tso.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/limit.maxfiles.plist /Library/LaunchDaemons/disable-tso.plist",
      "echo 'Disabling spotlight...'",
      "sudo mdutil -a -i off",
    ]
  }
}
