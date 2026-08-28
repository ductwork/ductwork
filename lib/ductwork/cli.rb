# frozen_string_literal: true

require "optparse"

module Ductwork
  class CLI
    DEFAULT_COMMAND = "start"
    BACKTRACE_FRAME_LIMIT = 5

    def self.start!(args)
      new(args).start!
    end

    def initialize(args)
      @raw_args = args.dup
      @configuration_options = {}
      @health_check_options = {}
      @top_level_parser = OptionParser.new do |op|
        op.banner = "ductwork [options]"

        op.on("-c", "--config PATH", "path to YAML config file") do |arg|
          configuration_options[:path] = arg
        end

        op.on("-h", "--help", "Prints this help") do
          puts op
          puts "\nCommands:\n  start\n  health"
          exit
        end
      end
    end

    def start!
      parse!
      configure
      validate!
      execute
    end

    private

    attr_reader :raw_args, :configuration_options, :health_check_options,
                :top_level_parser, :command

    def parse!
      top_level_parser.order(raw_args)
      @command = raw_args.shift || DEFAULT_COMMAND

      if start_command?
        start_command_parser.parse!(raw_args)
      elsif health_check_command?
        health_command_parser.parse!(raw_args)
      else
        warn "Unknown command: #{command}"
        puts top_level_parser
        exit 1
      end
    end

    def start_command?
      command == "start"
    end

    def health_check_command?
      command == "health"
    end

    def configure
      configuration_options[:role] = ENV.fetch("DUCTWORK_ROLE", nil)
      Ductwork.configuration = Configuration.new(**configuration_options)
      Ductwork.logger = if Ductwork.configuration.logger_source == "rails"
                          Rails.logger
                        else
                          Ductwork::Configuration::DEFAULT_LOGGER
                        end
      Ductwork.logger.level = Ductwork.configuration.logger_level
    end

    def banner
      <<-BANNER
  \e[1;37m
   \e[0m════════════╗
                ║
                ║
                ║                             ╔═════\e[1;31m●\e[0m
                ║     \e[1;37mD U C T W O R K\e[0m         ║
            ╔═══║═╗                           ║
            ║   ║ ║             ╔═════════╗   ║
     \e[1;37m\e[0m══════╝   ╚═║═══════════════════════║═══╝
                  ╚═════════════╝         ╚═══════════\e[1;37m
  \e[0m
      BANNER
    end

    def validate!
      if start_command?
        Ductwork.validate!
      end
    rescue StandardError => e
      report_invalid_definitions(e)
      exit 1
    end

    def report_invalid_definitions(error)
      warn "ductwork failed to validate your step and pipeline definitions"
      warn ""
      warn "  #{error.class}: #{error.message}"

      definition_frames(error).each do |frame|
        warn "    #{frame}"
      end
    end

    def definition_frames(error)
      frames = error.backtrace.to_a

      return frames if Ductwork.logger.debug?

      application_frames = frames.grep(/\A#{Regexp.escape(Rails.root.to_s)}/)

      (application_frames.presence || frames).first(BACKTRACE_FRAME_LIMIT)
    end

    def execute
      if start_command?
        launch_processes
      elsif health_check_command?
        check_health
      end
    end

    def launch_processes
      puts banner

      Ductwork::Processes::Launcher.start_processes!
    end

    def check_health
      Ductwork::Processes::HealthCheck.run(**health_check_options)
    end

    def start_command_parser
      OptionParser.new do |op|
        op.banner = "ductwork start [options]"

        op.on("-c", "--config PATH") do |arg|
          configuration_options[:path] = arg
        end
      end
    end

    def health_command_parser
      OptionParser.new do |op|
        op.banner = "ductwork health [options]"

        op.on("-p", "--pid PID") do |arg|
          health_check_options[:pid] = arg.to_i
        end

        op.on("-V", "--verbose", "Prints all the health check data") do
          health_check_options[:verbose] = true
        end
      end
    end
  end
end
