require "json"
require "awesome_print"

def rest(endpoint)
  "http://localhost:4567/api/#{endpoint}"
end

def out_dir
  "out"
end
directory out_dir


namespace :test do
  namespace :web do
    desc "favicon"
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

  return :linux

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

desc "build for raspi"
task :build_for_raspi_with_docker do |t, args|
  out = "out/main/raspi"
  uid = `id -u`.strip
  sh "mkdir -p #{out}"
#  sh "docker run -u#{uid}:#{uid} --rm --interactive --tty --mount type=bind,src=#{Dir.pwd},dst=/ws --entrypoint=/usr/bin/bash cross-ldc:0.0.1 -c 'arm-linux-gnueabihf-gcc -c -DREAL_SPI=1 -mhard-float source/c/libdotstar.c -o #{out}/libdotstar.o && arm-linux-gnueabihf-ar rcs #{out}/libdotstar.a #{out}/libdotstar.o'"
  sh "docker run -u#{uid}:#{uid} --rm --interactive --tty --mount type=bind,src=#{Dir.pwd},dst=/ws cross-ldc:0.0.1 -c application-raspi"
end

desc "Build cross ldc docker image"
task :build_docker_image do
  sh "docker build . -t cross-ldc:0.0.1"
end
require "sshkit"
require "sshkit/dsl"
include SSHKit::DSL

hosts = [
  "wohnzimmer",
  "seehaus-piano",
].each do |host|

  namespace :deploy do
    desc "Deploy to #{host}"
    task host do
      on [host] do
        info "Working on #{host}"
        execute("sudo systemctl stop sdrip")
        execute("rm -rf ~/sdrip")
        execute("mkdir ~/sdrip")
        Dir.glob("source/deployment/sites/#{host}/*").each do |file|
          puts "uploading #{file}"
          puts capture "ls -l /home/osmc"
          upload!(file, "/home/osmc/sdrip/")
        end
        upload!("out/main/raspi/sdrip", "/home/osmc/sdrip/")
        execute("sudo systemctl start sdrip")
      end
    end
  end
  namespace :status do
    desc "Status of #{host}"
    task host do
      on [host] do
        puts capture("systemctl status sdrip")
      end
    end
  end
end
