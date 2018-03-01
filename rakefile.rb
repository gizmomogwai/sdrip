out_dir = directory 'out'

task :favicon do
  sh "wget http://localhost:4567/favicon.png -O #{out_dir}/favicon.png"
end

task :state do
  out = "#{out_dir}/state.json"
  sh "wget http://localhost:4567/state -O #{out}"
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
       :set,
       :shutdown
     ]

task :default => [:test]
