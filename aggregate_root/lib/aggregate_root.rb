# frozen_string_literal: true

require_relative "aggregate_root/version"
require_relative "aggregate_root/configuration"
require_relative "aggregate_root/transform"
require_relative "aggregate_root/default_apply_strategy"
require_relative "aggregate_root/repository"
require_relative "aggregate_root/instrumented_repository"
require_relative "aggregate_root/instrumented_apply_strategy"
require_relative 'aggregate_root/snapshot_repository'

module AggregateRoot
  module OnDSL
    ANONYMOUS_CLASS = "#<Class:".freeze

    def on(*event_klasses, &block)
      event_klasses.each do |event_klass|
        name = event_klass.to_s
        raise(ArgumentError, "Anonymous class is missing name") if name.start_with? ANONYMOUS_CLASS

        handler_name = "on_#{name}"
        define_method(handler_name, &block)
        @on_methods ||= {}
        @on_methods[name] = handler_name
        private(handler_name)
      end
    end

    def on_methods
      @on_methods ||= {}
      (superclass.respond_to?(:on_methods) ? superclass.on_methods : {}).merge(@on_methods)
    end
  end

  module Constructor
    def new(*, **)
      super.tap do |instance|
        instance.instance_variable_set(:@version, -1)
        instance.instance_variable_set(:@unpublished_events, [])
      end
    end
  end

  module AggregateMethods
    def apply(*events)
      events.each do |event|
        apply_strategy.(self, event)
        @unpublished_events << event
      end
    end

    def version
      @version
    end

    def version=(value)
      @unpublished_events = []
      @version = value
    end

    def unpublished_events
      @unpublished_events.each
    end

    UNMARSHALED_VARIABLES = [:@version, :@unpublished_events]

    def marshal_dump
      instance_variables.reject{|m| UNMARSHALED_VARIABLES.include? m}.inject({}) do |vars, attr|
        vars[attr] = instance_variable_get(attr)
        vars
      end
    end

    def marshal_load(vars)
      vars.each do |attr, value|
        instance_variable_set(attr, value) unless UNMARSHALED_VARIABLES.include?(attr)
      end
    end
  end

  def self.with_default_apply_strategy
    Module.new do
      def self.included(host_class)
        host_class.extend OnDSL
        host_class.include AggregateRoot.with_strategy(-> { DefaultApplyStrategy.new })
      end
    end
  end

  def self.with_strategy(strategy)
    Module.new do
      def self.included(host_class)
        host_class.extend Constructor
        host_class.include AggregateMethods
      end

      define_method :apply_strategy do
        strategy.call
      end
    end
  end

  def self.included(host_class)
    host_class.include with_default_apply_strategy
  end
end
