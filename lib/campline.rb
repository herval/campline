# encoding: utf-8

require 'time'
require 'thread'
require 'tinder'
require 'io/wait'
require 'yaml'
require 'cli-colorize'

unless Gem::Specification::find_all_by_name('ruby-growl').empty?
  require 'ruby-growl'
  $growl = Growl.new "localhost", "ruby-growl", "UDP"
else
  print "Install the ruby-growl to enable Growl notification support\r\n"
end

module Campline
  
  GO_BACK = "\r\e[0K" # return to beginning of line and use the ANSI clear command "\e" or "\003"

  class Client
    include Tinder
    include CLIColorize

    def initialize(options)
      @config = options
      @me = nil
      @room_users = []
      @output_buffer = ""
      @input_buffer = Queue.new
    end

    def print_message(msg, flush = true, ignore_current_user = true)
      return if msg[:user].nil?

      return if (msg[:user] && msg[:user][:id] == @me[:id] && ignore_current_user)
      @input_buffer << case msg[:type]
        when "KickMessage","LeaveMessage"
          white("#{msg[:user][:name]} left the room")
        when "EnterMessage"
          white("#{msg[:user][:name]} joined the room")
        when "SoundMessage"
          "#{green(msg[:user][:name])} #{white('played some sound. Sound is for dummies.')}" 
        when "PasteMessage", "TextMessage", "TweetMessage"
          "#{green(msg[:user][:name])}: #{msg[:body]}"
        else
          msg
      end
      flush_input_buffer! if flush
    end

    def print_inline(msg)
      print "#{GO_BACK}#{msg}\r\n"
      show_prompt
    end

    def commands
      {
        "/help" => lambda { print_inline(white("Available commands: /users (list users on the room), /exit (quit!), /log (show latest messages)")) },
        "/exit" => lambda { exit! },
        "/users" => lambda { list_users },
        "/log" => lambda { print_transcript }
      }
    end

    def list_users
      update_user_list
      print_inline(white("In the room right now: #{@room_users.collect(&:name).join(', ')}"))
    end

    def print_transcript
      update_user_list
      transcript = @campfire_room.transcript(Date.today) || []
      
      # load user names, as these don't come on the transcript...
      talking_users = {}
      @room_users.each do |user|
        talking_users[user.id] = user
      end

      transcript.reverse[0..15].reverse.each do |m| 
        print_message(m.merge(:user => talking_users[m[:user_id]], :type => "TextMessage", :body => m[:message]), false, false)
      end
      flush_input_buffer!
      print_inline(white("Last message received at #{transcript[-1][:timestamp]}"))
    end

    def update_user_list
      @room_users = @campfire_room.users
    end

    def backspace!
      @output_buffer.chop!
      print "#{GO_BACK}> #{@output_buffer}"
    end

    def show_prompt
      print "#{GO_BACK}> #{@output_buffer}"
      $stdout.flush
    end

    def exit!
      @campfire_room.leave
      print "\r\nGoodbye..."
      exit    
    end

    def flush_input_buffer!
      unless @input_buffer.empty? # read from server
        notify_growl!
        print GO_BACK
        print "#{@input_buffer.shift}\r\n" until @input_buffer.empty?
        show_prompt
      end      
    end

    def notify_growl!
      $growl.notify("ruby-growl", "ruby-growl", "Greetings!") if $growl
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
      buffer = @output_buffer
      @output_buffer = ""
      if commands[buffer]
        commands[buffer].call
      else
        return if buffer.blank?
        Thread.new do
          begin
            print_message({ :user => @me, :type => "TextMessage", :body => buffer }, true, false)
            @campfire_room.speak(buffer)
          rescue => e
            print_inline(white("A message could not be sent: #{buffer}"))
          end
        end
      end        
    end

    def start_message_listener!(room)
      Thread.new do
        while true
          begin
            room.listen do |msg|
              print_message(msg)
            end
          rescue => e
            # ignore errors!
            #  puts e
          end
        end
      end
    end

    def start_typing_agent!
      Thread.new do
        while character = $stdin.getc
          case character
            when ?\C-c
              exit!
            when ?\r, ?\n
              send_line!
              show_prompt
            when ?\e # arrow keys & fn keys
              # do nothing
            when ?\u007F, ?\b
              backspace!
            else
              @output_buffer << character
              print character.chr
              $stdout.flush
          end
        end
      end
    end

    def listen!
      print "Logging in...\r\n"
      begin
        params = { :ssl => true }
        if @config[:api_key]
          params[:token] = @config[:api_key]
        else
          params.merge!(:username => @config[:username], :password => @config[:password])
        end
        campfire = Campfire.new(@config[:domain], params)
      rescue Tinder::AuthenticationFailed
        raise "There was an authentication error - check your login information\r\n"
      end
      @me = campfire.me

      print "Joining #{@config[:room]}...\r\n"
      @campfire_room = campfire.find_room_by_name(@config[:room])
      raise "Can't find room named #{@config[:room]}!\r\n" if @campfire_room.nil?
      
      @campfire_room.join
      update_user_list
      
      print_transcript
      print_inline("You're up! For a list of available commands, type #{highlight('/help')}\r\n")

      start_message_listener!(@campfire_room)
      start_typing_agent!.join
    end
  end

end