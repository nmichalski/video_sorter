require 'set'
require 'fileutils'

# mdls uses a different mapping for reading the color
COLOR_NAME_BY_ID={
  "0" => "Blank",
  "1" => "Gray",
  "2" => "Green",
  "3" => "Purple",
  "4" => "Blue",
  "5" => "Yellow",
  "6" => "Red",
  "7" => "Orange",
}
# The osascript uses a different mapping for setting the color
COLOR_ID_BY_NAME={
  "Blank"  => "0",
  "Orange" => "1",
  "Red"    => "2",
  "Yellow" => "3",
  "Blue"   => "4",
  "Purple" => "5",
  "Green"  => "6",
  "Gray"   => "7",
}


# --- Parameters ---

ORIGIN="/Users/nick/Downloads/Unsorted_Downloads/*"
TV_DESTINATION="/Volumes/Nicks/Media/TV\ Shows/"
MOVIE_DESTINATION="/Volumes/Nicks/Media/New\ Movies/"
VIDEO_FILE_EXTENSIONS=[".mkv", ".mp4", ".avi"]


# --- Methods ---

def was_processed?(path)
  color_id   = `mdls -name kMDItemFSLabel -raw "#{path}"`
  color_name = COLOR_NAME_BY_ID[color_id]
  color_name != "Blank"
end

def is_video_file?(file_path)
  VIDEO_FILE_EXTENSIONS.any? do |video_file_extension|
    file_path.end_with?(video_file_extension)
  end
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
  puts "[#{timestamp}] copying: #{origin} --> #{destination}"
  FileUtils.cp(origin, destination)
end

def label_as_processed(path)
  timestamp = Time.now.strftime("%F %T")
  puts "[#{timestamp}] labeling Red: #{path}"
  `./change_file_label.sh #{COLOR_ID_BY_NAME["Red"]} "#{path}"`
end


# --- Script ---

top_level_files_and_folders = Dir[ORIGIN]

top_level_files_and_folders.each do |file_or_folder|
  next if was_processed?(file_or_folder)

  # TODO: unrar if .rar (and make note of this for copy/move decision later)

  files_to_process = Set[]
  if File.file?(file_or_folder)
    file = file_or_folder

    files_to_process << file if is_video_file?(file)
  else # is a folder
    folder = file_or_folder

    VIDEO_FILE_EXTENSIONS.each do |video_file_extension|
      video_files = Dir["#{folder}/**/*#{video_file_extension}"]
      video_files.each do |video_file|
        files_to_process << video_file
      end
    end
  end

  files_to_process.each do |file_to_process|
    filename = file_to_process.split("/").last
    filename =~ /.*[S](\d\d)[E]\d\d\..*/i
    season   = $1

    if !season.nil? # TV show
      filename   =~ /(.*)\.[S]\d\d[E]\d\d\..*/i
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
