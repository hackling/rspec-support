module RSpec
  module Support
    # @api private
    #
    # Defines a helper method that is optimized to require files from the
    # named lib. The passed block MUST be `{ |f| require_relative f }`
    # because for `require_relative` to work properly from within the named
    # lib the line of code must be IN that lib.
    #
    # `require_relative` is preferred when available because it is always O(1),
    # regardless of the number of dirs in $LOAD_PATH. `require`, on the other
    # hand, does a linear O(N) search over the dirs in the $LOAD_PATH until
    # it can resolve the file relative to one of the dirs.
    def self.define_optimized_require_for_rspec(lib, &require_relative)
      name = "require_rspec_#{lib}"

      if Kernel.respond_to?(:require_relative)
        (class << self; self; end).__send__(:define_method, name) do |f|
          require_relative.call("#{lib}/#{f}")
        end
      else
        (class << self; self; end).__send__(:define_method, name) do |f|
          require "rspec/#{lib}/#{f}"
        end
      end
    end

    define_optimized_require_for_rspec(:support) { |f| require_relative(f) }
    require_rspec_support "version"
    require_rspec_support "ruby_features"

    # @api private
    KERNEL_METHOD_METHOD = ::Kernel.instance_method(:method)

    # @api private
    #
    # Used internally to get a method handle for a particular object
    # and method name.
    #
    # Includes handling for a few special cases:
    #
    #   - Objects that redefine #method (e.g. an HTTPRequest struct)
    #   - BasicObject subclasses that mixin a Kernel dup (e.g. SimpleDelegator)
    #   - Objects that undefine method and delegate everything to another
    #     object (e.g. Mongoid association objects)
    if RubyFeatures.supports_rebinding_module_methods?
      def self.method_handle_for(object, method_name)
        KERNEL_METHOD_METHOD.bind(object).call(method_name)
      rescue NameError => original
        begin
          handle = object.method(method_name)
          raise original unless handle.is_a? Method
          handle
        rescue Exception
          raise original
        end
      end
    else
      def self.method_handle_for(object, method_name)
        if ::Kernel === object
          KERNEL_METHOD_METHOD.bind(object).call(method_name)
        else
          object.method(method_name)
        end
      rescue NameError => original
        begin
          handle = object.method(method_name)
          raise original unless handle.is_a? Method
          handle
        rescue Exception
          raise original
        end
      end
    end

    # A single thread local variable so we don't excessively pollute that namespace.
    def self.thread_local_data
      Thread.current[:__rspec] ||= {}
    end

    def self.failure_notifier=(callable)
      thread_local_data[:failure_notifier] = callable
    end

    # @private
    DEFAULT_FAILURE_NOTIFIER = lambda { |failure, _opts| raise failure }

    def self.failure_notifier
      thread_local_data[:failure_notifier] || DEFAULT_FAILURE_NOTIFIER
    end

    def self.notify_failure(failure, options={})
      arity = if failure_notifier.respond_to?(:arity)
                failure_notifier.arity
              else
                failure_notifier.method(:call).arity
              end

      # TODO: remove these first two branches once the other repos have been
      # updated to deal with the new two-arg interface.
      if arity == 1
        failure_notifier.call(failure)
      elsif Method === failure_notifier && failure_notifier.name.to_sym == :raise
        # `raise` accepts 2 arguments (exception class and message) but we
        # don't want it to treat the opts hash as the message.
        failure_notifier.call(failure)
      else
        failure_notifier.call(failure, options)
      end
    end

    def self.with_failure_notifier(callable)
      orig_notifier = failure_notifier
      self.failure_notifier = callable
      yield
    ensure
      self.failure_notifier = orig_notifier
    end

    # The Differ is only needed when a a spec fails with a diffable failure.
    # In the more common case of all specs passing or the only failures being
    # non-diffable, we can avoid the extra cost of loading the differ, diff-lcs,
    # pp, etc by avoiding an unnecessary require. Instead, autoload will take
    # care of loading the differ on first use.
    autoload :Differ, "rspec/support/differ"
  end
end
