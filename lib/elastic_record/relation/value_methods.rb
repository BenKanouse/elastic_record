module ElasticRecord
  class Relation
    MULTI_VALUE_METHODS  = [:extending, :facet, :filter, :order, :select, :aggregation]
    SINGLE_VALUE_METHODS = [:query, :limit, :offset, :reverse_order]
  end
end
