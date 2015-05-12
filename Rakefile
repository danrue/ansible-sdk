require 'bundler/gem_tasks'

task :test do 
  sh "rspec spec/* --color --format=documentation"
end 

task :uninstall do
  sh "gem uninstall -a -x ansible-sdk"
end

task :reinstall => [ :uninstall, :install ]
