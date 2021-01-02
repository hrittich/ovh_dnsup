require_relative 'lib/ovh_dnsup/version'

Gem::Specification.new do |spec|
  spec.name          = "ovh_dnsup"
  spec.version       = OvhDnsup::VERSION
  spec.authors       = ["Hannah Rittich"]
  spec.email         = ["hrittich@users.noreply.github.com"]
  spec.license       = 'Apache-2.0'

  spec.summary       = %q{Securely updates DNS records in a zone hosted by OVH.}
  spec.homepage      = "https://github.com/hrittich/ovh_dnsup"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'faraday', '~> 1.3.0', '>= 1.3.0'
end
