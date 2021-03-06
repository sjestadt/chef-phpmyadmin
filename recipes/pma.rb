#
# Cookbook Name:: phpmyadmin4
# Recipe:: pma
#
# Copyright 2014 Pressable
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'digest/sha1'

include_recipe "apache2"

home = node['phpmyadmin']['home']
user = node['phpmyadmin']['user']
group = node['phpmyadmin']['group']
conf = "#{home}/config.inc.php"

group group do
	action [ :create, :manage ]
end

user user do
	action [ :create, :manage ]
	comment 'PHPMyAdmin User'
	gid group
	home home
	shell '/usr/sbin/nologin'
	supports :manage_home => true
end

directory home do
	owner user
	group group
	mode 00755
	recursive true
	action :create
end

directory node['phpmyadmin']['upload_dir'] do
	owner 'root'
	group 'root'
	mode 01777
	recursive true
	action :create
end

directory node['phpmyadmin']['save_dir'] do
	owner 'root'
	group 'root'
	mode 01777
	recursive true
	action :create
end

# Download the selected PHPMyAdmin archive
remote_file "#{Chef::Config['file_cache_path']}/phpMyAdmin-#{node['phpmyadmin']['version']}-all-languages.tar.gz" do
  owner user
  group group
  mode 00644
	retries 5
	retry_delay 2
  action :create
  source "#{node['phpmyadmin']['mirror']}/#{node['phpmyadmin']['version']}/phpMyAdmin-#{node['phpmyadmin']['version']}-all-languages.tar.gz"
  checksum node['phpmyadmin']['checksum']
end

bash 'extract-php-myadmin' do
	user user
	group group
	cwd home
	code <<-EOH
		rm -fr *
		tar xzf #{Chef::Config['file_cache_path']}/phpMyAdmin-#{node['phpmyadmin']['version']}-all-languages.tar.gz
		mv phpMyAdmin-#{node['phpmyadmin']['version']}-all-languages/* #{home}/
		rm -fr phpMyAdmin-#{node['phpmyadmin']['version']}-all-languages
	EOH
	not_if { ::File.exists?("#{home}/RELEASE-DATE-#{node['phpmyadmin']['version']}")}
end

directory "#{home}/conf.d" do
	owner user
	group group
	mode 00755
	recursive true
	action :create
end

# Blowfish Secret - set it statically when running on Chef Solo via attribute
unless Chef::Config[:solo] || node['phpmyadmin']['blowfish_secret']
  node.set['phpmyadmin']['blowfish_secret'] = Digest::SHA1.hexdigest(IO.read('/dev/urandom', 2048))
  node.save
end





template "#{home}/config.inc.php" do
	source 'config.inc.php.erb'
	owner user
	group group
	mode 00644
end

# Now build out the apache virtual host config. 
# Just a reminder to myself, the definition of 'web_app'
# https://github.com/opscode-cookbooks/apache2/blob/master/definitions/web_app.rb


web_app "phpmyadmin" do
  server_name node['fqdn']
  docroot "/opt/phpmyadmin"
end



## Setup the PMA control database and setup the user for it

phpmyadmin4_pmadb 'phpmyadmin' do
  host '127.0.0.1'
  port  3306
  root_username 'root'
  root_password  node[:percona][:server][:root_password]
  pma_database 'phpmyadmin'
  pma_username 'pma_control'
  pma_password 'controller_pass'
end


## Create the configuration file for the local DB server
## This file is going to be in pmaroot/conf.d/

phpmyadmin4_db 'test_kitchen_server' do
  name "Test Kitchen Server"
  host '127.0.0.1'
  port 3306
  username 'root'
  password  node[:percona][:server][:root_password]
  hide_dbs %w{ information_schema mysql phpmyadmin performance_schema }
  pma_username 'pma_controller'
  pma_password 'pma_controller_pass'
  pma_database 'phpmyadmin'
  auth_type 'config'
end
