require 'set'
require 'fileutils'

$stdout.sync = true
$stderr.sync = true


# --- Parameters ---

ORIGIN="/media/Fast/uTorrent/completed_downloads/*"
TV_DESTINATION="/media/NAS/Media/TV\ Shows/"
MOVIE_DESTINATION="/media/NAS/Media/New\ Movies/"
VIDEO_FILE_EXTENSIONS=[".mkv", ".mp4", ".avi", ".m4v"]


# --- Methods ---

def was_processed?(path)
  path_array = path.split("/")
  path_array[-1] = ".#{path_array[-1]}"
  dot_file_path = path_array.join("/")

  File.file?(dot_file_path)
end

def is_video_file?(file_path)
  VIDEO_FILE_EXTENSIONS.any? do |video_file_extension|
    file_path.end_with?(video_file_extension)
  end
end

def is_sample?(file_path)
  File.size(file_path) < (100 * 1024 * 1024) # 100 MB
end

def escape_glob(s)
  s.gsub(/[\\\{\}\[\]\*\?]/) { |x| "\\"+x }
end

def find_or_create_show_folder(show_title)
  list_of_show_folders = Dir["#{TV_DESTINATION}*"]

  existing_show_folder = list_of_show_folders.find { |show_folder| show_folder =~ /#{show_title}/i }
  if existing_show_folder.nil?
    existing_show_folder = "#{TV_DESTINATION}#{show_title}"
    FileUtils.mkdir(existing_show_folder)
  end

  existing_show_folder
end

def find_or_create_season_folder(show_folder, season)
  list_of_season_folders  = Dir["#{show_folder}/*"]

  existing_season_folder = list_of_season_folders.find { |season_folder| season_folder =~ /\/season\s#{season}/i }
  if existing_season_folder.nil?
    existing_season_folder = "#{show_folder}/Season #{season}"
    FileUtils.mkdir(existing_season_folder)
  end

  existing_season_folder
end

def copy_file_from_origin_to_destination(origin, destination)
  timestamp = Time.now.strftime("%F %T")
  puts "[#{timestamp}] ----COPYING----"
  puts "[#{timestamp}]   FROM: #{origin}"
  puts "[#{timestamp}]   TO: #{destination}"

  FileUtils.cp(origin, destination)
  `notify-send --icon=/home/nick/Pictures/video_icon.jpg "Video Sorter" "Copied (#{origin.split('/')[-1]}) to (#{destination.split('/')[-1]})"`
end

def label_as_processed(path)
  timestamp = Time.now.strftime("%F %T")
  path_array = path.split("/")
  path_array[-1] = ".#{path_array[-1]}"
  dot_file_path = path_array.join("/")
  puts "[#{timestamp}] adding dot file: #{path_array[-1]}"

  FileUtils.touch(dot_file_path)
end


# --- Script ---

begin
  folder_of_this_script = File.expand_path(File.dirname(__FILE__))
  pidfile = "#{folder_of_this_script}/video_sorter.pid"
  exit if File.exist?(pidfile)
  File.write(pidfile, $$)

  # TODOs:
  # - add support for rar'd/zip'd files
  #   - deferred since qbittorrent now unrar's after download completes
  # - add support for copying subtitles (nested within folder for movie)

  top_level_files_and_folders = Dir[ORIGIN]

  top_level_files_and_folders.each do |file_or_folder|
    next if was_processed?(file_or_folder)

    files_to_process = Set[]
    if File.file?(file_or_folder)
      file = file_or_folder

      files_to_process << file if is_video_file?(file) && !is_sample?(file)
    else # is a folder
      folder = file_or_folder

      VIDEO_FILE_EXTENSIONS.each do |video_file_extension|
        video_files = Dir["#{escape_glob(folder)}/**/*#{video_file_extension}"]
        video_files.each do |video_file|
          files_to_process << video_file unless is_sample?(video_file)
        end
      end
    end

    next if files_to_process.empty?
    timestamp = Time.now.strftime("%F %T")
    puts "[#{timestamp}] files to process:"
    files_to_process.each do |f|
      puts "[#{timestamp}] - #{f}"
    end

    files_to_process.each do |file_to_process|
      filename = file_to_process.split("/").last
      filename =~ /.*[S](\d\d)\s*[E]\d\d.*/i
      season   = $1

      if !season.nil? # TV show
        filename   =~ /(.*)[\.\s][S]\d\d\s*[E]\d\d.*/i
        show_title = $1

        show_folder = find_or_create_show_folder(show_title)

        season_folder = find_or_create_season_folder(show_folder, season)
        final_destination = "#{season_folder}/"
      else # Movie
        final_destination = MOVIE_DESTINATION
      end

      # TODO: (or move if extracted)
      copy_file_from_origin_to_destination(file_to_process, final_destination)

      label_as_processed(file_or_folder)
    end
  end
rescue => error
  timestamp = Time.now.strftime("%F %T")
  puts "[#{timestamp}] Error encountered: #{error}"
ensure
  FileUtils.rm_f(pidfile)
end
