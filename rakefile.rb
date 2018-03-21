require 'json'
require "awesome_print"

def rest(endpoint)
  "http://localhost:4567/api/#{endpoint}"
end

def out_dir
  'out'
end
directory out_dir


namespace :test do
  namespace :web do
    desc 'favicon'
    task :favicon do
      sh "wget http://localhost:4567/favicon.png -O #{out_dir}/favicon.png"
    end
  end

  namespace :rest do
    desc 'state'
    task :state do
      out = "#{out_dir}/state.json"
      sh "wget #{rest('state')} -O #{out}"
      ap JSON.parse(File.read(out))
    end


    def activate(what)
      out = "#{out_dir}/activate_#{what}.json"
      sh "wget -v '--post-data={\"renderer\":\"#{what}\"}' --header=Content-Type:application/json #{rest('activate')} -O #{out}"
      sh "cat #{out}"
    end

    desc 'activate'
    task :activate do
      ["rainbow", "red", "green", "blue"].each do |what|
        activate(what)
        sleep(2)
      end
    end

    def set(v)
      sh "wget -v --method=PUT '--body-data={\"data\":{\"blue.active\":\"#{v}\"}}' --header=Content-Type:application/json #{rest('set')} -O #{out_dir}/set_#{v}.json"
    end

    desc 'set'
    task :set do
      5.times do
        set(false)
        sleep(1);
        set(true)
        sleep(1);
      end
      set(false)
    end

    desc 'shutdown'
    task :shutdown do
      #sh "http  http://localhost:4567/shutdown"
    end

  end
end
desc 'test server'
task :test => [
       out_dir,
       'test:web:favicon',
       'test:rest:state',
       'test:rest:activate',
       'test:rest:set',
       'test:rest:shutdown',
     ]

def os
  if RUBY_PLATFORM.include?('darwin')
    return :osx
  end

  if RUBY_PLATFORM.match(Regexp.new('arm.*linux.*'))
    return :raspi
  end

  raise "Platform not supported: #{RUBY_PLATFORM}"
end
def output_folder
  File.join('out', 'main', os.to_s)
end

directory output_folder
lib = file "#{output_folder}/libdotstar.o" => ['source/c/libdotstar.c', 'source/c/libdotstar.h', output_folder, 'rakefile.rb'] do |t|
  flags = os == :osx ? "-DSIM_SPI=1" : "-DREAL_SPI=1"
  flags = os == :raspi ? flags + " -mhard-float " : flags
  sh "gcc -std=c11 -c #{flags} -o #{t.name} #{t.prerequisites.first}"
end

f = file "#{output_folder}/libdotstar.a" => ["#{output_folder}/libdotstar.o"] do |t|
  sh "ar rcs #{t.name} #{t.prerequisites.first}"
end

task 'out/main/sdrip3' do
  sh "dub build --compiler=dmd"
end

task :build => [f, 'out/main/sdrip3']

task :default => [:build, :test]

desc 'install needed gems'
task :install_gems do
  sh "gem install sshkit"
end

desc 'build for raspi'
task :build_for_raspi do
  sh "raspi.sh make"
  sh "raspi.sh dub build --compiler=ldc-raspi"
end

desc 'deploy to targets'
task :deploy do
  require 'sshkit'
  require 'sshkit/dsl'
  include SSHKit::DSL
  users = {"wohnzimmer" => "user1"}
  on ['wohnzimmer', 'schlafzimmer'], in: :sequence, wait: 5 do |host|
    info "Working on #{host}"
    execute('sudo systemctl stop sdrip')
    execute('rm -rf /home/osmc/sdrip')
    execute('mkdir -p /home/osmc/sdrip')
    (Dir.glob("deployment/#{host}/*") + Dir.glob("deployment/*"))
      .each do |file|
      if File.file?(file)
        upload! file, "/home/osmc/sdrip/"
      end
    end
    upload! "out/main/raspi/sdrip", "/home/osmc/sdrip/"
    execute('sudo systemctl start sdrip')
  end
end
