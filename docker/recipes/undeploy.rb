#
# Cookbook Name:: docker
# Recipe:: undeploy
#
# (c) 2014 Qmulus Inc.
# Author: Jeffrey Bagdis (jeff@qmulus.io)
#

include_recipe 'deploy'

node[:deploy].each do |application, deploy|
  if deploy[:application_type] != 'other'
    Chef::Log.debug("Skipping docker::docker-undeploy for application #{application} as it is not a docker app")
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
  
  ruby_block "remove docker container #{application}" do
    block do
      Chef::Log.info("remove docker container via: docker rm #{application}")
      Chef::Log.info(`docker rm #{application}`)
      $? == 0
    end
    not_if { node.has_key?("app".to_sym) && application != node[:app] }
  end
  
  ruby_block "remove docker image #{application}" do
    block do
      Chef::Log.info("remove docker container via: docker rmi #{application}")
      Chef::Log.info(`docker rmi #{application}`)
      $? == 0
    end
    not_if { node.has_key?("app".to_sym) && application != node[:app] }
  end

  directory "#{deploy[:deploy_to]}" do
    recursive true
    action :delete
    
    only_if do
      ::File.exists?("#{deploy[:deploy_to]}")
    end
    not_if { node.has_key?("app".to_sym) && application != node[:app] }
  end
end
