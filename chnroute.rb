#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'ipaddr'

def fetch_apnic_data
  regex = Regexp.new('apnic\|cn\|ipv4\|[0-9\.]+\|[0-9]+\|[0-9]+\|a.*', 
                     Regexp::IGNORECASE)

  uri = URI('http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest')
  uri_test = URI('http://localhost/~jack/delegated-apnic-latest')
  data = Net::HTTP.get(uri)
  cndata = data.scan(regex)

  results = []
  cndata.each do |d|
    a,b,c, start_ip, value, f,g = d.split('|')
    # netmask is for the 255.255.255.0 format
    netmask = IPAddr.new(0xffffffff ^ (value.to_i - 1), Socket::AF_INET).to_s
    # cidr is for the 10.0.1.0/24 format
    cidr = (0xffffffff ^ (value.to_i - 1)).to_s(2).count("1")
    results << [start_ip, "/#{cidr}"]
#    return results if results.size > 10
  end
  return results
end

def generate_mac
  results = fetch_apnic_data

  upscript_header = <<-END_OF_STRING
#!/bin/sh
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

OLDGW=`netstat -nr | grep '^default' | grep 'en0\\|en1' | grep -v 'ppp' \
| sed 's/default *\\([0-9\.]*\\) .*/\\1/'`

if [ ! -e /tmp/pptp_oldgw ]; then
    echo "${OLDGW}" > /tmp/pptp_oldgw
fi

dscacheutil -flushcache
  END_OF_STRING

  downscript_header = <<-END_OF_STRING
#!/bin/sh
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

if [ ! -e /tmp/pptp_oldgw ]; then
        exit 0
fi

ODLGW=`cat /tmp/pptp_oldgw`
  END_OF_STRING

  upfile = File.new("ip-up", "w")
  downfile = File.new("ip-down", "w")

  upfile.puts "#{upscript_header}\n"
  downfile.puts "#{downscript_header}\n"

  results.each do |start_ip, cidr|
    upfile.puts "route add #{start_ip}#{cidr} ${OLDGW}\n"
    downfile.puts "route delete #{start_ip}#{cidr} ${OLDGW}\n"
  end

  File.open("company-ip.txt") do |file|
    file.each_line do |line|
      upfile.puts "route add #{line[0..-2]} ${OLDGW}\n"
      downfile.puts "route delete #{line[0..-2]} ${OLDGW}\n"
    end
  end

  upfile.close
  downfile.close
end

generate_mac

