module Facy
  module Core
    def config
      @config ||= {}
    end

    def inits
      @inits ||= []
    end

    def init(&block)
      inits << block
    end

    def _init
      load_config
      inits.each { |block| class_eval(&block) }
      user_id_cache_load
    end

    def load_config
      config.reverse_update(default_config)
      save_session_file(get_tokens) unless load_session_file
    end

    def session_file
      File.expand_path(config[:session_file_name], config[:session_file_folder])
    end

    def save_session_file(auth_hash)
      File.open(session_file, "w") { |f| f.write auth_hash.to_yaml } 
    end

    def load_session_file
      session = YAML.load_file(session_file)
      config[:session_key] = session["session_key"]
      config[:uid] = session["uid"]
      return true
    rescue Errno::ENOENT #file not found
      return false
    end

    def default_config
      config = YAML.load_file(File.expand_path("config.yml", "."))
      {
        session_file_folder: "/tmp",
        session_file_name: "session.yml",
        user_id_cache_dump_folder: "/tmp",
        user_id_cache_dump_file: "facy_user_id_cache.dump",
        app_id: config['app_id'],
        app_token: config['app_token'],
        prompt: "facy> ",
        stream_fetch_interval: 2,
        output_interval: 3,
        debug: true,
        debug_level: 1
      }
    end

    def start(options={})
      _init      

      EM.run do
        Thread.start do
          while buf = Readline.readline(config[:prompt], true) 
            print "->", buf, "\n"
            #unless Readline::HISTORY.count == 1
            #  Readline::HISTORY.pop if buf.empty?
            #end
          end
        end

        Thread.start do
          EM.add_periodic_timer(config[:stream_fetch_interval]) do
            facebook_stream_fetch
          end
        end
        
        Thread.start do
          EM.add_periodic_timer(config[:output_interval]) do
            output
          end
        end

        Signal.trap("INT")  { stop_process }
        Signal.trap("TERM") { stop_process }
      end
    end

    def mutex
      @mutex ||= Mutex.new
    end

    def sync(&block)
      mutex.synchronize do
        block.call
      end
    end

    def stop_process
      Thread.new {
        user_id_cache_dump 
        EventMachine.stop 
      }.join
    end
  end

  extend Core
end
