
require 'thor' 
require 'ansible-sdk' 

class AnsibleSDKCLI < Thor

  desc 'role_artifact', 'build role artifact(s)'

  def role_artifact
    excludefile = Tempfile.new('excludes')
    excludefile.write "#{(asdk.role_excludes.join "\n")}\n"
    excludefile.fsync
   Dir.entries('roles').reject{ |d| 
      asdk.role_excludes.include?(d) or !File.directory?(d)
    }.each do |roledir|
      role = File.basename(roledir)
      path = File.join 'roles', roledir
      asdk.log.debug "Building role #{role} from #{roledir}"
      result = asdk.execute(
        "tar cvjpf build/#{roledir}-#{asdk.version path}.tbz2 " +
          "-X #{excludefile.path} " +
          "-C #{path} #{ asdk.role_paths.join " " }"
      ) 
      unless result[:exit_status] == 0
        raise CommandError, 
          "Couldn't build role tarball for #{role} from #{roledir}"
     end
   end
  end

  desc 'playbook_artifact', 'Build playbook artifacts'
  def playbook_artifact 
    excludefile = Tempfile.new('excludes')
    excludefile.write "#{(asdk.playbook_excludes.join "\n")}\n"
    excludefile.fsync
    playbook_name = File.basename( File.expand_path('.') )
    entries = Dir.entries('./').reject{ |d| asdk.playbook_excludes.include? d }
    asdk.log.debug "Building playbook artifact for #{playbook_name}"
    result = asdk.execute(
      "tar cvjpf " +
      "build/#{playbook_name}-#{asdk.version '.'}.tbz2 " + 
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
  def publish_artifact path, s3_bucket = 'sps-build-deploy', s3_path = 'ansible/'
    require 'aws-sdk'
    s3_key = File.join s3_path, File.basename(path)
    s3 = AWS::S3.new
    bucket = s3.buckets[s3_bucket]
    s3object = bucket.objects[s3_key]
    if s3object.exists?
      if options[:force] 
        asdk.log.warn "Warn: forcing overwrite of #{s3object.key}"
      else
        asdk.log.fatal "Object already exists and force is not set; aborting"
       return false
      end
    end
    File.open( path, "r" ) do |f|
      s3object.write(f)
    end
    asdk.log.info "File #{path} written to #{s3object.key}"
    acl = ( options[:public] ? :public_read : :private )
    s3object.acl = acl
    asdk.log.debug "ACL set to :#{acl}"
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
        s3obj = AWS::S3.new.buckets[bucket].objects[path]
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

  def asdk
    ansible_sdk
  end
  def ansible_sdk
    @ansible_sdk ||= AnsibleSDK.new
    @ansible_sdk
  end

end
