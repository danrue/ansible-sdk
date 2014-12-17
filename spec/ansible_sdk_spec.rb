require_relative '../lib/ansible-sdk.rb'

describe AnsibleSDK do

  it "initializes" do
    expect{ AnsibleSDK.new }.not_to raise_error
  end

  it "Allows setting log level" do
    AnsibleSDK.log_level Logger::WARN
    expect(AnsibleSDK.log.level).to eq(Logger::WARN)
  end

  it "calls capture3 successfully" do
    expect(AnsibleSDK.new.execute("true").reject{|k,v| k == :status}).to eq(
      { cmd: 'true', exit_status: 0, stdout: "", stderr: "" }
    )
    expect(AnsibleSDK.new.execute("false",1).reject{|k,v| k == :status}).to eq(
      { cmd: 'false', exit_status: 1, stdout: "", stderr: "" }
    )
    expect {
      AnsibleSDK.new.execute("false")
    }.to raise_error(AnsibleSDK::CommandError)
    expect(AnsibleSDK.new.execute("echo 'Hi, world!'",0).reject{ |k,v| 
      [:status, :cmd ].include? k 
    }).to eq(
      { exit_status: 0, stdout: "Hi, world!\n", stderr: "" }
    )
  end

  it 'provides list of ansible role files' do
    role_paths = AnsibleSDK.new.role_paths
    expect(role_paths).to be_kind_of(Array)
    expect(role_paths.include? 'tasks').to eq(true)
  end
  
  it 'can unarchive'
  
  it 'can append to a .gitignore' do
    Dir.chdir '/tmp/' do

      f = File.open(".gitignore", "w+") do |f|
        f.write("somefile.txt") 
        f.sync
      end
      AnsibleSDK.log_level Logger::DEBUG
      AnsibleSDK.new.gitignore_path "anotherfile/" 
      expect( File.read('.gitignore') ).to eq("somefile.txt\nanotherfile/\n")
  
      AnsibleSDK.new.gitignore_path "athirdpath/" 
      expect( File.read('.gitignore') ).to eq(
        "somefile.txt\nanotherfile/\nathirdpath/\n"
      )
 
      File.open(".gitignore", "w") { |f| f.truncate(0) }
      AnsibleSDK.new.gitignore_path( "afile.txt" )
      expect( File.read('.gitignore') ).to eq("afile.txt\n")
      
      
      File.open(".gitignore", "w") { |f| f.truncate(0) }
      AnsibleSDK.new.gitignore_path( "./adir/" )
      AnsibleSDK.new.gitignore_path( "../adir2/" )
      expect( File.read('.gitignore') ).to eq("adir/\nadir2/\n")
    end
  end
  it 'does not append the same thing twice' do 
    Dir.chdir '/tmp' do
      File.open(".gitignore", "w") { |f| f.truncate(0) }
      AnsibleSDK.new.gitignore_path( "./adir/" )
      AnsibleSDK.new.gitignore_path( "./adir/" )
      expect( File.read('.gitignore') ).to eq("adir/\n")
    end
  end

end
