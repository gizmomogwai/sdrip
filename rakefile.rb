def os
  if RUBY_PLATFORM.include?('darwin')
    return :osx
  end

  if RUBY_PLATFORM.match(Regexp.new('arm.*linux.*'))
    return :raspi
  end

  raise "Platform not supported: #{RUBY_PLATFORM}"
end

task 'source/versioninfo.d' do
  sha = `git rev-parse HEAD`.strip
  desc = `git describe --dirty`.strip;
  File.write("source/versioninfo.d", "module versioninfo;\nstatic const string SHA=\"#{sha}\";\nstatic const string DESCRIPTION=\"#{desc}\";\n")
end

task :sync do
  sh "rsync -a --progress --exclude .dub --exclude settings.yaml --exclude out --exclude sdrip --exclude sdrip-test-ut --exclude unittest . osmc@wohnzimmer.local:./sdrip"
end

def output_folder
  File.join('out', os.to_s)
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

file "sdrip" => (Dir.glob("**/*.d") + Dir.glob("**/*.dt") + Dir.glob("dub.*") + Dir.glob("rakefile.rb") + [f, 'source/versioninfo.d']) do
  sh "dub build --verbose"
end

task :build => [lib, 'sdrip']
desc 'quicktest'
task :qtest do
  sh "dub test -c ut"
end
desc 'test'
task :test do
  sh "dub test -c ut || dub test"
end
task :default => [:build]

desc 'format'
task :format do
  sh 'find source -name "*.d" | xargs dfmt -i'
end

['schlafzimmer', 'wohnzimmer'].each do |room|
  desc "deploy to #{room}"	
  task "deploy_to_#{room}" do
    cd ".." do
      sh "rsync -va --exclude *.o --exclude sdrip --exclude out --exclude .dub sdrip2 #{room}:."
    end
  end
end
