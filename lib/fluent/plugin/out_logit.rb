# coding: utf-8

require 'fluent/output'

module Fluent
  class LogitOutput < BufferedOutput
    Fluent::Plugin.register_output('logit', self)

    def initialize
      super
      require 'socket'
      require 'timeout'
      require 'fileutils'
    end

    config_param :stack_id, :string, :default => ""
    config_param :port, :string, :default => 0

    config_param :send_timeout, :time, :default => 60
    config_param :connect_timeout, :time, :default => 5
    config_param :output_type, :string, :default => "json"
    config_param :output_append_newline, :bool, :default => true

    def configure(conf)
      super
      if /[\w]{8}(-[\w]{4}){3}-[\w]{12}/.match(@stack_id) == nil
        raise "stack_id is required and must be a GUID. See the source wizard"
      end
      if @port == 0
        raise "port is required. See the source wizard."
      end
    end

    def start
      super
    end

    def shutdown
      super
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      return if chunk.empty?

      send_data(chunk)
    end

    private
    def send_data(chunk)
      sock = connect()
      begin
        opt = [1, @send_timeout.to_i].pack('I!I!')  # { int l_onoff; int l_linger; }
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, opt)

        opt = [@send_timeout.to_i, 0].pack('L!L!')  # struct timeval
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, opt)

        chunk.msgpack_each do |tag, time, record|
          next unless record.is_a? Hash
          sock.write(prepare_data_to_send(tag, time, record))
        end
      ensure
        sock.close
      end
    end

    def prepare_data_to_send(tag, time, record)
      if @output_type == "json"
        new_line_suf = ""
        if @output_append_newline
          new_line_suf = "\n"
        end
        return "#{record.to_json}#{new_line_suf}"
      else
        return [tag, time, record].to_msgpack
      end
    end

    def connect()
      Timeout.timeout(@connect_timeout) do
        socket = TCPSocket.open("#{resolved_host()}", @port)
        ssl_context = OpenSSL::SSL::SSLContext.new()
        # TODO implement mutual tls
        #ssl_context.cert = OpenSSL::X509::Certificate.new(File.open("certificate.crt"))
        #ssl_context.key = OpenSSL::PKey::RSA.new(File.open("certificate.key"))
        ssl_context.options |= OpenSSL::SSL::OP_NO_SSLv2
        ssl_context.options |= OpenSSL::SSL::OP_NO_SSLv3
        ssl_context.options |= OpenSSL::SSL::OP_NO_COMPRESSION
        ssl_context.ciphers = "TLSv1.2:!aNULL:!eNULL"
        ssl_context.ssl_version = :TLSv1_2
        ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
        ssl_socket.sync_close = true
        ssl_socket.connect
        return ssl_socket
      end
    end

    def resolved_host()
      @sockaddr = Socket.pack_sockaddr_in(@port, "#{@stack_id}-ls.logit.io")
      _, rhost = Socket.unpack_sockaddr_in(@sockaddr)
      return rhost
    end
  end
end
