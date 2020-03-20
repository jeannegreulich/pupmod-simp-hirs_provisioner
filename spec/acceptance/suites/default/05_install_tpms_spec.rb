require 'spec_helper_acceptance'

test_name 'install tpm simulators'

describe 'install tpm_simulators' do

  # Implement any workarounds that are needed to run as service
  def implement_workarounds(hirs_host)
    # workaround for dbus config file mismatch error:
    # "dbus[562]: [system] Unable to reload configuration: Configuration file
    #  needs one or more <listen> elements giving addresses"
    on hirs_host, 'systemctl restart dbus'
    # The tpm simulator does not configure the socket to work with
    # selinux
    on hirs_host, 'setenforce 0'
  end

  def config_abrmd_for_tpm2sim_on(hirs_host)
    tpm2_abrmd_version = on(hirs_host, 'tpm2-abrmd --version').stdout.split(/\s+/).last
    if tpm2_abrmd_version.split('.').first.to_i > 1
      tcti_info = '--tcti=/usr/lib64/libtss2-tcti-mssim.so.0'
    else
      tcti_info = '-t socket'
    end
    on hirs_host, 'mkdir -p /etc/systemd/system/tpm2-abrmd.service.d'
    # Configure the TAB/RM to talk to the TPM2 simulator
    extra_file=<<-SYSTEMD.gsub(/^\s*/,'')
    [Service]
    ExecStart=
    ExecStart=/sbin/tpm2-abrmd  #{tcti_info}
    SYSTEMD
    create_remote_file hirs_host, '/etc/systemd/system/tpm2-abrmd.service.d/override.conf', extra_file
    on hirs_host, 'systemctl daemon-reload'
    on hirs_host, 'systemctl list-unit-files | grep tpm2-abrmd ' \
      + '&& systemctl restart tpm2-abrmd ' \
      + %q[|| echo "tpm2-abrmd.service not restarted because it doesn't exist"]
  end

  # start the tpm2sim and override tpm2-abrmd's systemd config use it
  # assumes the tpm2sim has been installed on the hosts
  def configure_tpm2_0_tools(hirs_host)
    install_package(hirs_host,'tpm2-abrmd')
    install_package(hirs_host,'tpm2-tools')
    config_abrmd_for_tpm2sim_on(hirs_host)
    on hirs_host, 'systemctl start tpm2-abrmd.service'
  end

  # This is a helper to get the status of the TPM so it can be compared against the
  # the expected results.
  def get_tpm2_status(hirs_host)
      stdout = on(hirs_host, 'facter -p -y tpm2 --strict').stdout
      fact = YAML.safe_load(stdout)['tpm2']
      tpm2_status = fact['tpm2_getcap']['properties-variable']['TPM_PT_PERSISTENT']
      [tpm2_status['ownerAuthSet'],tpm2_status['endorsementAuthSet'],tpm2_status['lockoutAuthSet']]
  end

  # starts tpm 1.2 simulator services
  # Per the README file included with the source code, procedures for starting the tpm are:
  #   Start the TPM in another shell after setting its environment variables
  #     (TPM_PATH,TPM_PORT)
  #     > cd utils
  #     > ./tpmbios
  #   Kill the TPM in the other shell and restart it
  def start_tpm_1_2_sim(hirs_host)
    os = fact_on(hirs_host,'operatingsystemmajrelease')
    on hirs_host, 'yum install -y trousers gcc tpm-tools'
    if os.eql?('7')
      on hirs_host, 'systemctl start tpm12-simulator'
      on hirs_host, 'systemctl start tpm12-tpmbios'
      on hirs_host, 'systemctl restart tpm12-simulator'
      on hirs_host, 'systemctl restart tpm12-tpmbios'
      on hirs_host, 'systemctl start tpm12-tpminit'
      on hirs_host, 'systemctl start tpm12-tcsd'
    else os.eql?('6')
      on hirs_host, 'service tpm12-simulator start '
      on hirs_host, 'service tpm12-tpmbios start '
      on hirs_host, 'service tpm12-simulator restart '
      on hirs_host, 'service tpm12-tpmbios start '
      on hirs_host, 'service tpm12-tpminit start '
      on hirs_host, 'service tpm12-tcsd start '
    end
  end

  let(:manifest) {
    <<-EOS
      include 'hirs_provisioner'
    EOS
  }


  let(:hieradata) {
    <<-EOS
---
hirs_provisioner::config::aca_fqdn: aca
    EOS
  }

  context 'on a hirs host' do
    hosts_with_role(hosts, 'hirs').each do |hirs_host|
    # Using puppet_apply as a helper
      it 'should work with no errors' do
        if hirs_host.host_hash[:roles].include?('tpm_2_0')
          install_package(hirs_host,'simp-tpm2-simulator')
          implement_workarounds(hirs_host)
          on hirs_host, 'systemctl start simp-tpm2-simulator.service'
          configure_tpm2_0_tools(hirs_host)
        else
          install_package(hirs_host,'simp-tpm12-simulator')
          start_tpm_1_2_sim(hirs_host)
        end
      end
    end
  end
end
