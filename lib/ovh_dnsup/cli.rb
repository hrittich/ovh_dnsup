# Copyright 2021 Hannah Rittich
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'optparse'
require 'socket'
require_relative 'domain_manager'

module OvhDnsup
  module Cli
    def self.run

      @conf_fn = File.join(Dir.home, '.ovh_dnsup.conf')

      command = ARGV.shift

      if %w{register unregister login logout list authorize update interfaces sessions}.include? command
        self.send command.to_sym()
      else
        usage
        puts "Invalid command #{command}"
      end
    end

    def self.usage
      puts <<~EOS
      Usage: ovh_dnsup command [arguments...]

      OVH DNS updater

      Commands:

        register      Register application with the API.
        unregister    Unregister (the) application(s).
        login         Login to manage the DNS updaters.
        logout        Logout.
        list          List a DNS zone.
        authorize     Authorize a DNS updater.
        update        Perform DNS updates.
        sessions      List all authorized updaters.
        interfaces    List the local network interfaces.

      EOS
    end

    def self.load_config
      begin
        conf = File.open(@conf_fn, 'r') { |fp| JSON.parse(fp.read) }
      rescue
        puts "Could not load configuration"
        conf = {}
      end
      @api = DomainManager.new(state: conf)
    end

    def self.save_config
      File.open(@conf_fn, 'w') { |fp| fp.write(@api.state.to_json) }
    end

    def self.register
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ovh_dnsup register [options]'
      end
      parser.parse!
      if ARGV.length != 0
        puts 'Invalid number of arguments'
        puts parser
        return
      end


      print "Endpoint (#{OvhApi.endpoints.join(', ')}): "
      endpoint = gets.strip

      if !OvhApi.endpoint_url(endpoint)
        puts 'Invalid endpoint'
        return
      end

      puts <<~EOS
      Please visit

         #{OvhApi.endpoint_url(endpoint)}createApp/

      and create an application. Afterwards, come back and answer the
      questions below.
      EOS

      print 'Application key: '
      application_key = gets().strip
      print 'Application secret: '
      application_secret = gets().strip

      @api = DomainManager.new(endpoint: endpoint,
                               application_key: application_key,
                               application_secret: application_secret)
      save_config
    end

    def self.unregister
      load_config

      params = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ovh_dnsup unregister [-a|--all]"
        opts.on('-a', '--all', 'Unregister all applications.')
      end
      parser.parse!(into: params)
      if ARGV.length != 0
        puts 'Invalid number of arguments'
        puts parser
        return
      end

      puts 'All sessions of unregistered applications become invalid. To continue, please type "YES"'
      if gets.strip != 'YES'
        puts 'Abort'
        return
      end

      @api.unregister(all: params[:all])
      if params[:all]
        puts "All applications have been unregistered"
      else
        puts "This application has been unregistered"
      end
    end

    def self.login
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ovh_dnsup login'
      end
      parser.parse!
      if ARGV.length != 0
        puts 'Invalid number of arguments'
        puts parser
        return
      end

      load_config
      @api.login
      save_config
    end

    def self.logout
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ovh_dnsup logout'
      end
      parser.parse!
      if ARGV.length != 0
        puts 'Invalid number of arguments'
        puts parser
        return
      end

      load_config
      @api.logout
    end

    def self.list
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ovh_dnsup list domain'
      end
      parser.parse!
      if ARGV.length != 1
        puts 'Invalid number of arguments'
        puts parser
        return
      end

      load_config
      @api.list_zone ARGV[0]
    end

    def self.authorize
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ovh_dnsup authorize domain subdomain token_file'
      end
      parser.parse!
      if ARGV.length != 3
        puts 'Invalid number of arguments'
        puts parser
        return
      end
      domain, subdomain, token_file = ARGV

      load_config
      map = @api.subdomain_type_map(domain, subdomain)

      if map.empty?
        puts "Subdomain has no A or AAAA record."
        return
      end

      up = DomainUpdater.new(endpoint: @api.endpoint,
                             application_key: @api.application_key,
                             application_secret: @api.application_secret)
      up.login(domain: domain, subdomain: subdomain, type_map: map)

      File.open(token_file, 'w') do |of|
        of.write(up.state.to_json)
      end
    end

    def self.update
      banner = "Usage: ovh_dnsup update [options] token_file"
      params = {}
      parser = OptionParser.new do |opts|
        opts.banner = banner

        opts.on("--ipv6", "Force IPv6")
        opts.on("--ipv4", "Force IPv4")
        opts.on("--ip IP", "The IP address to set")
        opts.on("--if INTERFACE", "The interface")
        opts.on("-d", "--daemon", "Run continuously")
        opts.on("-v", "--verbose", "Run verbosely")
        opts.on("--delay SECONDS", "Time in seconds between checks")
      end
      parser.parse!(into: params)

      if ARGV.length != 1
        puts "Invalid number of arguments"
        puts parser
        return
      end
      token_file, = ARGV

      delay = params[:delay] ? params[:delay] : 60

      if params[:ipv6]
        version = 6
      elsif params[:ipv4]
        version = 4
      end

      if !params[:ip] && !params[:if]
        puts "Either provide IP address of interface name"
        return
      end
      if params[:ip] && params[:if]
        puts "You cannot provide IP and interface!"
        return
      end

      if params[:daemon] && !params[:if]
        puts "Daemon mode requires an interface to be given"
        return
      end

      state = File.open(token_file, 'r') { |fp| JSON.parse(fp.read) }
      @up = DomainUpdater.new(state: state)

      ip = nil
      running = true
      while running
        begin
          if params[:ip]
            new_ip = params[:ip]
          else
            new_ip = get_interface_address(interface: params[:if], version: version)
          end

          if new_ip != ip
            puts "Setting new IP #{new_ip}" if params[:verbose]
            @up.update new_ip
            ip = new_ip

            if !params[:daemon]
              running = false
            end
          else
            puts "IP not changed" if params[:verbose]
          end

        rescue Interrupt
          puts "Interrupted" if params[:verbose]
          running = false
        rescue Exception => e
          puts "WARNING: #{e.to_s}"
        end

        begin
          sleep delay if running
        rescue Interrupt
          running = false
        end
      end
    end

    def self.sessions
      load_config

      params = {}
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ovh_dnsup sessions'
        opts.on('-a', '--all', 'List all sessions')
        opts.on('-d', '--delete ID', 'Delete session')
        opts.on('--delete-all', 'Delte all sessions')
      end
      parser.parse!(into: params)
      if ARGV.length != 0
        puts 'Invalid number of arguments'
        puts parser
        return
      end

      if params[:delete]
        @api.delete_session(params[:delete].to_i)
      elsif params["delete-all".to_sym]
        @api.delete_all_sessions()
      else
        @api.list_sessions(all: params[:all])
      end
    end

    # version: the IP version
    def self.get_interface_address(interface:, version: nil)
      ipv4 = []
      ipv6 = []
      Socket.getifaddrs.each do |ifaddr|
        if ifaddr.name == interface
          if ifaddr.addr.ipv4?
            ipv4.push(ifaddr.addr.ip_address)
          end
          if ifaddr.addr.ipv6?
            ipv6.push(ifaddr.addr.ip_address)
          end
        end
      end

      # filter local addresses
      ipv6.select { |addr| !/^fe80/ =~ addr }

      if !ipv6.empty? && (version == nil || version == 6)
        return ipv6[0]
      elsif !ipv4.empty? && (version == nil || version == 4)
        return ipv4[0]
      else
        raise 'No suitable address found.'
      end
    end

    def self.interfaces
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ovh_dnsup interfaces'
      end
      parser.parse!
      if ARGV.length != 0
        puts 'Invalid number of arguments'
        puts parser
        return
      end

      interfaces = Hash.new { |h, k| h[k] = [] }
      Socket.getifaddrs.each do |a|
        if a.addr.ip?
          interfaces[a.name].push(a.addr)
        end
      end

      interfaces.each do |k,v|
        puts k
        v.each { |i| puts "  #{i.ip_address}" }
      end

    end
  end
end
