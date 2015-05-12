require 'thor'
require 'thor-scmversion'
require 'ansible-sdk'

class AnsibleSDKCLI < Thor
  class_option :build_dir, type: :string, default: 'build'

  def initialize *args
    super
    @index = 0
    metadata
  end

  desc 'build_artifact', 'build Ansible artifact(s)'
  def build_artifact deploy_type
    version = "0.0.0"
    if deploy_type != "none"
      version = bump_version(deploy_type)
      asdk.log.info "Current version after bump is: #{version}"
    else
      asdk.log.debug "No version increase; Current version is: #{version}"
    end
    (0..@metadata.length-1).each do |i|
      @index = i
      build_artifact_index 
    end
  end
  
  desc 'deploy', 'Build and publish artifact(s) to S3'
  def deploy deploy_type
    (0..@metadata.length-1).each do |i|
      @index  = i
      artifact = build_artifact_index
      publish_artifact_index(artifact) unless deploy_type == "none"
    end
  end

  desc 'publish_artifact', 'Publish specified artifact to S3'
  option :force,  type: :boolean, default: false
  option :public, type: :boolean, default: false
  option :fail_on_exist, type: :boolean, default: false
  def publish_artifact path, s3_bucket = 'sps-build-deploy', s3_path = 'ansible/'
    (0..@metadata.length-1).each do |i|
      @index = i
      publish_artifact_index path, s3_bucket, s3_path
    end
  end

  desc 'dependencies', 'resolve dependencies'
  def dependencies path='./requirements.yml'
    require 'yaml'
    require 'tempfile'

    unless File.file?(path)
      asdk.log.info "No requirements.yml file"
      exit 0
    end

    requirements = YAML.load( File.read(path) )

    if requirements.nil?
      asdk.log.info "No requirements in requirements.yml file"
      exit 0
    end

    requirements.each do |requirement|
      asdk.log.debug "Attempting to meet dependency: #{requirement.inspect}"
      if requirement['url'] =~ %r(^s3://)
        matchdata =  requirement['url'].match(%r|s3://([^/]+)/(.*)$|)
        bucket = matchdata[1]
        path = matchdata[2]
        require 'aws-sdk'
        s3obj = ::AWS::S3.new.buckets[bucket].objects[path]
        unless s3obj.exists?
          raise ConfigError, "S3 object #{requirement['url']} does not exist"
        end
        file = Tempfile.new('requirement')
        s3obj.read do |chunk|
          file.write(chunk)
        end
        file.fsync
        asdk.unarchive( file.path, requirement['paths'] )
        file.unlink
      elsif requirement['method'] == 'git' or requirement['url'] =~ /git@github\.com/
        raise ConfigError, "git backends Unimplemented"
      elsif requirement['url'] =~ %r(https?://)
        raise ConfigError, "http(s) backends Unimplemented"
      else
        asdk.log.fatal(msg="Couldn't resolve dependency: #{requirement.inspect}")
        raise ArgumentError, msg
      end
    end
  end

private
  # consistent single location where file location is specified
  def metadata_file
    'metadata.yml'
  end
  # built-in documentation for the metadata file.  Could be used in error messages, etc.  
  def metadata_fields
    return { 
      'name'=> { 
        'description'=> %Q(Name of artifact without version.  Typically this is the name of the role or playbook.  If unspecified, the name of the directory from which the ansible-sdk has been written, will be used),
        'optional'=> true,
        'validation'=> '/^[_-a-zA-Z0-9.]+$/'
      },
      'type'=> {
        'description'=> %Q(Type of artifact: role or playbook?),
        'optional'=> false,
        'validation' => '/^(role|playbook)$/'
      },
      'ansible_path' => {
        'description' => %Q(the root of the ansible code, defaulting to the current directory),
        'optional' => true,
        'validation'=> 'valid path'
      }   
    }
  end

  def cache_metadata
    begin
      require 'yaml'
      @metadata = YAML.load_file( metadata_file )
      @metadata = [ @metadata ] unless @metadata.kind_of? Array
      asdk.log.debug @metadata.inspect
    rescue Errno::ENOENT => e 
      raise ConfigError, "No config metadata file '#{metadata_file}' found; Please create a #{metadata_file} metadata file"
    end
  end

  # lookup and cache metadata or return from cache
  def metadata index=nil
    index=@index unless index
    cache_metadata unless instance_variable_defined? :@metadata
    @metadata[index]
  end

  # return configured name, default to directory name
  def name(dir)
    begin
      name = metadata['name']
    rescue ConfigError => e 
    end 
    name ||= File.basename(dir) 
  end

  def type
    data = metadata['type']
    unless data
      raise ConfigError, "type is a required field:  #{metadata_fields['type'].inspect}"
    end
    data
  end

  def ansible_path
    data = metadata['ansible_path'] 
    data ||= './'
  end

  def bump_version(deploy_type)
    unless ['patch', 'minor', 'major'].include? deploy_type
      abort('Deploy type must be one of the following: major, minor, patch')
    end

    scm = ::ThorSCMVersion::Tasks.new
    scm.bump(deploy_type)
    current_version = ::ThorSCMVersion.versioner.from_path
    return current_version
  end

  def setup_aws_credentials
    key = ENV['AWS_KEYS']
    if key.nil?
      if ENV['AWS_ACCESS_KEY_ID'].nil? || ENV['AWS_SECRET_ACCESS_KEY'].nil?
        asdk.log.warn "AWS_KEYS not set"
      end
    else
      ENV['AWS_ACCESS_KEY_ID'] = key.split(':')[0].strip
      ENV['AWS_SECRET_ACCESS_KEY'] = key.split(':')[1].strip
    end
  end
  
  def build_artifact_index 

    artifact_name = name(Dir.pwd)
    artifact_file_name = ''
    target_files = ''
    artifact_file_path = File.expand_path(options[:build_dir])
    Dir.chdir(ansible_path) do
      excludefile = Tempfile.new('excludes')
      if type == "role"
        asdk.log.debug "Building role #{artifact_name} from roles/#{artifact_name}"
        artifact_file_name = File.join( artifact_file_path, "#{artifact_name}-#{version}.tgz" )

        excludefile.write "#{(asdk.role_excludes.join "\n")}\n"

        paths = asdk.role_paths.select{ |p|
          File.exists? "roles/#{artifact_name}/#{p}"
        }

        path = File.join 'roles', artifact_name
        target_files = "#{ paths.join " " }"

      elsif type == "playbook"
        asdk.log.debug "Building playbook artifact for ansible-pb-#{artifact_name}"
        artifact_file_name = File.join( artifact_file_path, "ansible-pb-#{artifact_name}-#{version}.tgz" )

        excludefile.write "#{(asdk.playbook_excludes.join "\n")}\n"

        paths = Dir.entries('./').reject{ |d| asdk.playbook_excludes.include? d }
      
        path = "."
        target_files = "#{ paths.join " " }"
      else
        raise CommandError, 
          "Couldn't build artifact type '#{type}'"
      end
      excludefile.fsync    

      result = asdk.execute(
        "mkdir -p '#{options[:build_dir]}' && tar cvzpf #{artifact_file_name} " +
          "-X #{excludefile.path} " +
          "-C #{path} #{target_files}"
      ) 

      unless result[:exit_status] == 0
        raise CommandError, 
          "Couldn't build artifact tarball for #{artifact_name}"
      end
    end
    return artifact_file_name
  end

  def publish_artifact_index path, s3_bucket='sps-build-deploy', s3_path = 'ansible/'
    require 'aws-sdk'
    setup_aws_credentials()

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

  def asdk
    ansible_sdk
  end
  def ansible_sdk
    @ansible_sdk ||= AnsibleSDK.new
    @ansible_sdk
  end
  class CommandError < Exception; end
  class DeprecationError < Exception; end
  class ConfigError < Exception; end
end
