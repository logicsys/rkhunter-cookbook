#
# Cookbook:: rkhunter
# Recipe:: default
#
# Copyright:: (C) 2014 Greg Palmier

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#   http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe 'yum-epel' if platform_family?('rhel')

if platform_family?('rhel') && node['platform_version'].to_f >= 8
  # use bundled unhide bins

  cookbook_file '/usr/sbin/unhide' do
    mode '755'
  end
  cookbook_file '/usr/sbin/unhide-posix' do
    mode '755'
  end
  cookbook_file '/usr/sbin/unhide-tcp' do
    mode '755'
  end
  cookbook_file '/usr/sbin/unhide_rb' do
    mode '755'
  end

else
  package 'unhide or unhide.rb' do
    # The Ruby version of unhide is reportedly much better in all
    # respects, including performance. Sometimes it is packaged
    # separately, sometimes not. DISABLE_UNHIDE=2 disables Ruby.
    if node['rkhunter']['config']['disable_unhide'] != 2
      package_name value_for_platform(
        'debian' => {
          '~> 8.0' => 'unhide',
          'default' => 'unhide.rb',
        },
        %w(opensuse opensuseleap suse) => {
          'default' => 'unhide_rb',
        },
        'ubuntu' => {
          'default' => 'unhide.rb',
        },
        'default' => 'unhide'
      )
    else
      package_name 'unhide'
    end

    not_if do
      node['rkhunter']['config']['disable_tests']
        .include?('hidden_procs')
    end
  end
end

package 'rkhunter' do
  action :upgrade
end

template '/etc/default/rkhunter' do
  source 'rkhunter.erb'
  owner 'root'
  group node['root_group']
  mode '0644'
  variables :config => node['rkhunter']['debian']
  only_if { platform_family?('debian') }
end

template '/etc/sysconfig/rkhunter' do
  source 'rkhunter.erb'
  owner 'root'
  group node['root_group']
  mode '0644'
  variables :config => node['rkhunter']['rhel']
  only_if { platform_family?('fedora', 'rhel') }
end

template '/etc/rkhunter.conf' do
  source 'rkhunter.conf.erb'
  owner 'root'
  group node['root_group']
  mode '0640'
  variables :config => node['rkhunter']['config']
end

# Note - this is quite brittle, and subject to breakage by up-stream changes
# However, it's quite visible when it *does* break, and it's reasonably
# unlikely the cron scripts are going to change much

if node['rkhunter']['email_on_success']
  if platform_family?('rhel', 'fedora')
    ruby_block 'Add success email' do
      block do
        file = Chef::Util::FileEdit.new('/etc/cron.daily/rkhunter')
        file.search_file_replace_line(/XITVAL != 0/, %{
    if [ $XITVAL == 0 ]; then
      /bin/cat $TMPFILE1 | /bin/mail -s "[OK] rkhunter Daily Run on $(hostname)" $MAILTO
    else
})
        file.write_file
      end
    end
  elsif platform_family?('debian')
    ruby_block 'Add success email' do
      block do
        file = Chef::Util::FileEdit.new('/etc/cron.daily/rkhunter')
        # NH - a bit awkward, as we're only searching and replacing on one line,
        # so the 'else' has to make sense
        file.search_file_replace_line(/if \[ -s "\$OUTFILE"/, %{
        if [ ! -n "$REPORT_EMAIL" ] || [ ! -s "$OUTFILE" ]; then
          if [ -n "$REPORT_EMAIL" ]; then
            (
              echo "Subject: [OK] [rkhunter] $(hostname -f) - Daily report"
              echo "To: $REPORT_EMAIL"
              echo ""
              echo "No output (success)"
            ) | /usr/sbin/sendmail $REPORT_EMAIL
          fi
        else
})
        file.write_file
      end
    end
  end
end

# don't want extra files cluttering up cron.daily!
file '/etc/cron.daily/rkhunter.old' do
  action :delete
end
