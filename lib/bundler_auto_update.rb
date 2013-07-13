require "bundler_auto_update/version"

module Bundler
  module AutoUpdate
    class CLI
      attr_reader :gem, :gemfile

      def initialize(argv)
        @argv = argv
      end

      def run!
        unless @argv.first == '-noupdate'
          gemfile.remove_all_versions
          result = CommandRunner.system("bundle update")
          return Logger.log_error("Aborting due to error") unless result
        end
        gemfile.set_versions(gemfile_lock.version_map)
        CommandRunner.system("bundle install")
      end

       def gemfile
        @gemfile ||= Gemfile.new
       end

       def gemfile_lock
        @gemfile_lock ||= GemfileLock.new
       end
    end

    class GemfileLock
      attr_reader :version_map

      def initialize
        @version_map = {}
        load_versions
      end

      def load_versions
        @version_map = {}
        content = File.read('Gemfile.lock')
        content.dup.each_line do |l|
          match = l.match(/^\s\s\s\s(.*)\s+\((.*)\)/)
          if match
            @version_map[match[1]] = match[2]
          end
        end
      end
    end

    class Gemfile
      attr_reader :content

      # Regex that matches a gem definition line.
      #
      # @return [RegEx] matching [_, name, _, version, _, options]
      def gem_line_regex(gem_name = '(.*)')
        /^\s*gem\s*['"]#{gem_name}['"]\s*(,\s*['"](.+)['"])?\s*(,\s*(.*))?\n?$/
      end

      # @note This funky code parser could be replaced by a funky dsl re-implementation
      def gems
        gems = []

        content.dup.each_line do |l|
          if match = l.match(gem_line_regex)
            _, name, _, version, _, options = match.to_a
            gems << Dependency.new(name, version, options)
          end
        end

        gems
      end

      # Update Gemfile and run 'bundle update'
      def update_gem(gem)
        update_content(gem) and write and run_bundle_update(gem)
      end

      # @return [String] Gemfile content
      def content
        @content ||= read
      end

      # Reload Gemfile content
      def reload!
        @content = read
      end

      def set_versions(version_map)
        new_content = ""
        content.dup.each_line do |l|
          if match = l.match(gem_line_regex)
            Logger.log "atempting to update on line: #{l}"
            _, name, _, version, _, options = match.to_a
            if version_map[name]
              Logger.log "updating #{name} to #{version_map[name]}"
              l.gsub!("\n","")
              l += ", \"~> #{version_map[name]}\"\n"
            else
              Logger.log_error "gem #{name} not found in Gemfile.lock"
            end
          end
          new_content += l
        end
        @content = new_content
        write
      end

      def remove_all_versions
        new_content = ""
        content.each_line do |l|
          if l.match(/^(\s+)?gem/) && !l.match(/\,.*(github).*/)
            Logger.log "removing version from line: #{l}"
            l.gsub!(/\,.*/, "")
          else
            Logger.log_error "ignoring line: #{l}"
          end
          new_content += l
        end
        @content = new_content
        write
      end

      private

      def update_content(gem)
        new_content = ""
        content.each_line do |l|
          if l =~ gem_line_regex(gem.name)
            l.gsub!(/\d+\.\d+\.\d+/, gem.version)
          end

          new_content += l
        end

        @content = new_content
      end

      # @return [String] Gemfile content read from filesystem
      def read
        File.read('Gemfile')
      end

      # Write content to Gemfile
      def write
        File.open('Gemfile', 'w') do |f|
          f.write(content)
        end
      end
    end # class Gemfile

    class Logger
      def self.log(msg, prefix = "")
        puts prefix + msg
      end

      # Log with indentation:
      # "  - Log message"
      #
      def self.log_indent(msg)
        log(msg, "  - ")
      end

      def self.log_error(msg)
        log(msg, "  BAUError ")
      end


      # Log command:
      # "  > bundle update"
      #
      def self.log_cmd(msg)
        log(msg, "    > ")
      end
    end

    class Dependency
      attr_reader :name, :options, :major, :minor, :patch
      attr_accessor :version

      def initialize(name, version = nil, options = nil)
        @name, @version, @options = name, version, options

        @major, @minor, @patch = version.split('.') if version
      end

      # Return last version scoped at :version_type:.
      #
      # Example: last_version(:patch), returns the last patch version 
      # for the current major/minor version
      #
      # @return [String] last version. Ex: '1.2.3'
      #
      def last_version(version_type)
        case version_type
        when :patch
          available_versions.select { |v| v =~ /^#{major}\.#{minor}\D/ }.first
        when :minor
          available_versions.select { |v| v =~ /^#{major}\./ }.first
        when :major
          available_versions.first
        else
          raise "Invalid version_type: #{version_type}"
        end
      end

      # Return an ordered array of all available versions.
      #
      # @return [Array] of [String].
      def available_versions
        the_gem_line = gem_remote_list_output.scan(/^#{name}\s.*$/).first
        the_gem_line.scan /\d+\.\d+\.\d+/
      end

      private

      def gem_remote_list_output
        CommandRunner.run "gem list #{name} -r -a"
      end
    end # class Dependency

    class CommandRunner

      # Output the command about to run, and run it using system.
      #
      # @return true on success, false on failure
      def self.system(cmd)
        Logger.log_cmd cmd

        Kernel.system cmd
      end

      # Run a system command and return its output.
      def self.run(cmd)
        `#{cmd}`
      end
    end
  end # module AutoUpdate
end # module Bundler
