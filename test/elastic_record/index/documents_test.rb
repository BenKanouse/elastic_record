require 'helper'

class ElasticRecord::Index::DocumentsTest < MiniTest::Test
  class InheritedWidget < Widget
    def self.base_class
      Widget
    end
  end

  def test_index_record
    record = Widget.new(id: '5', color: 'red')

    index.index_record(record)

    assert index.record_exists?('5')
    refute index.record_exists?('7')
  end

  def test_index_record_without_id
    index = Warehouse.elastic_index
    without_deferring(index) do
      warehouse = Warehouse.new(name: 'Amazon')
      result = index.index_record(warehouse)

      assert index.record_exists?(result['_id'])
      refute index.record_exists?('xyz')
    end
  end

  def test_index_document
    index.index_document('abc', color: 'red')

    assert index.record_exists?('abc')
    refute index.record_exists?('xyz')
  end

  def test_index_document_without_id
    index = Warehouse.elastic_index
    without_deferring(index) do
      result = index.index_document(nil, name: 'red')

      assert index.record_exists?(result['_id'])
      refute index.record_exists?('xyz')
    end
  end

  def test_update_document
    index.index_document('abc', warehouse_id: '5', color: 'red')
    index.update_document('abc', color: 'blue')

    expected = {'warehouse_id' => '5', 'color' => 'blue'}
    assert_equal expected, index.get('abc', index.mapping_type)['_source']

    assert_raises RuntimeError do
      index.update_document(nil, color: 'blue')
    end
  end

  def test_delete_document
    index.index_document('abc', color: 'red')
    assert index.record_exists?('abc')

    index.delete_document('abc')
    refute index.record_exists?('abc')

    assert_raises RuntimeError do
      index.delete_document('')
    end
  end

  def test_delete_by_query
    index.index_document('bob', name: 'bob')
    index.index_document('joe', name: 'joe')

    index.delete_by_query('query' => {query_string: {query: 'name:bob'}})

    refute index.record_exists?('bob')
    assert index.record_exists?('joe')
  end

  def test_build_scroll_enumerator
    index.index_document('bob', name: 'bob')
    index.index_document('joe', name: 'joe')

    scroll_enumerator = index.build_scroll_enumerator(search: {'query' => {query_string: {query: 'name:bob'}}})

    assert_equal 1, scroll_enumerator.total_hits
    assert_equal 1, scroll_enumerator.request_more_ids.size
  end

  def test_expired_scroll_error
    index.index_document('bob', name: 'bob')
    index.index_document('bobs', name: 'bob')

    scroll_enumerator = index.build_scroll_enumerator(
      search: { 'query' => { query_string: { query: 'name:bob' } } },
      batch_size: 1,
      keep_alive: '1ms'
    )

    scroll_enumerator.request_more_hits
    index.delete_scroll(scroll_enumerator.scroll_id)
    assert_raises ElasticRecord::ExpiredScrollError do
      scroll_enumerator.request_more_hits
    end
  end

  def test_each_slice
    10.times { |i| index.index_document("bob#{i}", color: 'red') }
    batches = []

    scroll_enumerator = index.build_scroll_enumerator(search: {'query' => {query_string: {query: 'color:red'}}}, batch_size: 1)

    scroll_enumerator.each_slice do |slice|
      batches << slice
    end
    # delete = index.connection.deferred_actions.first

    assert_equal 10, batches.size
    # refute scroll_enumerator.scroll_ids.any?
    # assert_equal :json_delete, delete.method
  end

  # def reset_scroll
  #   scroll_id = 'test'
  #   scroll_enumerator = index.build_scroll_enumerator(search: {'query' => {query_string: {query: ''}}}, scroll_id: scroll_id)
  #   scroll_enumerator.reset_scroll

  #   refute scroll_enumerator.scroll_ids.any?
  #   refute scroll_enumerator.instance_eval('@initial_search_response')
  #   assert_equal :json_delete, delete.method
  #   assert_equal ['/_search/scroll', {scroll_id: scroll_id}], delete.args
  # end

  def test_invalid_scroll_error
    assert_raises ElasticRecord::InvalidScrollError do
      index.scroll('invalid', '1m')
    end
  end

  def test_bulk
    assert_nil index.current_bulk_batch

    index.bulk do
      index.index_document '5', color: 'green'
      index.update_document '5', color: 'blue'
      index.delete_document '3'

      expected = [
        {index: {_index: index.alias_name, _type: "widget", _id: "5"}},
        {color: "green"},
        {update: {_index: "widgets", _type: "widget", _id: "5", retry_on_conflict: 3}},
        {doc: {color: "blue"}, doc_as_upsert: true},
        {delete: {_index: index.alias_name, _type: "widget", _id: "3", retry_on_conflict: 3}}
      ]
      assert_equal expected, index.current_bulk_batch
    end

    assert_nil index.current_bulk_batch
  end

  def test_bulk_nested
    expected_warehouse_count = Warehouse.count + 2

    Warehouse.elastic_index.bulk do
      Warehouse.elastic_index.bulk do
        Warehouse.create(name: 'Warehouse 13')
      end
      Warehouse.create(name: 'Warehouse 12')
    end

    assert_equal 2, Warehouse.elastic_relation.count
    assert_equal expected_warehouse_count, Warehouse.count
  end

  def test_bulk_nested_with_error
    expected_warehouse_count = Warehouse.count

    begin
      Warehouse.elastic_index.bulk do
        Warehouse.elastic_index.bulk do
          Warehouse.create(name: 'Warehouse 13')
        end

        Warehouse.create(name: nil)
      end
    rescue ActiveRecord::NotNullViolation
    end

    assert_equal 0, Warehouse.elastic_relation.count
  end

  def test_bulk_error
    without_deferring(index) do
      begin
        index.bulk do
          index.index_document '5', color: 'green'
          index.index_document '3', color: {'bad' => 'stuff'}
        end
        refute index.record_exists?('3')
        assert false, 'Expected ElasticRecord::BulkError'
      rescue => e
        assert_match '[{"index"', e.message
      end
    end
  end

  def test_bulk_inheritance
    without_deferring(index) do
      index.bulk do
        InheritedWidget.elastic_index.index_document '5', color: 'green'

        expected = [
          {index: {_index: index.alias_name, _type: "widget", _id: "5"}},
          {color: "green"}
        ]
        assert_equal expected, index.current_bulk_batch
      end
    end
  end

  private

    def without_deferring(index)
      index.disable_deferring!
      yield
      index.reset
      index.enable_deferring!
    end

    def index
      @index ||= Widget.elastic_index
    end
end
