require 'rubygems'
require 'tinder'
require 'readline'
require 'yaml'
require 'cli-colorize'

module Campline
  
  class Client
    include Tinder
    include CLIColorize

    def initialize(domain, room, username, password)
      @domain = domain
      @room = room
      @username = username
      @password = password
      @user_id = nil
      @room_users = []
    end

    def print_message(msg)
      return if msg[:user] && msg[:user][:id] == @user_id
      case msg[:type]
        when "SoundMessage" then
          puts "#{green(msg[:user][:name])} played some annoying sound" 
        when "PasteMessage" then
          puts "#{green(msg[:user][:name])}: #{msg[:body]}"
        when "TextMessage" then
          puts "#{green(msg[:user][:name])}: #{msg[:body]}"
      end
    end

    def commands
      {
        "/help" => lambda { puts "Available commands: /users (list users on the room), /exit (quit!)"},
        "/exit" => lambda { @campfire_room.leave; exit; },
        "/users" => lambda { list_users }
      }
    end

    def list_users
      puts white("In the room right now: #{@room_users.join(', ')}")
    end

    def update_user_list
      new_list = @campfire_room.users.collect(&:name)
      @room_users = new_list if @room_users.empty?

      new_guys = new_list - @room_users
      new_guys.each { |n| puts "#{n} joined the room" }

      dead_guys = @room_users - new_list
      dead_guys.each { |n| puts "#{n} left the room" }
      @room_users = new_list
    end

    def blue(str)
      colorize(str, :foreground => :blue)
    end

    def green(str)
      colorize(str, :foreground => :green)
    end

    def white(str)
      colorize(str, :foreground => :white)
    end

    def highlight(str)
      colorize(str, :background => :red)
    end

    def listen!
      puts "Logging in..."
      begin
        campfire = Campfire.new @domain, :username => @username, :password => @password, :ssl => true
      rescue Tinder::AuthenticationFailed
        raise "There was an authentication error - check your username and password"
      end
      @user_id = campfire.me.id

      puts "Joining #{@room}..."
      @campfire_room = campfire.find_room_by_name @room
      raise "Can't find room named #{@room}!" if @campfire_room.nil?
      
      @campfire_room.join
      update_user_list
      
      puts "You're up! For a list of available commands, type #{highlight('/help')}"

      Thread.new(@campfire_room) do |listener|
        while true
          listener.listen do |msg|
            print_message msg
          end
        end
      end

      Thread.new do
        while true
          sleep(10)
          update_user_list
        end
      end

      Thread.new do
        while msg = Readline.readline('> ', true)
          next if msg.strip.blank?
          if commands[msg]
            commands[msg].call
          else
            @campfire_room.speak msg
          end 
        end
      end.join
    end
  end

end