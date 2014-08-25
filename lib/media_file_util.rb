require 'media_file_util/version'
require 'thor'
require 'taglib'
require 'fileutils'
require 'logger'

module MediaFileUtil

  class CLI < Thor

    desc 'reorganize', 'Reorganizes the files in the given input directory into the destination directory.  Files are grouped by sample_rate/artist/album'
    option :input_dir, :required=>true
    option :dest_dir, :required=>true
    option :input_file_ext, :required=>true
    option :log_file, :required=>true
    option :dry_run
    def reorganize
      logger = Logger.new(options[:log_file])
      titles = {}
      bad_tags = []
      bad_files = []
      count = 0
      files = Dir.glob("#{options[:input_dir]}/**/*.#{options[:input_file_ext]}")
      files.each do | file |
        count+=1
        print "\r#{count} of #{files.count} processed [#{bad_tags.count} bad tags, #{bad_files.count} unreadable files]"
        TagLib::FileRef.open(file) do | fileref |
          if fileref.nil?
            bad_files.push(file)
            next
          end
          tag = fileref.tag
          if tag.nil?
            bad_tags.push(file)
            next
          end
          key = "#{tag.artist}:#{tag.album}"
          titles[key] = {} unless titles[key]
          titles[key][fileref.audio_properties.sample_rate] = [] unless titles[key][fileref.audio_properties.sample_rate]
          titles[key][fileref.audio_properties.sample_rate].push(file)
        end
      end
      titles.keys.each do | key |
        titles[key].keys().each do | sample_rate |
          titles[key][sample_rate].each do | file |
            if titles[key].keys().count > 1
              TagLib::FileRef.open(file) do | fileref |
                tag = fileref.tag
                album = "#{tag.album} [#{sample_rate}]"
                logger.info("Retagging duplicate title #{key}: #{album}")
                if options[:dry_run].nil?
                  tag.album = album
                  fileref.save
                end
              end
            end
            dest_dir = destination_dir(file, sample_rate, options[:dest_dir])
            logger.info("mv #{file} #{dest_dir}")
            if options[:dry_run].nil?
              FileUtils.makedirs(dest_dir)
              FileUtils.mv(file, dest_dir)
            end
          end
        end
      end

      bad_files.each do | file |
        dest_dir = File.join(options[:dest_dir], 'exceptions', 'bad_files')
        logger.info("mv #{file} #{dest_dir}")
        if options[:dry_run].nil?
          FileUtils.makedirs(dest_dir)
          FileUtils.mv(file, dest_dir)
        end
      end

      bad_tags.each do | file |
        dest_dir = File.join(options[:dest_dir], 'exceptions', 'bad_tags')
        logger.info("mv #{file} #{dest_dir}")
        if options[:dry_run].nil?
          FileUtils.makedirs(dest_dir)
          FileUtils.mv(file, dest_dir)
        end
      end
    end

    desc 'filter-duplicates', 'Compares the files with the given extension in the first directory to those with the given extension in the second and filters the duplicates'
    option :dir_1, :required=>true
    option :file_ext_1, :required=>true
    option :dir_2, :required=>true
    option :file_ext_2, :required=>true
    option :duplicate_dir, :required=>true
    option :log_file, :required=>true
    option :dry_run, :required=>false
    def filter_duplicates
      logger = Logger.new(options[:log_file])
      files_1 = Dir.glob("#{options[:dir_1]}/**/*.#{options[:file_ext_1]}")
      files_2 = Dir.glob("#{options[:dir_2]}/**/*.#{options[:file_ext_2]}")
      files_1.each do | file_1 |
        file_2 = "#{File.basename(file_1, ".#{options[:file_ext_1]}")}.#{options[:file_ext_2]}"
        matches = files_2.select { |f| File.basename(f).eql?(file_2) }
        #matches = Dir.glob("#{options[:dir_2]}/**/#{file_2}")
        if matches.count > 0
          dup_dir = duplicate_dir(file_1, options[:duplicate_dir])
          logger.info("mv #{file_1} #{dup_dir}")
          if options[:dry_run].nil?
            FileUtils.makedirs(dup_dir)
            FileUtils.mv(file_1, dup_dir)
          end
        end
      end
    end

    desc 'prune-dirs', 'Prunes all the directories found beneath the specified directory that do not contain any files with the given extension'
    option :dir, :required=>true
    option :file_ext, :required=>true
    option :log_file, :required=>true
    option :dry_run
    def prune_dirs
      logger = Logger.new(options[:log_file])
      Dir.glob("#{options[:dir]}/**/*").select { |d| File.directory?(d) }.reverse_each { |d|
        Dir.entries(d).each do | entry |
          next if entry.include?("#{options[:file_ext]}")
          next unless File.file?(File.join(d,entry))
          logger.info("deleting #{File.join(d, entry)}")
          if options[:dry_run].nil?
            File.delete(File.join(d, entry))
          end
        end
      }
      Dir.glob("#{options[:dir]}/**/*").select { |d| File.directory? d }.select { |d| (Dir.entries(d) - %w[ . .. ]).empty? }.each { |d|
        logger.info("unlinking #{d}")
        if options[:dry_run].nil?
          Dir.unlink(d)
        end
      }
    end

    private
    def duplicate_dir(file, duplicate_dir)
      album_dir = File.dirname(file)
      artist_dir = File.dirname(album_dir)
      File.join(duplicate_dir, File.basename(artist_dir), File.basename(album_dir))
    end

    def destination_dir(file, sample_rate, dest_dir)
      album_dir = File.dirname(file)
      artist_dir = File.dirname(album_dir)
      File.join(dest_dir, sample_rate.to_s, File.basename(artist_dir), File.basename(album_dir))
    end
  end
end
