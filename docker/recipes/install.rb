#
# Cookbook Name:: docker
# Recipe:: install
#
# Source: AWS Application Management Blog "Running Docker on AWS OpsWorks" (http://bit.ly/1EHNqts)
#
# See source for license details.
#

case node[:platform]
when "ubuntu","debian"
  package "docker.io" do
    action :install
  end
when 'centos','redhat','fedora','amazon'
  package "docker" do
    action :install
  end
end

service "docker" do
  action :start
end
