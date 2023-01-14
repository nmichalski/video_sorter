require 'set'
require 'fileutils'

$stdout.sync = true
$stderr.sync = true


# --- Parameters ---

ORIGIN="/media/Fast/uTorrent/completed_downloads/.*"


# --- Script ---

begin
  folder_of_this_script = File.expand_path(File.dirname(__FILE__))
  pidfile = "#{folder_of_this_script}/dot_file_cleanup.pid"
  exit if File.exist?(pidfile)
  File.write(pidfile, $$)

  dot_files = Dir[ORIGIN]

  # remove dot files for files/folders that no longer exist
  dot_files.each do |dot_file_path|
    dot_file_name = dot_file_path.split("/")[-1]

    next if [".", ".."].include?(dot_file_name)

    file_name_without_dot = dot_file_name[1..-1]

    path_to_source_file_or_folder = dot_file_path.split("/").tap { |array| array[-1] = file_name_without_dot }.join("/")

    source_file_or_folder_exists = File.directory?(path_to_source_file_or_folder) || File.file?(path_to_source_file_or_folder)

    if !source_file_or_folder_exists
      timestamp = Time.now.strftime("%F %T")
      puts "[#{timestamp}] deleting: #{dot_file_path}"
      FileUtils.rm_f(dot_file_path)
    end
  end
rescue => error
  timestamp = Time.now.strftime("%F %T")
  puts "[#{timestamp}] Error encountered: #{error}"
ensure
  FileUtils.rm_f(pidfile)
end
