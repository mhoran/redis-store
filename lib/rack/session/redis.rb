module Rack
  module Session
    class Redis < Abstract::ID
      attr_reader :mutex, :pool
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge :redis_server => "redis://127.0.0.1:6379/0"

      def initialize(app, options = {})
        super
        @mutex = Mutex.new
        options[:redis_server] ||= @default_options[:redis_server]
        @pool = ::Redis::Factory.create options
      end

      def generate_sid
        loop do
          sid = super
          break sid unless @pool.get(sid)
        end
      end

      def get_session(env, sid)
        with_lock(env, [ nil, {} ]) do
          unless sid and session = @pool.get(sid)
            env['rack.errors'].puts("Session '#{sid.inspect}' not found, initializing...") if $VERBOSE and not sid.nil?
            session = {}
            sid = generate_sid
            ret = @pool.set sid, session
            raise "Session collision on '#{sid.inspect}'" unless ret
          end
          [sid, session]
        end
      end

      def set_session(env, session_id, new_session, options)
        with_lock(env, false) do
          @pool.set session_id, new_session, options
          session_id
        end
      end

      def destroy_session(env, session_id, options)
        with_lock(env) do
          @pool.del(session_id)
          generate_sid unless options[:drop]
        end
      end

      private
        def with_lock(env, default=nil)
          @mutex.lock if env['rack.multithread']
          yield
        rescue Errno::ECONNREFUSED
          warn "#{self} is unable to find server."
          warn $!.inspect
          default
        ensure
          @mutex.unlock if @mutex.locked?
        end
    end
  end
end

