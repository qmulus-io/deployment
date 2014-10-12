#
# Cookbook Name:: docker
# Recipe:: start
#
# (c) 2014 Qmulus Inc.
# Author: Jeffrey Bagdis (jeff@qmulus.io)
#

node[:deploy].each do |application, deploy|
  if deploy[:application_type] != 'other'
    Chef::Log.debug("Skipping docker::docker-start for application #{application} as it is not a docker app")
    next
  end

  ruby_block "start docker application #{application}" do
    block do
      Chef::Log.info("start docker via: docker start #{application}")
      Chef::Log.info(`docker start #{application}`)
      $? == 0
    end
    not_if { node.has_key?("app".to_sym) && application != node[:app] }
  end

end
