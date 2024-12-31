# frozen_string_literal: true

require "optparse"

module Ductwork
  class CLI
    class << self
      def start!(args)
        options = {}
        parser = build_option_parser(options)
        parser.parse!(args)
        configuration = Configuration.new(**options)

        Ductwork::WorkerLauncher.start!(configuration)
      end

      private

      def build_option_parser(options)
        OptionParser.new do |op|
          op.banner = "ductwork [options]"

          op.on("-c", "--config PATH", "path to YAML config file") do |arg|
            options[:path] = arg
          end

          op.on("-h", "--help", "Prints this help") do
            puts opts
            exit
          end

          op.on("-v", "--version", "Prints the version") do
            puts "Ductwork #{Ductwork::VERSION}"
            exit
          end
        end
      end
    end
  end
end
