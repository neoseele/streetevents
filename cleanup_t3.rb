#!/usr/bin/env ruby
require 'find'
require 'fileutils'

## load the base class
require File.join(File.dirname($0), 'base.rb')

class Worker < Base

  def fix(input, output)
    data = []

    File.open(input, 'r').each do |line|
      clean_line = line.chars.select(&:valid_encoding?).join
        .gsub(/\r\n?/,'|')
        .clean_up

      if clean_line.include?('|')
        clean_line.split('|').each do |s|
          data << s.strip
        end
      else
        data << clean_line
      end
    end

    info "saving #{input} to #{output}"
    File.open(output, 'w+') do |f|
      f.puts(data)
    end
  end
end

### functions

def usage
  puts 'Usage: ' + File.basename(__FILE__) + ' <directory>'
  exit 1
end

usage unless ARGV.length == 1 and File.directory?(ARGV[0])

worker = Worker.new

source_dir = ARGV[0]
output_dir = 'fixed'

# create the output directory
FileUtils.mkdir(output_dir) unless File.directory?(output_dir)

Find.find(source_dir) do |input|
  if File.directory?(input)
    next
  else
    if File.extname(input) == '.txt' and not File.basename(input) =~ /^\./
      output = File.join(output_dir, File.basename(input))
      worker.fix(input, output)
    end
  end
end
