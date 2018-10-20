require 'set'
require 'fileutils'

# Parameters:

ORIGIN="/Users/nick/Downloads/Unsorted_Downloads/*"
TV_DESTINATION="/Volumes/Nicks/Media/TV\ Shows/"
MOVIE_DESTINATION="/Volumes/Nicks/Media/New\ Movies/"
VIDEO_FILE_EXTENSIONS=[".mkv", ".mp4", ".avi"]
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
COLOR_ID_BY_NAME={
  "Blank"  => "0",
  "Gray"   => "1",
  "Green"  => "2",
  "Purple" => "3",
  "Blue"   => "4",
  "Yellow" => "5",
  "Red"    => "6",
  "Orange" => "7",
}


def is_video_file?(file_path)
  VIDEO_FILE_EXTENSIONS.any? do |video_file_extension|
    file_path.end_with?(video_file_extension)
  end
end


# get directory listing
top_level_files_and_folders = Dir[ORIGIN]

# iterate through them
top_level_files_and_folders.each do |file_or_folder|
  color_id   = `mdls -name kMDItemFSLabel -raw "#{file_or_folder}"`
  color_name = COLOR_NAME_BY_ID[color_id]
  next unless color_name == "Blank"

  # TODO?: unrar if .rar (and make note of this for copy/move decision later)

  files_to_process = Set[]
  if File.file?(file_or_folder)
    file = file_or_folder

    if is_video_file?(file)
      files_to_process << file
    end
  else # is a folder
    folder = file_or_folder

    # find .mkv or .mp4 or .avi files
    VIDEO_FILE_EXTENSIONS.each do |video_file_extension|
      video_files = Dir["#{folder}/**/*#{video_file_extension}"]
      video_files.each do |video_file|
        files_to_process << video_file
      end
    end
  end

  # TODO?: capture top-folder name as string to use for renaming later

  files_to_process.each do |file_to_process|
    filename = file_to_process.split("/").last
    filename =~ /.*[S](\d\d)[E]\d\d\..*/i
    season = $1

    if !season.nil?  # TV show (i.e. has S##E##)
      # calculate title from part before S##E##
      filename =~ /(.*)\.[S]\d\d[E]\d\d\..*/i
      show_title = $1

      existing_shows = Dir["#{TV_DESTINATION}*"]

      # find existing show folder
      existing_show = existing_shows.find { |exist_show| exist_show =~ /#{show_title}/i }
      if existing_show.nil?
        existing_show = "#{TV_DESTINATION}#{show_title}"
        FileUtils.mkdir(existing_show)
      end

      existing_seasons = Dir["#{existing_show}/*"]

      # find existing season folder (i.e. final_destination)
      existing_season = existing_seasons.find { |exist_season| exist_season =~ /#{show_title}\/season\s#{season}/i }
      if existing_season.nil?
        existing_season = "#{existing_show}/Season #{season}"
        FileUtils.mkdir(existing_season)
      end

      final_destination = "#{existing_season}/"
    else # Movie
      final_destination = MOVIE_DESTINATION
    end

    # copy origin video file to destination folder
    # TODO?: (or move if extracted)
    puts "copying: #{file_to_process} --> #{final_destination}"
    FileUtils.cp(file_to_process, final_destination)

    # label original file/folder as Red
    puts "labeling Red: #{file_or_folder}"
    `./change_file_label.sh 2 "#{file_or_folder}"`
  end
end
