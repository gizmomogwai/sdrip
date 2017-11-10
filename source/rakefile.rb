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
  File.join('out', os.to_s)
end

directory output_folder
obj = file "#{output_folder}/libdotstar.o" =>
           ['source/c/libdotstar.c', 'source/c/libdotstar.h', output_folder, 'rakefile.rb'] do |t|
  flags = os == :osx ? "-DSIM_SPI=1" : "-DREAL_SPI=1"
  flags = os == :raspi ? flags + " -mhard-float " : flags
  sh "gcc -std=c11 -c #{flags} -o #{t.name} #{t.prerequisites.first}"
end

lib = file "#{output_folder}/libdotstar.a" => [obj] do |t|
  sh "ar rcs #{t.name} #{t.prerequisites.first}"
end
