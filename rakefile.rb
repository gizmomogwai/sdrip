out_dir = directory 'out'

task :favicon do
  sh "wget http://localhost:4567/favicon.png -O #{out_dir}/favicon.png"
end

task :state do
  out = "#{out_dir}/state.json"
  sh "wget http://localhost:4567/state -O #{out}"
  sh "cat #{out}"
end

task :activate do
  out = "#{out_dir}/activate.json"
  sh "wget '--post-data=profile=test' http://localhost:4567/activate  -O #{out}"
  sh "cat #{out}"
end

task :set do
#  sh "wget '--post-data={\"data\":{\"a\":\"b\", \"c\":\"d\"}}'  --header=Content-Type:application/json http://localhost:4567/set -O #{out_dir}/set.json"
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
