require 'json'
require "awesome_print"

def out_dir
  'out'
end
directory out_dir

task :favicon do
  sh "wget http://localhost:4567/favicon.png -O #{out_dir}/favicon.png"
end

task :state do
  out = "#{out_dir}/state.json"
  sh "wget http://localhost:4567/state -O #{out}"
  ap JSON.parse(File.read(out))
end


def activate(what)
  out = "#{out_dir}/activate_#{what}.json"
  sh "wget -v '--post-data={\"profile\":\"#{what}\"}' --header=Content-Type:application/json http://localhost:4567/activate -O #{out}"
  sh "cat #{out}"
end

task :activate do
  ["rainbow", "red", "green", "blue"].each do |what|
    activate(what)
    sleep(2)
  end
end

def set(v)
  sh "wget '--post-data={\"data\":{\"blue.active\":\"#{v}\"}}'  --header=Content-Type:application/json http://localhost:4567/set -O #{out_dir}/set_#{v}.json"
end

task :set do
  5.times do
    set(false)
    sleep(1);
    set(true)
    sleep(1);
  end
  set(false)
end

task :shutdown do
  #sh "http  http://localhost:4567/shutdown"
end

desc 'test server'
task :test => [
       out_dir,
       :favicon,
       :state,
       :activate,
       :set,
       :shutdown,
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
