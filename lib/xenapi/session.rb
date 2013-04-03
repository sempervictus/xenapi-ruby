module XenAPI
  require "xmlrpc/client"
  require 'xenapi/dispatcher'

  class Session
    include XenAPI::VirtualMachine
    include XenAPI::Vdi
    include XenAPI::Vbd
    include XenAPI::Storage
    include XenAPI::Task
    include XenAPI::Network

    attr_reader :key

    def initialize(uri, &block)
      @uri, @block = uri, block
    end

    def login_with_password(username, password, timeout = 1200, ssl_verify = false)
      begin
        @client = XMLRPC::Client.new2(@uri, nil, timeout)
        if not ssl_verify
                @client.instance_variable_get(:@http).instance_variable_set(:@verify_mode, OpenSSL::SSL::VERIFY_NONE)
        end
        @session = @client.proxy("session")

        response = @session.login_with_password(username, password)
        raise XenAPI::ErrorFactory.create(*response['ErrorDescription']) unless response['Status'] == 'Success'

        @key = response["Value"]

        #Let's check if it is a working master. It's a small pog due to xen not working as we would like
        self.pool.get_all

        self
      rescue Exception => exc
        error = XenAPI::ErrorFactory.wrap(exc)
        if @block
          # returns a new session
          @block.call(error)
        else
          raise error
        end
      end
    end

    def close
      @session.logout(@key)
    end

    # Avoiding method missing to get lost with Rake Task
    # (considering Xen tasks as Rake task (???)
    def task(*args)
      method_missing("task", *args)
    end

    def method_missing(name, *args)
      raise XenAPI::UnauthenticatedClient.new unless @key

      proxy = @client.proxy(name.to_s, @key, *args)
      Dispatcher.new(proxy, &@block)
    end
  end
end
