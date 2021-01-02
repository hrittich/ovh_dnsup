# OvhDnsup - Dynamic DNS for IPv6

This software enables you to safely update DNS zone entries hosted by OVH. As of January 2021, OVH does not allow dynamic DNS (DynDNS) updates for IPv6 addresses when using their DynHost protocol. This software provides a work-around for this limitation by using the OVH API to perform this task. Security is ensured by generating a DNS-entry-specific access token, which can only be used to update the corresponding entry. Hence, if this token is stolen the possible damage is limited.

This client also supports IPv4, however, in this case you probably want to use OVH's DynHost feature.

## Installation

Either clone or download this repository and execute (after installing [Bundler](https://bundler.io/)):

    $ bundle install

Or install it yourself by running:

    $ gem install ovh_dnsup

You might want to add the `--user-install` flag to install into your home directory.

## Quick Start

This section describes how to setup OvhDnsup to dynamically update a domain. We shall use `dynamic.example.com` as an example. You have to replace the domain `example.com` and the hostname `dynamic` according to your needs.

First, you need to register the application with the OVH API. Enter

    $ ovh_dnsup register

(without the dollar sign) into a console, which will start the registration process. Follow the instructions on the screen.

Next, you need to login:

    $ ovh_dnsup login

Again, follow the instructions. This login will request access to a few API functions, which are needed for the management of the dynamic hosts. We can, however, later drop these privileges to ensure security.

Now, you have to request the an authorization token for the domain update. Note, *the A and/or AAAA record need to be created first in the OVH customer center!*  When the subdomain is created, execute:

    $ ovh_dnsup authorize example.com dynamic dynamic_example_com.token

After following the instructions on the screen, you have created a file `dynamic_example_com.token` which contains the authorization information to update the hostname. The file is restricted to updating only the hostname you have authorized. Note, you can inspect and manage all authorizations using the `ovh_dnsup sessions` command. Furthermore, make sure to grant access for the time period that you want to perform updates in.

Updating the IP address can be done essentially in two ways. You can set the IP address manually by executing:

    $ ovh_dnsup update --ip 2001:db8::abcd dynamic_example_com.token

You can also use an interface name to update the IP address:

    $ ovh_dnsup update --if eth0 --daemon dynamic_example_com.token

The `--daemon` option instructs OvhDnsup to periodically check if the IP of the interface has changed and in this case to update the hostname.

When you have convinced yourself that your setup is working, you can run the command

    $ ovh_dnsup logout

to log out from the management interface. From now on, only DNS updates are possible using the corresponding token files. (You can, of course, re-login at any time.)

## Usage

In general, you use OvhDnsup by executing:

    $ ovh_dnsup command [arguments...]

The following commands are possible

| Command    | Description |
| :---       | :--- |
| register   | Register application with the API. |
| unregister | Unregister (the) application(s). |
| login      | Login to manage the DNS updaters. |
| logout     | Logout. |
| list       | List a DNS zone. |
| authorize  | Authorize a DNS updater. |
| update     | Perform DNS updates. |
| sessions   | List all authorized updaters. |
| interfaces | List the local network interfaces. |

For more information on the individual commands run:

    $ ovh_dnsup command --help

## Running as a Service

### Linux with Systemd

The following commands need to be executed as root. First, create a service user.

    useradd --system ovh_dnsup
    
Then, save the token file as `/etc/ovh_dnsup.token` and execute

    $ chown ovh_dnsup /etc/ovh_dnsup.token
    $ chmod 700 /etc/ovh_dnsup.token
    
to set the right permissions. Afterwards, create a service file:

	$ cat > /etc/systemd/system/ovh_dnsup.service << EOF
    [Unit]
    Description=Update OVH DNS

    [Service]
    User=ovh_dnsup
    Group=nogroup
    ExecStart=sh -c '/usr/local/bin/ovh_dnsup update \$(cat /etc/ovh_dnsup.conf) --daemon /etc/ovh_dnsup.token'

    [Install]
    WantedBy=multi-user.target
    EOF

Set you configuration by executing

    $ echo "--if=eth0" > /etc/ovh_dnsup.conf

where you replace the `eth0` by the interface of your choice.

You can now start and enable the service by

    systemctl start ovh_dnsup.service
    systemctl enable ovh_dnsup.service

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hrittich/ovh_dnsup.

