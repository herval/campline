require "mixlib/cli"

class CliConfig
  include Mixlib::CLI

  option :room,
    :short => "-r ROOM_NAME",
    :long => "--room ROOM_NAME",
    :description => "Use quotes if there are spaces on the room name"

  option :domain,
    :short => "-d DOMAIN_NAME",
    :long => "--domain DOMAIN_NAME",
    :description => "The subdomain of your campfire room - <domain>.campfirenow.com"


  option :username,
    :short => "-u USERNAME",
    :long => "--user USERNAME"

  option :api_key,
    :short => "-k API_KEY",
    :long => "--key API_KEY",
    :description => "Use this to log without a username/password prompt. You can skip the -u option if you use that"

  option :help,
    :short => "-h",
    :long => "--help",
    :on => :tail,
    :description => "This handy guide you're reading right now",
    :boolean => true,
    :show_options => true,
    :exit => 0

  option :version,
    :short => "-v",
    :long => "--version",
    :proc => Proc.new { puts "Campline version #{File.open('VERSION').read}" },
    :boolean => true,
    :exit => 0

  def load!
    self.parse_options
    unless self.config[:domain] && self.config[:room] && (self.config[:username] || self.config[:api_key])
      raise "Missing parameters - please run 'campline --help' for help" 
    end
  end

  def data
    config
  end
end