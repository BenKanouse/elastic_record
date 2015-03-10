require 'arelastic'
require 'active_support/core_ext/object/blank' # required because ActiveModel depends on this but does not require it
require 'active_support/concern'
require 'active_model'

module ElasticRecord
  autoload :Callbacks, 'elastic_record/callbacks'
  autoload :Config, 'elastic_record/config'
  autoload :Connection, 'elastic_record/connection'
  autoload :Index, 'elastic_record/index'
  autoload :Lucene, 'elastic_record/lucene'
  autoload :Model, 'elastic_record/model'
  autoload :Relation, 'elastic_record/relation'
  autoload :Searching, 'elastic_record/searching'

  class << self
    def configure
      yield(ElasticRecord::Config)
    end

    def json_parser
      @@json_parser ||= :active_support
    end

    def json_parser=(value)
      @@json_parser = value
    end
  end
end

require 'elastic_record/errors'
require 'elastic_record/railtie' if defined?(Rails)
