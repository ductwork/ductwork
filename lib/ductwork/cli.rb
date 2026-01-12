# frozen_string_literal: true

require "optparse"

module Ductwork
  class CLI
    def self.start!(args)
      new(args).start!
    end

    def initialize(args)
      @args = args
      @options = {}
    end

    def start!
      option_parser.parse!(args)
      auto_configure
      puts banner
      launch_processes
    end

    private

    attr_reader :args, :options

    def option_parser
      OptionParser.new do |op|
        op.banner = "ductwork [options]"

        op.on("-c", "--config PATH", "path to YAML config file") do |arg|
          options[:path] = arg
        end

        op.on("-h", "--help", "Prints this help") do
          puts op
          exit
        end

        op.on("-v", "--version", "Prints the version") do
          puts "Ductwork #{Ductwork::VERSION}"
          exit
        end
      end
    end

    def auto_configure
      options[:role] = ENV.fetch("DUCTWORK_ROLE", nil)
      Ductwork.configuration = Configuration.new(**options)
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
  ██████╗ ██╗   ██╗ ██████╗████████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
  ██╔══██╗██║   ██║██╔════╝╚══██╔══╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
  ██║  ██║██║   ██║██║        ██║   ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
  ██║  ██║██║   ██║██║        ██║   ██║███╗██║██║   ██║██╔══██╗██╔═██╗
  ██████╔╝╚██████╔╝╚██████╗   ██║   ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
  ╚═════╝  ╚═════╝  ╚═════╝   ╚═╝    ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
  ▒▒▓  ▒ ░▒▓▒ ▒ ▒ ░ ░▒ ▒  ░  ▒ ░░   ░ ▓░▒ ▒  ░ ▒░▒░▒░ ░ ▒▓ ░▒▓░▒ ▒▒ ▓▒
   ░ ▒  ▒ ░░▒░ ░ ░   ░  ▒       ░      ▒ ░ ░    ░ ▒ ▒░   ░▒ ░ ▒░░ ░▒ ▒░
    ░ ░  ░  ░░░ ░ ░ ░          ░        ░   ░  ░ ░ ░ ▒    ░░   ░ ░ ░░ ░
       ░       ░     ░ ░                    ░        ░ ░     ░     ░  ░
     ░               ░
  \e[0m
      BANNER
    end

    def launch_processes
      Ductwork::Processes::Launcher.start_processes!
    end
  end
end
