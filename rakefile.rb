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
  {
    name: "wohnzimer",
    stop_command: "sudo systemctl stop sdrip",
    start_command: "sudo systemctl start sdrip",
    status_command: "sudo systemctl status sdrip",
    home: "/home/osmc",
  },
  {
    name: "seehaus-piano",
    stop_command: "systemctl --user stop sdrip",
    start_command: "systemctl --user start sdrip",
    status_command: "systemctl --user status sdrip",
    home: "/home/pi",
  },
].each do |host|

  name = host[:name]
  stop_command = host[:stop_command]
  start_command = host[:start_command]
  status_command = host[:status_command]
  home = host[:home]

  namespace :deploy do
    desc "Deploy to #{name}"
    task name do
      on [name] do
        info "Working on #{name}"
        execute(stop_command)
        execute("rm -rf ~/sdrip")
        execute("mkdir ~/sdrip")
        Dir.glob("source/deployment/sites/#{host}/*").each do |file|
          puts "uploading #{file}"
          puts capture "ls -l #{home}"
          upload!(file, "#{home}/sdrip/")
        end
        execute("mkdir", "-p", "#{home}/sdrip/public")
        Dir.glob("public/*").each do |file|
          upload!(file, "#{home}/sdrip/public/#{File.basename(file)}")
        end
        upload!("out/main/raspi/sdrip", "#{home}/sdrip/")
        upload!("source/deployment/sites/#{name}/settings.yaml", "#{home}/sdrip")
        execute(start_command)
      end
    end
  end

  namespace :status do
    desc "Status of #{host}"
    task name do
      on [name] do
        puts capture(status_command)
      end
    end
  end
end
