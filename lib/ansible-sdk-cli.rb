
require 'thor' 
require 'ansible-sdk' 

class AnsibleSDKCLI < Thor
  class_option :build_dir, type: :string, default: 'build'

  desc 'role_artifact', 'build role artifact(s)'
  def role_artifact deploy_type
    version = bump_version(deploy_type)

    excludefile = Tempfile.new('excludes')
    excludefile.write "#{(asdk.role_excludes.join "\n")}\n"
    excludefile.fsync

    this_role = name(Dir.pwd)

    Dir.entries('roles').reject{ |d|
      asdk.role_excludes.include?(d) or ! File.directory? "roles/#{d}" or d != this_role
    }.each do |roledir|
      paths = asdk.role_paths.select{ |p|
        File.exists? "roles/#{roledir}/#{p}"
      }

      role = File.basename(roledir)
      path = File.join 'roles', roledir
      asdk.log.debug "Building role #{role} from #{roledir}"
      result = asdk.execute(
        "mkdir -p '#{options[:build_dir]}' && tar cvzpf #{options[:build_dir]}/#{roledir}-#{version}.tgz " +
          "-X #{excludefile.path} " +
          "-C #{path} #{ paths.join " " }"
      ) 
      unless result[:exit_status] == 0
        raise CommandError, 
          "Couldn't build role tarball for #{role} from #{roledir}"
     end
   end
  end

  desc 'playbook_artifact', 'Build playbook artifacts'
  def playbook_artifact deploy_type
    version = bump_version(deploy_type)

    excludefile = Tempfile.new('excludes')
    excludefile.write "#{(asdk.playbook_excludes.join "\n")}\n"
    excludefile.fsync
    playbook_name = 'ansible-pb-' + name(File.expand_path('.'))

    entries = Dir.entries('./').reject{ |d| asdk.playbook_excludes.include? d }
    asdk.log.debug "Building playbook artifact for #{playbook_name}"
    result = asdk.execute(
      "mkdir -p '#{options[:build_dir]}' && tar cvzpf " +
      "'#{options[:build_dir]}/#{playbook_name}-#{version}.tgz' " +
      "-X #{excludefile.path} " +
      "-C . #{ entries.join " " }"
    ) 
    unless result[:exit_status] == 0
      raise CommandError, 
      "Couldn't build playbook tarball for #{role} from #{roledir}"
    end
  end

  desc 'publish_artifact', 'Publish artifact to S3'
  option :force,  type: :boolean, default: false
  option :public, type: :boolean, default: false
  option :fail_on_exist, type: :boolean, default: false
  def publish_artifact path, s3_bucket = 'sps-build-deploy', s3_path = 'ansible/'
    require 'aws-sdk'
    s3_key = File.join s3_path, File.basename(path)
    s3 = ::AWS::S3.new
    bucket = s3.buckets[s3_bucket]
    s3object = bucket.objects[s3_key]
    if s3object.exists?
      if options[:force]
        asdk.log.warn "Warn: forcing overwrite of #{s3object.key}"
      else
        asdk.log.fatal "Object already exists and force is not set; aborting"

        if options[:fail_on_exist]
          exit 1
        end
       return false
      end
    end
    File.open( path, "r" ) do |f|
      s3object.write(f)
    end

    asdk.log.info "Setting Object ACLs"
    s3object.acl = { :grant_full_control => "emailAddress=\"AWS_Development@spscommerce.com\", id=\"ea4d1ef911bc199d5b7967bd2dd39867891a50203a590ecfaa0f0350defe2059\"" }
    return true
  end

  desc 'dependencies', 'resolve dependencies'
  def dependencies path='./requirements.yml'
    require 'yaml'
    require 'tempfile'
    requirements = YAML.load( File.read(path) )
    requirements.each do |requirement|
      asdk.log.debug "Attempting to meet dependency: #{requirement.inspect}"
      if requirement['url'] =~ %r(^s3://)
        matchdata =  requirement['url'].match(%r|s3://([^/]+)/(.*)$|)
        bucket = matchdata[1]
        path = matchdata[2]
        require 'aws-sdk'
        s3obj = ::AWS::S3.new.buckets[bucket].objects[path]
        unless s3obj.exists?
          raise Exception, "S3 object #{requirement['url']} does not exist"
        end
        file = Tempfile.new('requirement')
        s3obj.read do |chunk|
          file.write(chunk)
        end
        file.fsync
        asdk.unarchive( file.path, requirement['paths'] )
        file.unlink
      elsif requirement['method'] == 'git' or requirement['url'] =~ /git@github\.com/
        raise Exception, "git backends Unimplemented"
      elsif requirement['url'] =~ %r(https?://)
        raise Exception, "http(s) backends Unimplemented"
      else
        asdk.log.fatal(msg="Couldn't resolve dependency: #{requirement.inspect}")
        raise ArgumentError, msg
      end
    end
  end

private
  def name(dir)
    require 'yaml'

    metadata_file = 'metadata.yml'
    name = File.basename(dir)

    if File.exist?(metadata_file)
      yaml = YAML.load_file(metadata_file)

      if yaml.key?('name')
        name = yaml['name']
      end
    end

    name
  end

  def bump_version(deploy_type)
    unless ['patch', 'minor', 'major'].include? deploy_type
      abort('Deploy type must be one of the following: major, minor, patch')
    end

    version = %x(thor version:bump #{deploy_type})

    return version
  end

  def asdk
    ansible_sdk
  end
  def ansible_sdk
    @ansible_sdk ||= AnsibleSDK.new
    @ansible_sdk
  end

end
