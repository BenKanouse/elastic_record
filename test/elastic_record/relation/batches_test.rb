require 'helper'

class ElasticRecord::Relation::BatchesTest < MiniTest::Spec
  def setup
    Widget.reset_index!
    create_widgets
  end

  def test_find_each
    results = []
    Widget.relation.find_each do |widget|
      results << widget.id
    end
    assert_equal ['5', '10', '15'].to_set, results.to_set
  end

  def test_find_each_with_scope
    results = []
    Widget.relation.filter(color: %w(red blue)).find_each do |widget|
      results << widget.id
    end
    assert_equal ['5', '10'].to_set, results.to_set
  end

  private
    def create_widgets
      Widget.elastic_connection.index({'widget' => {'color' => 'red'}}, {index: 'widgets', type: 'widget', id: 5})
      Widget.elastic_connection.index({'widget' => {'color' => 'blue'}}, {index: 'widgets', type: 'widget', id: 10})
      Widget.elastic_connection.index({'widget' => {'color' => 'green'}}, {index: 'widgets', type: 'widget', id: 15})
      
      Widget.elastic_connection.refresh
    end
end