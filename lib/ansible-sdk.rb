
require 'logger'
require 'open3'

class AnsibleSDK
  
  def self.log_level level
    @@log_level = level
  end

  def self.log 
    @@log ||= Logger.new $stderr
    if class_variable_defined?( :@@log_level ) && @@log_level
      @@log.level = @@log_level
      @@log_level = nil
    end
    @@log
  end

  def log 
    self.class.log
  end

  def execute( cmd,success_status=0)
    log.debug "Executing command: #{cmd}"
    stdout, stderr, status = Open3.capture3(cmd)
    result = { 
      stdout: stdout, stderr: stderr, status: status, 
      exit_status: status.exitstatus, cmd: cmd }
    if success_status and result[:exit_status] != success_status
      command_error result
    end
    result
  end

  def command_error results
    raise  CommandError, 
"Failed to execute command!
Command: #{results[:cmd]}
Stdout: #{results[:stdout]}
Stderr: #{results[:stderr]}
Exit Status #{results[:exit_status]}"
  end

  def role_paths
    return %w(
      defaults files handlers meta tasks templates vars library
    )
  end
  
  def shared_excludes
    %w( 
        . .. 
        .gitignore .git 
        Rakefile 
        .kitchen .kitchen.yml 
        README.md 
        test tests spec
        Vagrantfile 
        .vagrant
        build
        VERSION
        Thorfile
        Gemfile Gemfile-e
    )
  end

  def playbook_excludes 
    shared_excludes + %w( inventory/groups inventory/vagrant )
  end

  def role_excludes 
    shared_excludes
  end

  def unarchive(archivepath,paths )
    Dir.mktmpdir() do |tmpdir|
      results= execute("tar xvpf #{archivepath} -C #{tmpdir}")
      log.debug results[:stderr]
      paths.each do |path|
      FileUtils.mkdir_p path['to']
        log.debug "#{File.join(tmpdir, path['from'])}\t=>\t#{path['to']}"
        FileUtils.cp_r(File.join(tmpdir, path['from']), path['to'])
        gitignore_path(path['to'])
      end
    end
  end

  def gitpath(archivepath,paths )
    paths.each do |path|
    FileUtils.mkdir_p path['to']
      log.debug "#{File.join(archivepath, path['from'])}\t=>\t#{path['to']}"
      FileUtils.rm_rf( File.join(archivepath, ".git"))
      FileUtils.cp_r(File.join(archivepath, path['from']), path['to'])
      gitignore_path(path['to'])
    end
  end

  def version path='./'
      versionpath = File.join path, 'VERSION' 
      begin
        version = File.read(versionpath).strip
      rescue Errno::ENOENT => e
        File.open(versionpath,'w') do |f|
          f.write('0.0.0')  
        end
        retry
      end
      version
  end

  def gitignore_path path
    path.gsub!( %r|^\.+/(.*)$|, '\1')
    if File.exists? '.gitignore' \
       and File.read('.gitignore').lines.grep(/#{Regexp.escape "#{path}\n"}/).count > 0
      log.debug ".gitignore already contains #{path}"
    else
      File.open('.gitignore','a+') { |f|
        # determine if newline must be added before
        if f.size > 0
          f.seek(-1, IO::SEEK_END)
          f.write "\n" if f.read(1) != "\n" # append always writes at end!
        end
        f.puts "#{path}"
        f.sync
      }
    end
  end

  class CommandError < Exception; end
end
