# frozen_string_literal: true

module RubyEventStore
  module Mappers
    module Transformation
      class PreserveTypes
        def initialize(type_resolver: ->(type) { type.to_s })
          @registry = Registry.new(type_resolver)
        end

        class NullType
          PASS_THROUGH = ->(v) { v }
          private_constant :PASS_THROUGH

          def serializer
            PASS_THROUGH
          end

          def deserializer
            PASS_THROUGH
          end

          def stored_type
            DEFAULT_STORE_TYPE
          end
        end
        private_constant :NullType

        class RegisteredType
          def initialize(serializer, deserializer, stored_type)
            @serializer = serializer
            @deserializer = deserializer
            @stored_type = stored_type
          end

          attr_reader :serializer, :deserializer, :stored_type
        end
        private_constant :RegisteredType

        class Registry
          def initialize(resolver)
            @types = {}
            @resolver = resolver
          end


          NULL_TYPE = NullType.new
          private_constant :NULL_TYPE

          def add(type, serializer, deserializer, stored_type)
            types[resolver[type]] = RegisteredType.new(serializer, deserializer, stored_type)
          end

          def of(type)
            types.fetch(resolver[type]) { NULL_TYPE }
          end

          private
          attr_reader :resolver, :types
        end
        private_constant :Registry

        def register(type, serializer:, deserializer:, stored_type: DEFAULT_STORE_TYPE)
          registry.add(type, serializer, deserializer, stored_type)
          self
        end

        def dump(record)
          data = transform(record.data)
          metadata = transform(record.metadata)
          if (metadata.respond_to?(:[]=))
            metadata[:types] = { data: store_type(record.data), metadata: store_type(record.metadata) }
          end

          Record.new(
            event_id: record.event_id,
            event_type: record.event_type,
            data: data,
            metadata: metadata,
            timestamp: record.timestamp,
            valid_at: record.valid_at
          )
        end

        def load(record)
          types =
            begin
              record.metadata.delete(:types)
            rescue StandardError
              nil
            end
          data_types = types&.fetch(:data, nil)
          metadata_types = types&.fetch(:metadata, nil)
          data = data_types ? restore_type(record.data, data_types) : record.data
          metadata = metadata_types ? restore_type(record.metadata, metadata_types) : record.metadata

          Record.new(
            event_id: record.event_id,
            event_type: record.event_type,
            data: data,
            metadata: metadata,
            timestamp: record.timestamp,
            valid_at: record.valid_at
          )
        end

        DEFAULT_STORE_TYPE = ->(argument) { argument.class.name }
        private_constant :DEFAULT_STORE_TYPE

        private
        attr_reader :registry

        def transform_hash(argument)
          argument.each_with_object({}) { |(key, value), hash| hash[transform(key)] = transform(value) }
        end

        def transform(argument)
          case argument
          when Hash
            transform_hash(argument)
          when Array
            argument.map { |i| transform(i) }
          else
            registry.of(argument.class).serializer[argument]
          end
        end

        def store_types(argument)
          argument.each_with_object({}) do |(key, value), hash|
            hash[transform(key)] = [store_type(key), store_type(value)]
          end
        end

        def store_type(argument)
          case argument
          when Hash
            store_types(argument)
          when Array
            argument.map { |i| store_type(i) }
          else
            registry.of(argument.class).stored_type[argument]
          end
        end

        def restore_types(argument, types)
          argument.each_with_object({}) do |(key, value), hash|
            key_type, value_type = types.fetch(key.to_sym) { types.fetch(key.to_s) }
            restored_key = restore_type(key, key_type)
            hash[restored_key] = restore_type(value, value_type)
          end
        end

        def restore_type(argument, type)
          case argument
          when Hash
            restore_types(argument, type)
          when Array
            argument.each_with_index.map { |a, idx| restore_type(a, type.fetch(idx)) }
          else
            registry.of(type).deserializer[argument]
          end
        end
      end
    end
  end
end
