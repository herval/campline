require 'rubygems'
require 'thread'
require 'tinder'
require 'io/wait'
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
      @output_buffer = ""
      @input_buffer = Queue.new
    end

    def print_message(msg)
      return if (msg[:user] && msg[:user][:id] == @user_id)
      case msg[:type]
        when "SoundMessage" then
          @input_buffer << "#{green(msg[:user][:name])} played some annoying sound" 
        when "PasteMessage" then
          @input_buffer << "#{green(msg[:user][:name])}: #{msg[:body]}"
        when "TextMessage" then
          @input_buffer << "#{green(msg[:user][:name])}: #{msg[:body]}"
      end
    end

    def commands
      {
        "/help" => lambda { print "\r\nAvailable commands: /users (list users on the room), /exit (quit!)"},
        "/exit" => lambda { @campfire_room.leave; exit; },
        "/users" => lambda { list_users }
      }
    end

    def list_users
      print white("\r\nIn the room right now: #{@room_users.join(', ')}")
    end

    def update_user_list
      new_list = @campfire_room.users.collect(&:name)
      @room_users = new_list if @room_users.empty?

      new_guys = new_list - @room_users
      new_guys.each { |n| @input_buffer << "#{n} joined the room" }

      dead_guys = @room_users - new_list
      dead_guys.each { |n| @input_buffer << "#{n} left the room" }
      @room_users = new_list
    end

    def backspace!
      @output_buffer.chop!
      go_back = "\r\e[0K" # return to beginning of line and use the ANSI clear command "\e" or "\003"
      print "#{go_back}> #{@output_buffer}"
    end

    def show_prompt
      puts "\r\n"
      print "> #{@output_buffer}"
      $stdout.flush
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

    def send_line!
      if commands[@output_buffer]
        commands[@output_buffer].call
      else
        @campfire_room.speak @output_buffer
      end
      @output_buffer = ""
    end

    def listen!
      puts "Logging in...\r\n"
      begin
        campfire = Campfire.new @domain, :username => @username, :password => @password, :ssl => true
      rescue Tinder::AuthenticationFailed
        raise "There was an authentication error - check your username and password\r\n"
      end
      @user_id = campfire.me.id

      puts "Joining #{@room}...\r\n"
      @campfire_room = campfire.find_room_by_name @room
      raise "Can't find room named #{@room}!\r\n" if @campfire_room.nil?
      
      @campfire_room.join
      update_user_list
      
      puts "You're up! For a list of available commands, type #{highlight('/help')}\r\n"
      show_prompt

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
        while true #msg = Readline.readline('> ', true)
          if $stdin.ready?
            character = $stdin.getc
            case character
              when ?\C-c
                break
              when ?\r, ?\n
                send_line!
                show_prompt
              when ?\u007F, ?\b
                backspace!
              else
                @output_buffer << character
                print character.chr
                $stdout.flush
            end
          end

          unless @input_buffer.empty?   # read from server
            puts "\r\n"
            puts "#{@input_buffer.shift}\r\n" until @input_buffer.empty?
            show_prompt
          end

        end
      end.join
    end
  end

end