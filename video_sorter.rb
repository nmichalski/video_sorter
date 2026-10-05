# DEFUNCT: superseded by video_sorter.sh, which is what cron runs. Kept for reference only;
# it lacks the newer fixes (e.g. year-based seasons like S1952E08).

require 'bundler/setup'
require 'set'
require 'fileutils'
require 'shellwords'
require 'rest-client'
# require 'net/ping'

$stdout.sync = true
$stderr.sync = true


# --- Parameters ---

ORIGIN="/Users/nick/Torrent/completed_downloads/*"
ORIGIN_BASE = File.dirname(ORIGIN).freeze
TV_DESTINATION="/Volumes/Media/TV\ Shows/"
MOVIE_DESTINATION="/Volumes/Media/New\ Movies/"
VIDEO_FILE_EXTENSIONS=[".mkv", ".mp4", ".avi", ".m4v"]
SOURCES = {
  movies_unwatched: 1,
  movies_watched: 2,
  tv_shows: 3,
  podcasts: 5,
  twitch: 6,
  youtube: 7,
  youtube_funny: 8,
  youtube_music: 9,
  wedding: 10,
  music: 11
}.freeze
PLEX_TOKEN=ENV.fetch("PLEX_TOKEN", "").freeze # mac mini


# --- Methods ---

def log(string)
  timestamp = Time.now.strftime("%F %T")
  puts "[#{timestamp}] #{string}"
end

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
  File.size(file_path) < (60 * 1024 * 1024) # 60MB
end

def escape_glob(s)
  s.gsub(/[\\\{\}\[\]\*\?]/) { |x| "\\"+x }
end

def shell_ls(dir)
  `ls -d #{Shellwords.escape(dir)}/*`.split("\n").reject(&:empty?)
rescue
  []
end

def find_or_create_show_folder(show_title)
  list_of_show_folders = shell_ls(TV_DESTINATION)

  existing_show_folder = list_of_show_folders.find { |show_folder| show_folder =~ /#{show_title}/i }
  if existing_show_folder.nil?
    existing_show_folder = "#{TV_DESTINATION}#{show_title}"
    system("mkdir", existing_show_folder)
  end

  existing_show_folder
end

def find_or_create_season_folder(show_folder, season)
  list_of_season_folders = shell_ls(show_folder)

  existing_season_folder = list_of_season_folders.find { |season_folder| season_folder =~ /\/season\s#{season}/i }
  if existing_season_folder.nil?
    existing_season_folder = "#{show_folder}/Season #{season}"
    system("mkdir", existing_season_folder)
  end

  existing_season_folder
end

def copy_file_from_origin_to_destination(origin, destination)
  relative_origin = origin.sub(ORIGIN_BASE + '/', '')
  log("┌─ COPYING ───────────────────────────────────────────────────")
  log("│  FROM: #{relative_origin}")
  log("│    TO: #{destination}")

  success = system("cp", origin, destination)
  # `notify-send --icon=/home/nick/Pictures/video_icon.jpg "Video Sorter" "Copied (#{origin.split('/')[-1]}) to (#{destination.split('/')[-1]})"`
  `osascript -e 'display notification "Copied (#{origin.split('/')[-1]}) to (#{destination.split('/')[-1]})" with title "Video Sorter"'` if success
  success
end

def label_as_processed(path)
  path_array = path.split("/")
  path_array[-1] = ".#{path_array[-1]}"
  dot_file_path = path_array.join("/")
  log("│  adding dot file: #{path_array[-1]}")

  FileUtils.touch(dot_file_path)
end

def plex_library_refresh_url(source_id)
  # plex_server_ip = Net::Ping::External.new("192.168.1.184").ping? ? "192.168.1.184" : "192.168.1.169"
  plex_server_ip = "192.168.1.184"
  "http://#{plex_server_ip}:32400/library/sections/#{source_id}/refresh?X-Plex-Token=#{PLEX_TOKEN}"
end

def refresh_library(library)
  return false if SOURCES[library].nil?

  refresh_url = plex_library_refresh_url(SOURCES[library])

  try_count = 2
  begin
    RestClient::Request.execute(method: :get, url: refresh_url, timeout: 5)
    log("└─ Plex: refreshed #{library} library")
  rescue RestClient::Exceptions::Timeout
    try_count -= 1
    if try_count > 0
      retry
    end
    log("└─ Plex: failed to refresh #{library} library")
  end

  true
end

# --- Script ---

begin
  delete_pidfile_on_exit = true

  folder_of_this_script = File.expand_path(File.dirname(__FILE__))
  pidfile = "#{folder_of_this_script}/video_sorter.pid"
  if File.exist?(pidfile)
    delete_pidfile_on_exit = false
    log("QUITTING: VideoSorter instance already running; exiting now!")
    exit(0)
  end
  File.write(pidfile, $$)

  # TODOs:
  # - add support for rar'd/zip'd files
  #   - deferred since qbittorrent now unrars after download completes
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
    log("Files to process (#{files_to_process.size}):")
    files_to_process.each do |f|
      log("    #{f.sub(ORIGIN_BASE + '/', '')}")
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
      if copy_file_from_origin_to_destination(file_to_process, final_destination)
        label_as_processed(file_or_folder)
        final_destination == MOVIE_DESTINATION ? refresh_library(:movies_unwatched) : refresh_library(:tv_shows)
      else
        log("└─ ERROR: copy failed, skipping label and Plex refresh")
      end
    end
  end
rescue => error
  log("Error encountered: #{error}")
ensure
  if delete_pidfile_on_exit
    log("QUITTING: deleting pid file")
    FileUtils.rm_f(pidfile)
  end
end
