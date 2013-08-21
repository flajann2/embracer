require 'socket'

host = 'localhost'
port = 5009

s = TCPSocket.open(host, port)

t = Thread.start {
  while line = s.gets
    puts line.chop
  end
}

s.puts "w@ES#"
s.puts "w@NQ#"

t.join
