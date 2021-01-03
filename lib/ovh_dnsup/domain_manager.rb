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

require_relative 'ovh_api'

module OvhDnsup

  # Allows managing a DNS zone.
  class DomainManager
    def initialize(args)
      @api = OvhApi.new(args)
    end

    def endpoint; @api.endpoint; end
    def application_key; @api.application_key; end
    def application_secret; @api.application_secret; end

    def state
      @api.state
    end

    def state= h
      @api.state = h
    end

    def register
      @api.register
    end

    def unregister(all: false)
      response = @api.get('auth/currentCredential')
      app_id = response['applicationId']

      # unregister all applications other
      if all
        other_apps = @api.get('me/api/application').select {|id| id != app_id }
        other_apps.each do |id|
          @api.delete("me/api/application/#{id}")
        end
      end

      @api.delete("me/api/application/#{app_id}")
    end

    def login
      @api.login [{:method => 'GET', :path => '/domain/zone/*'},
                  {:method => 'GET', :path => '/me/api/application'},
                  {:method => 'DELETE', :path => '/me/api/application/*'},
                  {:method => 'GET', :path => '/me/api/credential'},
                  {:method => 'GET', :path => '/me/api/credential/*'},
                  {:method => 'DELETE', :path => '/me/api/credential/*'}]
    end

    def logout
      @api.post('auth/logout')
    end

    def list_zone(domain)
      ids = @api.get("domain/zone/#{domain}/record")
      ids.each do |id|
        record = @api.get("domain/zone/#{domain}/record/#{id}")
        if !record['subDomain'].empty?
          full_domain = "#{record['subDomain']}.#{domain}"
        else
          full_domain = domain
        end
        puts "#{record['fieldType']} #{full_domain} => #{record['target']}"
      end
    end

    def subdomain_type_map(domain, sub)
      # get IDs of all entries of this subdomain
      ids = @api.get("domain/zone/#{domain}/record", subDomain: sub)

      type_map = {}

      ids.each do |id|
        record = @api.get("domain/zone/#{domain}/record/#{id}")
        field_type = record['fieldType']
        if ['A', 'AAAA'].include? field_type
          type_map[field_type] = id
        end
      end

      type_map
    end

    def list_sessions(all: false)
      params = nil
      if !all
        app_id = @api.get('auth/currentCredential')['applicationId']
        params = {'applicationId' => app_id}
      end

      cred_ids = @api.get('me/api/credential', params)
      cred_ids.each do |id|
        info = @api.get("me/api/credential/#{id}")

        next if info['status'] == 'expired' && !all

        app_info = @api.get("me/api/credential/#{id}/application") if all

        puts "id: #{id}"
        puts "  app: #{app_info['name']} (#{app_info['description']})" if all
        puts "  status: #{info['status']}" if all
        puts "  creation: #{info['creation']}  expiration: #{info['expiration']}"

        info['rules'].each do |rule|
          if /^\/domain\/zone\/(?<zone>[^\/]+)\/record\/(?<eid>[^\/]+)$/ =~ rule['path'] then

            begin
              entry = @api.get("domain/zone/#{zone}/record/#{eid}")
              puts "  zone: #{zone}  subdomain: #{entry['subDomain']}"
            rescue OvhException
            end
          end

          if rule['path'] == '/domain/zone/*'
            puts "  domain management"
          end
        end # info['rules'].each
      end # cred_ids.each
    end

    def delete_session(id)
      @api.delete("me/api/credential/#{id}")
    end

    def delete_all_sessions()
      cred_id = @api.get('auth/currentCredential')['credentialId']

      other_ids = @api.get('me/api/credential').select {|id| id != cred_id}
      other_ids.each &method(:delete_session)
      delete_session(cred_id)
    end
  end

  # Once authorized, can be used to change a DNS zone entry.
  class DomainUpdater
    def initialize(endpoint: nil, application_key: nil, application_secret: nil, state: nil)
      if state
        self.state = state
      else
        @api = OvhApi.new(endpoint: endpoint,
                          application_key: application_key,
                          application_secret: application_secret)
      end
    end

    def state
      { 'api_state' => @api.state,
        'domain' => @domain,
        'subdomain' => @subdomain,
        'type_map' => @type_map }
    end

    def state= h
      @api = OvhApi.new(state: h['api_state'])
      @domain = h['domain']
      @subdomain = h['subdomain']
      @type_map = h['type_map']
    end

    def login(domain:, subdomain:, type_map:)
      @domain = domain
      @subdomain = subdomain
      @type_map = type_map

      access_rules = type_map.map() {
        |type, id| { method: 'PUT', path: "/domain/zone/#{domain}/record/#{id}" }
      }
      access_rules.push({method: 'POST', path: "/domain/zone/#{@domain}/refresh"})

      @api.login(access_rules)
    end

    def update(new_ip)
      type = (/:/ =~ new_ip) ? 'AAAA' : 'A'
      id = @type_map[type]
      if !id then raise "Subdomain has no #{type} record" end

      obj = {'ttl' => 300,
             'target' => new_ip }

      @api.put("domain/zone/#{@domain}/record/#{id}", obj)
      @api.post("domain/zone/#{@domain}/refresh")
    end
  end

end
