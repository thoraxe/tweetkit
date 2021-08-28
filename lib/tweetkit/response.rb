require 'json'
require 'pry'

module Tweetkit
  module Response
    class Tweets
      include Enumerable

      attr_accessor :annotations, :connection, :context_annotations, :entity_annotations, :expansions, :fields, :meta, :options, :original_response, :response, :tweets, :twitter_request

      def initialize(response, **options)
        parse! response, **options
      end

      def parse!(response, **options)
        parse_response response
        extract_and_save_tweets
        extract_and_save_meta
        extract_and_save_expansions
        extract_and_save_options(**options)
        extract_and_save_request
      end

      def parse_response(response)
        @original_response = response.body
        @response = JSON.parse(@original_response)
      end

      def extract_and_save_tweets
        if @response['data']
          @tweets = @response['data'].collect { |tweet| Tweet.new(tweet) }
        else
          @tweets = []
        end
      end

      def extract_and_save_meta
        @meta = Meta.new(@response['meta'])
      end

      def extract_and_save_expansions
        @expansions = @response['includes']
      end

      def extract_and_save_options(**options)
        @options = options
      end

      def extract_and_save_request
        @connection = @options[:connection]
        @twitter_request = @options[:twitter_request]
      end

      def each(*args, &block)
        tweets.each(*args, &block)
      end

      def last
        tweets.last
      end

      def next_page
        connection.params.merge!({ next_token: meta.next_token })
        response = connection.get(twitter_request[:previous_url])
        parse! response,
               connection: connection,
               twitter_request: {
                 previous_url: twitter_request[:previous_url],
                 previous_query: twitter_request[:previous_query]
               }
        self
      end

      def prev_page
        connection.params.merge!({ previous: meta.previous_token })
        response = connection.get(twitter_request[:previous_url])
        parse! response,
               connection: connection,
               twitter_request: {
                 previous_url: twitter_request[:previous_url],
                 previous_query: twitter_request[:previous_query]
               }
        self
      end

      class Tweet
        attr_accessor :annotations, :data

        def initialize(tweet)
          @data = tweet
          @annotations = Annotations.new(data['context_annotations'], data['entities'])
        end

        def id
          data['id']
        end

        def text
          data['text']
        end

        def context_annotations
          @annotations.context_annotations
        end

        def entity_annotations
          @annotations.entity_annotations
        end

        class Annotations
          attr_accessor :context_annotations, :entity_annotations

          def initialize(context_annotations, entity_annotations)
            @context_annotations = Context.new(context_annotations) unless context_annotations.nil? || context_annotations.empty?
            @entity_annotations = Entity.new(entity_annotations) unless entity_annotations.nil? || entity_annotations.empty?
          end

          class Context
            include Enumerable

            attr_accessor :annotations

            def initialize(annotations)
              @annotations = annotations.collect { |annotation| Annotation.new(annotation) }
            end

            def each(*args, &block)
              annotations.each(*args, &block)
            end

            class Annotation
              attr_accessor :domain, :entity

              def initialize(annotation)
                @domain = annotation['domain']
                @entity = annotation['entity']
              end
            end
          end

          class Entity
            include Enumerable

            attr_accessor :annotations, :mentions

            def initialize(entity_annotations)
              @annotations = entity_annotations['annotations'].collect { |annotation| Annotation.new(annotation) } if entity_annotations['annotations']
              @mentions = entity_annotations['mentions'].collect { |annotation| Mention.new(annotation) } if entity_annotations['mentions']
            end

            def each(*args, &block)
              annotations.each(*args, &block)
            end

            class Annotation
              attr_accessor :end, :probability, :start, :text, :type

              def initialize(annotation)
                @end = annotation['end']
                @probability = annotation['probability']
                @start = annotation['start']
                @text = annotation['normalized_text']
                @type = annotation['type']
              end
            end

            class Mention
              attr_accessor :end, :id, :start, :username

              def initialize(mention)
                @end = mention['end']
                @id = mention['id']
                @start = mention['start']
                @username = mention['username']
              end
            end
          end
        end
      end

      class Expansions
        attr_accessor :media, :places, :polls, :tweets, :users

        def initialize(expansions)
          @media = expansions['media']
          @places = expansions['places']
          @polls = expansions['polls']
          @tweets = expansions['tweets']
          @users = expansions['users']
        end
      end

      class Fields
        attr_accessor :fields, :media_fields, :place_fields, :poll_fields, :tweet_fields, :user_fields

        def initialize(fields)
          @fields = fields 
          build_and_normalize_fields(fields) unless fields.nil?
        end

        def build_and_normalize_fields(fields)
          fields.each_key do |field_type|
            normalized_field = build_and_normalize_field(@fields[field_type], field_type)
            instance_variable_set(:"@#{field_type}", normalized_field)
            self.class.define_method(field_type) { instance_variable_get("@#{field_type}") }
          end
        end

        def build_and_normalize_field(field, field_type)
          Field.new(field, field_type)
        end

        def method_missing(method, **args)
          return nil if VALID_FIELDS.include?(method.to_s)

          super
        end

        def respond_to_missing?(method, *args)
          VALID_FIELDS.include?(method.to_s) || super
        end

        class Field
          include Enumerable

          attr_accessor :normalized_field, :original_field

          FIELD_NORMALIZATION_KEY = {
            'users': 'id'
          }.freeze

          def initialize(field, field_type)
            @original_field = field
            @normalized_field = {}
            normalization_key = FIELD_NORMALIZATION_KEY[field_type.to_sym]
            field.each do |data|
              key = data[normalization_key]
              @normalized_field[key.to_i] = data
            end
          end

          def each(*args, &block)
            @normalized_field.each(*args, &block)
          end

          def each_data(*args, &block)
            @normalized_field.values.each(*args, &block)
          end

          def find(key)
            @normalized_field[key.to_i]
          end
        end
      end

      class Meta
        attr_accessor :data

        def initialize(meta)
          @data = meta
        end

        def next_token
          @data['next_token']
        end

        def previous_token
          @data['previous_token']
        end

        # def method_missing(attribute, **args)
        #   data = meta[attribute.to_s]
        #   data.empty? ? super : data
        # end

        # def respond_to_missing?(method, *args)
        #   meta.respond_to? method
        # end
      end
    end
  end
end
