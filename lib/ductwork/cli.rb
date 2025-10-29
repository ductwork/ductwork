# frozen_string_literal: true

require "optparse"

module Ductwork
  class CLI
    class << self
      def start!(args)
        options = parse_options(args)
        Ductwork.configuration = Configuration.new(**options)
        Ductwork.configuration.logger = Ductwork::Configuration::DEFAULT_LOGGER

        Ductwork::SupervisorRunner.start!
      end

      private

      def parse_options(args)
        options = {}

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
        end.parse!(args)

        options
      end
    end
  end
end
