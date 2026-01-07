# -*- mode: ruby -*-
# vi: set ft=ruby :

# ==============================================================================
#  AD-DEPLOYER - VAGRANTFILE
#  Provisions a Windows Server 2022 environment for Active Directory Deployment.
# ==============================================================================

Vagrant.configure("2") do |config|
  # ----------------------------------------------------------------------------
  # VM Configuration
  # ----------------------------------------------------------------------------
  config.vm.box = "jborean93/WindowsServer2022"
  config.vm.box_check_update = false
  
  # Forward WinRM port for Ansible connectivity
  config.vm.network "forwarded_port", guest: 5985, host: 5985, id: "winrm", auto_correct: true
  
  # Resource Allocation
  config.vm.provider "virtualbox" do |vb|
    vb.name = "AD-LAB-DC01"
    vb.gui = false
    vb.memory = 4096
    vb.cpus = 2
    vb.customize ["modifyvm", :id, "--clipboard", "bidirectional"]
  end

  config.vm.provider "vmware_desktop" do |vmware|
    vmware.vmx["displayname"] = "AD-LAB-DC01"
    vmware.gui = false
    vmware.memsize = "4096"
    vmware.numvcpus = "2"
    vmware.allowlist_verified = true
  end

  # ----------------------------------------------------------------------------
  # Provisioning - Prepare for Ansible
  # ----------------------------------------------------------------------------
  # Ensure WinRM is configured for Ansible (Basic Auth, Unencrypted for Lab)
  config.vm.provision "shell", shell: "powershell", inline: <<-SHELL
    $ErrorActionPreference = "Stop"
    
    Write-Output "[*] Configuring WinRM for Ansible..."
    
    # Configure WinRM Service
    winrm quickconfig -q
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/service/auth '@{Basic="true"}'
    
    # Allow WinRM through Firewall
    New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" -Protocol TCP -LocalPort 5985 -Action Allow -Enabled True -Profile Any || Write-Output "Rule exists"
    
    Write-Output "[+] WinRM Ready."
  SHELL

  config.vm.post_up_message = <<-MESSAGE
  
  ✅  Windows Server Deployed Successfully!
  
  Connexion Info:
  - IP: 127.0.0.1 (Port 5985 forwarded)
  - User: vagrant
  - Pass: vagrant
  
  🚀  To deploy AD, run:
      cd ad-deployer
      ./deploy-ad.sh -t 127.0.0.1 -p 'vagrant' -s 'S@feMode123!'
      
  MESSAGE

end
