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

require 'json'
require 'digest'
require 'faraday'

module OvhDnsup
  class OvhException < Exception; end

  ENDPOINTS = {
    'ovh-eu' => 'https://eu.api.ovh.com/',
    'ovh-us' => 'https://api.us.ovhcloud.com/',
    'ovh-ca' => 'https://ca.api.ovh.com/',
    'kimsufi-eu' => 'https://eu.api.kimsufi.com/',
    'kimsufi-ca' => 'https://ca.api.kimsufi.com/',
    'soyoustart-eu' => 'https://eu.api.soyoustart.com/',
    'soyoustart-ca' => 'https://ca.api.soyoustart.com/',
  }

  class OvhApi
    attr_reader :endpoint, :application_key, :application_secret, :consumer_key

    def self.endpoints
      ENDPOINTS.map { |k,v| k }
    end

    def self.endpoint_url(endpoint)
      ENDPOINTS[endpoint]
    end

    def initialize(endpoint: nil, application_key: nil, application_secret: nil, state: nil)
      if state
        self.state = state
        raise 'Invalid arguments' if application_key || application_secret || endpoint
      else
        @endpoint = endpoint
        @application_key = application_key
        @application_secret = application_secret
        @consumer_key = nil

        @base_url = ENDPOINTS[@endpoint] + '1.0/'
        @conn = Faraday.new @base_url
      end
    end

    def state
      { 'endpoint' => @endpoint,
        'application_key' => @application_key,
        'application_secret' => @application_secret,
        'consumer_key' => @consumer_key }
    end

    def state= h
      @endpoint = h['endpoint']
      @application_key = h['application_key']
      @application_secret = h['application_secret']
      @consumer_key = h['consumer_key']

      @base_url = ENDPOINTS[@endpoint] + '1.0/'
      @conn = Faraday.new @base_url
    end

    def login(access_rules, verbose=true)
      register unless @application_key && @application_secret

      body = { :accessRules => access_rules }.to_json
      headers = { 'Content-type' => 'application/json',
                  'X-Ovh-Application' => @application_key }
      response = @conn.post('auth/credential', body, headers)
      response = process(response)

      validation_url = response['validationUrl']
      @consumer_key = response['consumerKey']

      if verbose
        puts <<~EOS
        To complete the authentication process please open

          #{validation_url}

        and login with your credentials.
        EOS
      end
      return validation_url
    end

    def sign(method, url, body, tstamp)
      if !@application_key || !@application_secret
        raise OvhException.new('Application key and/or secret missing.')
      end
      if !@consumer_key
        raise OvhException.new('Not logged in')
      end

      "$1$" + Digest::SHA1.hexdigest(
                  @application_secret + "+" +
                  @consumer_key + "+" +
                  method + "+" +
                  url + "+" +
                  body + "+" +
                  tstamp.to_s)
    end

    def auth_header(method, path, params = nil, body = '')
      raise 'Only relative paths are allowed' if path.start_with?('/')
      url = @base_url + path
      if params
        url += '?' + Faraday::FlatParamsEncoder.encode(params)
      end
      tstamp = Time.now.to_i
      {
        'Content-type' => 'application/json',
        'X-Ovh-Application' => @application_key,
        'X-Ovh-Timestamp' => tstamp.to_s,
        'X-Ovh-Signature' => sign(method, url, body, tstamp),
        'X-Ovh-Consumer' => @consumer_key
      }
    end

    def get(path, params = nil)
      response = @conn.get(path, params, auth_header('GET', path, params))
      return process(response)
    end

    def post(path, body='')
      response = @conn.post(path, body, auth_header('POST', path, nil, body))
      return process(response)
    end

    def put(path, obj)
      body = obj.to_json
      response = @conn.put(path, body, auth_header('PUT', path, nil, body))
      return process(response)
    end

    def delete(path, params=nil)
      response = @conn.delete(path, params, auth_header('DELETE', path))
      return process(response)
    end

    private
    def process(response)
      if !response.success?
        begin
          msg = JSON.parse(response.body)['message']
        rescue
          msg = "#{response.status}: #{response.body}"
        end
        raise OvhException.new(msg)
      else
        return JSON.parse(response.body)
      end
    end
  end



end
