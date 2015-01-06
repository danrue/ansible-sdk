
Gem::Specification.new do |spec|
  spec.name          = 'ansible-sdk'
  spec.version       = '0.9.11'
  spec.authors       = ['Dan Farrell (dfarrell@spscommerce.com)']
  spec.email         = %w( cloudops@spscommerce.com )
  spec.summary       = 'Provides a consistent base for ansible development.'
  spec.description   = 'See Summary'
  spec.homepage      = 'https://github.com/farrellit/ansible-sdk'
  spec.license       = 'Apache License'

  git_files         = `git ls-files -z`.split(/\000/)
  spec.files = git_files.select{ |f| f =~ /^(lib|bin)\// }
  spec.executables   = git_files.grep(%r{^bin/}) { |f| File.basename(f) }
  #  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = %w( lib )
  spec.add_development_dependency 'bundler'
  spec.add_dependency 'thor'
  spec.add_dependency 'aws-sdk'
end
