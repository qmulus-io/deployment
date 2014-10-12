#
# Cookbook Name:: docker
# Recipe:: stop
#
# (c) 2014 Qmulus Inc.
# Author: Jeffrey Bagdis (jeff@qmulus.io)
#

node[:deploy].each do |application, deploy|
  if deploy[:application_type] != 'other'
    Chef::Log.debug("Skipping docker::docker-stop for application #{application} as it is not a docker app")
    next
  end

  ruby_block "stop docker application #{application}" do
    block do
      Chef::Log.info("stop docker via: docker stop --time=45 #{application}")
      Chef::Log.info(`docker stop --time 45 #{application}`)
      $? == 0
    end
    not_if { node.has_key?("app".to_sym) && application != node[:app] }
  end

end
