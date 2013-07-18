# -*- coding: utf-8 -*-
require 'test_helper'

require 'set'

require 'models/data_types'
require 'models/entry'
require 'models/auto_id'
require 'models/string_id'
require 'models/thing'
require 'models/custom_pk_name'
require 'models/validates_uniqueness_of_string'
require 'models/add_not_null_column_to_table'

ActiveRecord::Schema.verbose = false
ActiveRecord::Base.time_zone_aware_attributes = true if ActiveRecord::Base.respond_to?(:time_zone_aware_attributes)
ActiveRecord::Base.default_timezone = :utc

module MigrationSetup

  def setup
    setup!
  end

  def teardown
    teardown!
  end

  def setup!
    MigrationSetup.setup!
  end

  def teardown!
    MigrationSetup.teardown!
  end

  def self.setup!
    DbTypeMigration.up
    CreateStringIds.up
    CreateEntries.up
    CreateUsers.up
    CreateAutoIds.up
    CreateValidatesUniquenessOf.up
    CreateThings.up
    CreateCustomPkName.up
  end

  def self.teardown!
    DbTypeMigration.down
    CreateStringIds.down
    CreateEntries.down
    CreateUsers.down
    CreateAutoIds.down
    CreateValidatesUniquenessOf.down
    CreateThings.down
    CreateCustomPkName.down
  end

end

module FixtureSetup
  include MigrationSetup

  @@_time_zone = Time.respond_to?(:zone) ? Time.zone : nil

  def setup
    super
    #
    # just a random zone, unlikely to be local, and not UTC
    Time.zone = 'Moscow' if Time.respond_to?(:zone)
  end

  def teardown
    super
    #
    Time.zone = @@_time_zone if Time.respond_to?(:zone)
  end

end

module ColumnNameQuotingTests

  def self.included(base)
    base.class_eval do
      @@column_quote_char = "\""

      def self.column_quote_char(char)
        @@column_quote_char = char
      end
    end
  end

  def test_column_names_are_escaped
    conn = ActiveRecord::Base.connection
    quoted = conn.quote_column_name "foo#{column_quote_char}bar"
    assert_equal "#{column_quote_char}foo#{column_quote_char * 2}bar#{column_quote_char}", quoted
  end

  protected

  def column_quote_char
    @@column_quote_char || "\""
  end

end

module DirtyAttributeTests

  def test_partial_update_with_updated_at
    user = User.create!(:login => 'cicina')
    old_updated_at = 61.minutes.ago.in_time_zone

    do_update_all(User, { :updated_at => old_updated_at }, :login => user.login)

    with_partial_updates User, false do
      assert_queries(1) { user.save! }
    end

    do_update_all(User, { :updated_at => old_updated_at }, :login => user.login)

    with_partial_updates User, true do
      assert_queries(0) { user.save! }
      assert_datetime_equal old_updated_at, user.reload.updated_at

      assert_queries(1) { user.login = 'cicinbrus'; user.save! }
      assert_datetime_not_equal old_updated_at, user.reload.updated_at
    end
  end

  def test_partial_update_with_updated_on
    entry = Entry.create!(:title => 'foo')
    old_updated_on = 25.hours.ago.beginning_of_day.in_time_zone

    do_update_all(Entry, { :updated_on => old_updated_on }, :id => entry.id)

    with_partial_updates Entry, false do
      assert_queries(2) { 2.times { entry.save! } }
    end

    do_update_all(Entry, { :updated_on => old_updated_on }, :id => entry.id)

    with_partial_updates Entry, true do
      assert_queries(0) { 2.times { entry.save! } }
      assert_date_equal old_updated_on, entry.reload.updated_on

      assert_queries(1) { entry.title = 'bar'; entry.save! }
      assert_date_not_equal old_updated_on, entry.reload.updated_on
    end
  end

  private

  if ActiveRecord::VERSION::MAJOR > 3

    def with_partial_updates(klass, on = true)
      old = klass.partial_writes?
      klass.partial_writes = on
      yield
    ensure
      klass.partial_writes = old
    end

  else

    def with_partial_updates(klass, on = true)
      old = klass.partial_updates?
      klass.partial_updates = on
      yield
    ensure
      klass.partial_updates = old
    end

  end

  def do_update_all(model, values, conditions)
    if ar_version('3.2')
      model.where(conditions).update_all(values)
    else # User.update_all values, conditions deprecated on 4.0
      model.update_all(values, conditions)
    end
  end

end

module SimpleTestMethods
  include FixtureSetup

  def test_tables
    assert_not_empty ActiveRecord::Base.connection.tables
    tables = ActiveRecord::Base.connection.tables
    assert tables.find { |t| t =~ /^entries$/i }, "entries not created: #{tables.inspect}"
    assert tables.map(&:downcase).include?('users'), "users table not found: #{tables.inspect}"
  end

  def test_table_exists?
    assert_true  ActiveRecord::Base.connection.table_exists? 'entries'
    assert_false ActiveRecord::Base.connection.table_exists? 'blahbls'
  end

  def test_entries_empty
    Entry.delete_all
    assert_equal 0, Entry.count
  end

  def test_find_with_string_slug
    new_entry = Entry.create(:title => "Blah")
    entry = Entry.find(new_entry.to_param)
    assert_equal new_entry.id, entry.id
  end

  def test_insert_returns_id
    value = ActiveRecord::Base.connection.insert("INSERT INTO entries (title, content, rating) VALUES('insert_title', 'some content', 1)")
    assert !value.nil?
    entry = Entry.find_by_title('insert_title')
    assert_equal entry.id, value

    # Ensure we get the id even if the PK column is not named 'id'
    1.upto(4) do |i|
      cpn_name = "return id test#{i}"
      cpn = CustomPkName.new
      cpn.name = cpn_name
      cpn.save
      value = cpn.custom_id
      assert !value.nil?
      cpn = CustomPkName.find_by_name(cpn_name)
      assert_equal cpn.custom_id, value
    end
  end

  def test_create_new_entry
    Entry.delete_all

    title = "First post!"
    content = "Hello from JRuby on Rails!"
    rating = 205.76

    post = Entry.new
    post.title = title
    post.content = content
    post.rating = rating
    post.save

    assert_equal 1, Entry.count
  end

  def test_create_partial_new_entry
    Entry.create(:title => "Blah")
    Entry.create(:title => "Bloh")
  end

  def test_find_and_update_entry
    title = "First post!"
    content = "Hello from JRuby on Rails!"
    new_title = "First post updated title"
    rating = 205.76
    user = User.create! :login => "something"
    Entry.create! :title => title, :content => content, :rating => rating, :user => user

    post = Entry.first
    assert_equal title, post.title
    assert_equal content, post.content
    assert_equal rating, post.rating

    post.title = new_title
    post.save

    post = Entry.first
    assert_equal new_title, post.title
  end

  def test_destroy_entry
    user = User.create! :login => "something"
    Entry.create! :title => '1', :content => '', :rating => 1.0, :user => user
    Entry.create! :title => '2', :content => '', :rating => 2.0, :user => user

    prev_count = Entry.count
    entry = Entry.first
    entry.destroy

    assert_equal prev_count - 1, Entry.count
  end

  if Entry.respond_to?(:limit)
    def test_limit
      Entry.limit(10).to_a
    end

    def test_count_with_limit
      assert_equal Entry.count, Entry.limit(10).count
    end
  end

  if Time.respond_to?(:zone)

    def test_save_time_with_utc
      current_zone = Time.zone
      default_zone = ActiveRecord::Base.default_timezone
      ActiveRecord::Base.default_timezone = Time.zone = :utc
      now = Time.now
      my_time = Time.local now.year, now.month, now.day, now.hour, now.min, now.sec
      m = DbType.create! :sample_datetime => my_time
      m.reload

      assert_equal my_time, m.sample_datetime
    rescue
      Time.zone = current_zone
      ActiveRecord::Base.default_timezone = default_zone
    end

    def test_save_time_with_zone
      t = Time.now # precision will only be expected to the second :
      original_time = Time.local(t.year, t.month, t.day, t.hour, t.min, t.sec)
      time = original_time.in_time_zone
      e = DbType.create! :sample_datetime => time
      assert_equal time, e.reload.sample_datetime
    end

    def test_save_datetime
      t = Time.now # precision will only be expected to the second :
      time = Time.local(t.year, t.month, t.day, t.hour, t.min, t.sec)
      e = DbType.create! :sample_datetime => time.to_datetime
      assert_equal time, e.reload.sample_datetime.localtime
    end

  end

  def test_save_time
    # Ruby doesn't have a plain Time class without a date.
    time = Time.utc(2012, 12, 18, 21, 10, 15, 0)
    e = DbType.new
    e.sample_time = time
    e.save!

    assert_time_equal time, e.reload.sample_time
  end

  def test_save_timestamp
    timestamp = Time.utc(2012, 12, 18, 21, 10, 15, 0)
    e = DbType.create! :sample_datetime => Time.now
    e.sample_timestamp = timestamp
    e.save!
    assert_timestamp_equal timestamp, e.reload.sample_timestamp
  end

  def test_save_timestamp_with_usec
    timestamp = Time.utc(1942, 11, 30, 01, 53, 59, 123_456)
    e = DbType.create! :sample_timestamp => timestamp
    if ar_version('3.0')
      assert_timestamp_equal timestamp, e.reload.sample_timestamp
    else
      assert_datetime_equal timestamp, e.reload.sample_timestamp # only sec
    end
  end

  def test_time_usec_formatting_when_saved_into_string_column
    e = DbType.create!(:sample_string => '', :sample_text => '')
    t = Time.now
    value = Time.local(t.year, t.month, t.day, t.hour, t.min, t.sec, 0)
    if ActiveRecord::VERSION::MAJOR >= 3
      # AR-3 adapters override quoted_date which is called always when a
      # Time like value is passed (... as well for string/text columns) :
      str = value.utc.to_s(:db) << '.' << sprintf("%06d", value.usec)
    else # AR-2.x #quoted_date did not do TZ conversions
      str = value.to_s(:db)
    end
    e.sample_string = value
    e.sample_text = value
    e.save!; e.reload
    assert_equal str, e.sample_string
    assert_equal str, e.sample_text
  end

  def test_save_date
    date = Date.new(2007)
    e = DbType.new
    e.sample_date = date
    e.save!; e.reload
    assert_date_type e.sample_date
    assert_date_equal date, e.sample_date
  end

  def test_save_float
    e = DbType.new :sample_float => 12.0
    e.save!
    assert_equal 12.0, e.reload.sample_float
  end

  def test_boolean
    e = DbType.create! :sample_float => 0
    assert_nil e.reload.sample_boolean # unset boolean should default to nil

    e.update_attributes :sample_boolean => false
    assert_equal false, e.reload.sample_boolean

    e.sample_boolean = true
    e.save!
    assert_equal true, e.reload.sample_boolean
  end

  def test_integer
    e = DbType.create! :sample_boolean => false
    assert_nil e.reload.sample_integer

    e.sample_integer = 10
    e.save!
    assert_equal 10, e.reload.sample_integer
  end

  def test_text
    e = DbType.create! :sample_boolean => false
    assert_null_text e.reload.sample_text

    e.sample_text = "ooop?"
    e.save!
    assert_equal "ooop?", e.reload.sample_text
  end

  def test_string
    e = DbType.create! :sample_boolean => false
    assert_empty_string e.reload.sample_string

    e.sample_string = "ooop?"
    e.save!
    assert_equal "ooop?", e.reload.sample_string
  end

  def test_save_binary
    # string is 60_000 bytes
    binary_string = "\000ABCDEFGHIJKLMNOPQRSTUVWXYZ'\001\003" * 1 # 2_000
    e = DbType.new
    e.sample_binary = binary_string
    e.save!
    assert_equal binary_string, e.reload.sample_binary
  end

  def test_small_decimal
    test_value = 7.3
    db_type = DbType.new(:sample_small_decimal => test_value)
    db_type.save!
    db_type = DbType.find(db_type.id)
    assert_kind_of BigDecimal, db_type.sample_small_decimal
    assert_equal BigDecimal.new(test_value.to_s), db_type.sample_small_decimal

    test_value = BigDecimal('1.23')
    db_type = DbType.create!(:sample_small_decimal => test_value)
    if ar_version('3.0')
      assert_equal 1, DbType.where("sample_small_decimal < ?", 1.5).count
    else
      assert_equal 1, DbType.find(:all, :conditions => ["sample_small_decimal < ?", 1.5]).size
    end
  end

  def test_decimal # _with_zero_scale
    test_value = 7000.0
    db_type = DbType.create!(:sample_decimal => test_value)
    db_type = DbType.find(db_type.id)
    assert_kind_of Integer, db_type.sample_decimal
    assert_equal test_value.to_i, db_type.sample_decimal
  end

  def test_decimal_with_scale
    test_value = BigDecimal("100023400056.795")
    db_type = DbType.create!(:decimal_with_scale => test_value)
    assert_equal test_value, db_type.reload.decimal_with_scale
  end

  def test_big_decimal
    test_value = 9876543210_9876543210_9876543210.0
    db_type = DbType.create!(:big_decimal => test_value)
    db_type = DbType.find(db_type.id)
    assert_kind_of Bignum, db_type.big_decimal
    assert_equal test_value, db_type.big_decimal
  end

  # NOTE: relevant on 4.0 as it started using empty_insert_statement_value
  def test_empty_insert_statement
    DbType.create!
    assert DbType.first
    assert_not_nil DbType.first.id
  end

  def test_negative_default_value
    assert_equal(-1, DbType.columns_hash['sample_integer_neg_default'].default)
    assert_equal(-1, DbType.new.sample_integer_neg_default)
  end

  def test_created_records_have_different_ids
    e1 = Entry.create!(:title => "Blah")
    e2 = Entry.create!(:title => "Bloh")
    e3 = Entry.create!(:title => "Bloh")
    assert_not_nil e1.id
    assert_not_equal e1.id, e2.id
    assert_not_nil e2.id
    assert_not_equal e2.id, e3.id
    assert_not_nil e3.id
    assert_not_equal e3.id, e1.id
  end

  def test_indexes
    indexes = connection.indexes(:entries)
    assert_equal 0, indexes.size

    connection.add_index :entries, :updated_on
    connection.add_index :entries, [ :title, :user_id ], :unique => true,
                         :name => 'x_entries_on_title_and_user_id' # <= 30 chars

    indexes = connection.indexes(:entries)
    assert_equal 2, indexes.size

    assert_not_nil title_index = indexes.find { |index| index.unique }

    assert_equal "entries", title_index.table.to_s
    assert_true title_index.unique
    assert_equal [ 'title', 'user_id' ], title_index.columns

    updated_index = (indexes - [ title_index ]).first

    assert_equal "entries", updated_index.table.to_s
    assert_equal "index_entries_on_updated_on", updated_index.name
    assert ! updated_index.unique
    assert_equal [ 'updated_on' ], updated_index.columns

    connection.remove_index :entries, :updated_on
    indexes = connection.indexes(:entries)
    assert_equal 1, indexes.size
  end

  def test_nil_values
    e = DbType.create! :sample_integer => '', :sample_string => 'sample'
    assert_nil e.reload.sample_integer
  end

  # These should make no difference, but might due to the wacky regexp SQL rewriting we do.
  def test_save_value_containing_sql
    e = DbType.new :sample_string => 'sample'
    e.save!

    e.sample_string = e.sample_text = "\n\nselect from nothing where id = 'foo'"
    e.save!
  end

  def test_invalid
    title = "First post!"
    content = "Hello from JRuby on Rails!"
    rating = 205.76
    user = User.create! :login => "something"
    Entry.create! :title => title, :content => content, :rating => rating, :user => user

    e = Entry.new(:title => title, :content => content, :rating => ' ')
    assert e.valid?
  end

  def test_reconnect
    DbType.create! :sample_string => 'sample'
    assert_equal 1, DbType.count
    ActiveRecord::Base.connection.reconnect!
    assert_equal 1, DbType.count
  end

  if defined?(JRUBY_VERSION)
    def test_connection_valid
      assert_raise(ActiveRecord::JDBCError) do
        connection = ActiveRecord::Base.connection
        connection.raw_connection.with_connection_retry_guard do |c|
          begin
            stmt = c.createStatement
            stmt.execute "bogus sql"
          ensure
            stmt.close rescue nil
          end
        end
      end
    end

    class Animal < ActiveRecord::Base; end

    def test_fetching_columns_for_nonexistent_table
      disable_logger(Animal.connection) do
        assert_raise(ActiveRecord::StatementInvalid, ActiveRecord::JDBCError) do
          Animal.columns
        end
      end
    end
  end

  def test_disconnect
    DbType.create! :sample_string => 'sample'
    assert_equal 1, DbType.count
    ActiveRecord::Base.clear_active_connections!
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.respond_to?(:connection_pool)
    assert !ActiveRecord::Base.connected?
    assert_equal 1, DbType.count
    assert ActiveRecord::Base.connected?
  end

  def test_add_not_null_column_to_table
    AddNotNullColumnToTable.up
    AddNotNullColumnToTable.down
  end

  def test_add_null_column_with_default
    Entry.connection.add_column :entries, :color, :string, :null => false, :default => "blue"
    created_columns = Entry.connection.columns('entries')

    color = created_columns.detect { |c| c.name == 'color' }
    assert !color.null
  end

  def test_add_null_column_with_no_default
    # You must specify a default value with most databases
    if ActiveRecord::Base.connection.adapter_name =~ /mysql/i
      Entry.connection.add_column :entries, :color, :string, :null => false
      created_columns = Entry.connection.columns('entries')

      color = created_columns.detect { |c| c.name == 'color' }
      assert !color.null
    end
  end

  def test_add_null_column_with_nil_default
    # You must specify a default value with most databases
    if ActiveRecord::Base.connection.adapter_name =~ /mysql/i
      Entry.connection.add_column :entries, :color, :string, :null => false, :default => nil
      created_columns = Entry.connection.columns('entries')

      color = created_columns.detect { |c| c.name == 'color' }
      assert !color.null
    end
  end

  def test_validates_uniqueness_of_strings_case_sensitive
    name_lower = ValidatesUniquenessOfString.new(:cs_string => "name", :ci_string => '1')
    name_lower.save!

    name_upper = ValidatesUniquenessOfString.new(:cs_string => "NAME", :ci_string => '2')
    assert_nothing_raised do
      name_upper.save!
    end

    name_lower_collision = ValidatesUniquenessOfString.new(:cs_string => "name", :ci_string => '3')
    assert_raise ActiveRecord::RecordInvalid do
      name_lower_collision.save!
    end

    name_upper_collision = ValidatesUniquenessOfString.new(:cs_string => "NAME", :ci_string => '4')
    assert_raise ActiveRecord::RecordInvalid do
      name_upper_collision.save!
    end
  end

  def test_validates_uniqueness_of_strings_case_insensitive
    name_lower = ValidatesUniquenessOfString.new(:cs_string => '1', :ci_string => "name")
    name_lower.save!

    name_upper = ValidatesUniquenessOfString.new(:cs_string => '2', :ci_string => "NAME")
    assert_raise ActiveRecord::RecordInvalid do
      name_upper.save!
    end

    name_lower_collision = ValidatesUniquenessOfString.new(:cs_string => '3', :ci_string => "name")
    assert_raise ActiveRecord::RecordInvalid do
      name_lower_collision.save!
    end

    alternate_name_upper = ValidatesUniquenessOfString.new(:cs_string => '4', :ci_string => "ALTERNATE_NAME")
    assert_nothing_raised do
      alternate_name_upper.save!
    end

    alternate_name_upper_collision = ValidatesUniquenessOfString.new(:cs_string => '5', :ci_string => "ALTERNATE_NAME")
    assert_raise ActiveRecord::RecordInvalid do
      alternate_name_upper_collision.save!
    end

    alternate_name_lower = ValidatesUniquenessOfString.new(:cs_string => '6', :ci_string => "alternate_name")
    assert_raise ActiveRecord::RecordInvalid do
      alternate_name_lower.save!
    end
  end

  def test_substitute_binds_has_no_side_effect_on_binds_parameter
    binds = [ [ Entry.columns_hash['title'], 'test1' ] ]
    binds_dup = binds.dup
    sql = 'SELECT * FROM entries WHERE title = ?'
    Entry.connection.send :substitute_binds, sql, binds
    assert_equal binds_dup, binds
  end

  def test_find_by_sql_with_binds
    Entry.create!(:title => 'qqq', :content => '', :rating => 4)
    Entry.create!(:title => 'www', :content => '', :rating => 5)
    Entry.create!(:title => 'www', :content => '', :rating => 6)
    #ActiveRecord::Base.logger.level = Logger::DEBUG
    sql = 'SELECT * FROM entries WHERE ( title = ? OR title = ? ) AND rating < ? AND rating > ?'
    entries = Entry.find_by_sql [ sql, 'qqq', 'www', 6, 4 ]
    assert_equal 1, entries.size
  ensure
    #ActiveRecord::Base.logger.level = Logger::WARN
  end

  def test_find_by_sql_with_named_binds
    Entry.create!(:title => 'qqq', :content => '', :rating => 4)
    Entry.create!(:title => 'www', :content => '', :rating => 5)
    Entry.create!(:title => 'www', :content => '', :rating => 6)
    #ActiveRecord::Base.logger.level = Logger::DEBUG
    sql = 'SELECT * FROM entries WHERE ( title = :title OR title = :title ) AND rating < :upper AND rating > :lower'
    entries = Entry.find_by_sql [ sql, { :title => 'www', :upper => 6, :lower => 4 } ]
    assert_equal 1, entries.size
  ensure
    #ActiveRecord::Base.logger.level = Logger::WARN
  end

  def test_create_bind_param_with_q_mark
    str = "Don' botharrr talkin' like one, savvy? Right?!?"
    db_type = DbType.create! :sample_string => str.dup
    assert_equal str, db_type.reload.sample_string

    entry = Entry.create! :title => 'foo!', :content => 'bar?'
    assert_equal 'foo!', entry.reload.title
    assert_equal 'bar?', entry.content
  end

  def test_exec_update_bind_param_with_q_mark
    entry = Entry.create! :title => 'foo!'

    sql = "UPDATE entries SET title = ? WHERE id = #{entry.id}"
    connection.exec_update sql, 'UPDATE(with_q_mark)', [ [ nil, "bar?" ] ]
    assert_equal 'bar?', entry.reload.title
  end

  def test_exec_insert_bind_param_with_q_mark
    sql = "INSERT INTO entries(title) VALUES (?)"
    connection.exec_insert sql, 'INSERT(with_q_mark)', [ [ nil, "bar?!?" ] ]

    entries = Entry.find_by_sql "SELECT * FROM entries WHERE title = 'bar?!?'"
    assert entries.first
  end

  def test_raw_insert_bind_param_with_q_mark
    sql = "INSERT INTO entries(title) VALUES (?)"
    name = "INSERT(raw_with_q_mark)"
    pk = nil; id_value = nil; sequence_name = nil
    connection.insert sql, name, pk, id_value, sequence_name, [ [ nil, "?!huu!?" ] ]
    assert Entry.exists?([ 'title LIKE ?', "%?!huu!?%" ])
  end if Test::Unit::TestCase.ar_version('3.1') # no binds argument for <= 3.0

  def test_raw_update_bind_param_with_q_mark
    entry = Entry.create! :title => 'foo!'

    sql = "UPDATE entries SET title = ? WHERE id = #{entry.id}"
    name = "UPDATE(raw_with_q_mark)"
    title_column = Entry.columns.find { |n| n.to_s == 'title' }
    connection.update sql, name, [ [ title_column, "bar?" ] ]
    assert_equal 'bar?', entry.reload.title

    sql = "UPDATE entries SET title = ? WHERE id = ?"
    connection.update sql, name, [ [ nil, "?baz?!?" ], [ nil, entry.id ] ]
    assert_equal '?baz?!?', entry.reload.title
  end if Test::Unit::TestCase.ar_version('3.1') # no binds argument for <= 3.0

  def test_raw_delete_bind_param_with_q_mark
    entry = Entry.create! :title => 'foo?!?'

    sql = "DELETE FROM entries WHERE title = ?"
    name = "DELETE(raw_with_q_mark)"
    connection.delete sql, name, [ [ nil, "foo?!?" ] ]
    assert ! Entry.exists?(entry.id)
  end if Test::Unit::TestCase.ar_version('3.1') # no binds argument for <= 3.0

  class ChangeEntriesTable < ActiveRecord::Migration
    def self.up
      change_table :entries do |t|
        t.string :author
      end
    end
    def self.down
      change_table :entries do |t|
        t.remove :author
      end
    end
  end

  def test_change_table
    attributes = {
      :title => 'welcome to the real world',
      :content => '... TO BE CONTINUED ...',
      :author => 'kares'
    }
    assert_raise ActiveRecord::UnknownAttributeError do
      Entry.create! attributes
    end

    ChangeEntriesTable.up
    Entry.reset_column_information
    begin
      Entry.create! attributes
      if Entry.respond_to?(:where)
        e = Entry.where :author => 'kares'
      else # 2.3
        e = Entry.all :conditions => { :author => 'kares' }
      end
      assert e.first
    ensure
      ChangeEntriesTable.down # rescue nil
      Entry.reset_column_information
    end
  end # if Test::Unit::TestCase.ar_version('3.0')

  def test_string_id
    f = StringId.new
    f.id = "some_string"
    f.save
    f = StringId.first #reload is essential
    assert_equal "some_string", f.id
  end

  def test_handles_quotes_inside_of_strings
    content_json = {
      "comments" => [
        "First I was like, \"What, you've got crazy pants\"",
        "And then he was like, \"Yeah dude, total crazy pantalones\""
      ]
    }.to_json

    post = Entry.new :title => 'comment entry'
    post.content = content_json
    post.save!

    assert_equal content_json, post.reload.content
  end

  def test_exec_insert
    name_column = Thing.columns.detect { |column| column.name.to_s == 'name' }
    created_column = Thing.columns.detect { |column| column.name.to_s == 'created_at' }
    updated_column = Thing.columns.detect { |column| column.name.to_s == 'updated_at' }
    now = Time.zone.now

    binds = [ [ name_column, 'ferko' ], [ created_column, now ], [ updated_column, now ] ]
    connection.exec_insert "INSERT INTO things VALUES (?,?,?)", 'INSERT_1', binds
    assert Thing.find_by_name 'ferko'
    # NOTE: #exec_insert accepts 5 arguments on AR-4.0 :
    binds = [ [ name_column, 'jozko' ], [ created_column, now ], [ updated_column, now ] ]
    connection.exec_insert "INSERT INTO things VALUES (?,?,?)", 'INSERT_2', binds, nil, nil
    assert Thing.find_by_name 'jozko'
  end

  def test_exec_query_result
    Entry.delete_all
    user1 = User.create! :login => 'user1'
    user2 = User.create! :login => 'user2'
    Entry.create! :title => 'user11', :user_id => user1.id
    Entry.create! :title => 'user12', :user_id => user1.id
    Entry.create! :title => 'user21', :user_id => user2.id

    result = Entry.connection.exec_query 'SELECT * FROM entries'

    if ar_version('3.1')
      assert_instance_of ActiveRecord::Result, result
      assert_not_empty result.columns
      columns = Entry.columns.map { |column| column.name.to_s }
      assert_equal Set.new(columns), Set.new(result.columns)

      assert_equal 3, result.rows.size
      assert_instance_of Array, result.rows[0]
      assert_equal 'user11', result.rows[0][1]
      assert_equal 'user12', result.rows[1][1]
    else
      assert_instance_of Array, result
      assert_equal 3, result.size
      assert_instance_of Hash, result[0]
      assert_equal 'user11', result[0]['title']
      assert_equal user1.id, result[0]['user_id']
    end
  end

  def test_exec_query_empty_result
    Entry.delete_all; User.delete_all

    result = User.connection.exec_query 'SELECT * FROM users'

    if ar_version('3.1')
      assert_instance_of ActiveRecord::Result, result
      assert_not_empty result.columns
      columns = User.columns.map { |column| column.name.to_s }
      assert_equal Set.new(columns), Set.new(result.columns)

      assert_equal 0, result.rows.size
    else
      assert_instance_of Array, result
      assert_equal 0, result.size
    end
  end

  def test_exec_query_raw
    User.delete_all
    User.create! :login => 'user1'
    User.create! :login => 'user2'

    result = User.connection.exec_query_raw 'SELECT * FROM users'

    assert_instance_of Array, result
    assert_equal 2, result.size
    assert_instance_of Hash, result[0]
    assert_equal 'user1', result[0]['login']
    assert_equal 'user2', result[1]['login']
  end

  def test_exec_query_raw_yields
    User.create! :login => 'user3'
    User.create! :login => 'user4'

    arel = User.select('id, login, created_at').where("login = 'user3' or login = 'user4'")
    yielded = 0
    ActiveRecord::Base.connection.exec_query_raw(arel) do |*args| # id, login, created_at
      assert_equal 3, args.size
      yielded += 1
      case yielded
      when 1
        assert_equal 'user3', args[1]
      when 2
        assert_equal 'user4', args[1]
      else
        fail "yielded 3 times"
      end
    end
    assert yielded == 2
  end if Test::Unit::TestCase.ar_version('3.0')

  def test_select
    Entry.delete_all
    user = User.create! :login => 'select'
    Entry.create! :title => 'title 1', :content => 'content 1', :user_id => user.id, :rating => 1.0
    Entry.create! :title => 'title 2', :content => 'content 2', :user_id => user.id, :rating => 2.0

    # rows = connection.execute 'SELECT * FROM entries'
    # column_order = rows.first.keys

    result = connection.select 'SELECT * FROM entries'

    if ar_version('4.0')
      assert_instance_of ActiveRecord::Result, result
      assert_equal 2, result.rows.size
    else
      assert_instance_of Array, result
      assert_equal 2, result.size
    end
  end

  def test_select_rows
    Entry.delete_all
    user = User.create! :login => 'select_rows'
    Entry.create! :title => 'title 1', :content => 'content 1', :user_id => user.id
    Entry.create! :title => 'title 2', :content => 'content 2', :user_id => user.id, :rating => 1.0

    rows = connection.execute 'SELECT * FROM entries'
    column_order = rows.first.keys

    rows = connection.select_rows 'SELECT * FROM entries'
    assert_instance_of Array, rows
    assert_equal 2, rows.size

    row = rows[0]
    column_order.each_with_index do |column, i|
      case column.to_s
      when 'id' then assert_not_nil row[i]
      when 'title' then assert_equal 'title 1', row[i]
      when 'content' then assert_equal 'content 1', row[i]
      when 'user_id' then assert_equal user.id, row[i]
      when 'rating' then assert_nil row[i]
      when 'updated_on' then assert_not_nil row[i]
      else raise "unexpected entries row: #{column.inspect}"
      end
    end

    row = rows[1]
    column_order.each_with_index do |column, i|
      case column.to_s
      when 'id' then assert_not_nil row[i]
      when 'title' then assert_equal 'title 2', row[i]
      when 'content' then assert_equal 'content 2', row[i]
      when 'user_id' then assert_equal user.id, row[i]
      when 'rating' then assert_not_nil row[i]
      when 'updated_on' then assert_not_nil row[i]
      else raise "unexpected entries row: #{column.inspect}"
      end
    end
  end

  def test_update
    user = User.create! :login => 'update'

    User.update(user.id, :login => 'UPDATEd')
    assert_equal 'UPDATEd', user.reload.login
  end

  def test_connection_alive_sql
    connection = ActiveRecord::Base.connection
    if alive_sql = connection.config[:connection_alive_sql]
      connection.execute alive_sql
    end
    # if no alive SQL than JDBC 4.0 driver's "alive" test will be used
  end

  def test_connection_valid
    connection = ActiveRecord::Base.connection
    assert connection.active? # JDBC connection.isValid (if alive_sql not set)
  end

  def test_query_cache
    user_1 = User.create! :login => 'query_cache_1'
    user_2 = User.create! :login => 'query_cache_2'
    user_3 = User.create! :login => 'query_cache_3'
    # NOTE: on 3.1 AR::Base.cache does not cache if AR not configured,
    # due : `if ActiveRecord::Base.configurations.blank?; yield ...`
    User.connection.cache do # instead of simply `User.cache`
      id1 = user_1.id; id2 = user_2.id
      assert_queries(2) { User.find(id1); User.find(id1); User.find(id2); User.find(id1) }
    end
    User.connection.uncached do
      id1 = user_1.id; id3 = user_3.id
      assert_queries(3) { User.find(id3); User.find(id1); User.find(id3) }
    end
  end

  protected

  def assert_date_type(value)
    assert_instance_of Date, value
  end

end

module MultibyteTestMethods
  include MigrationSetup

  if defined?(JRUBY_VERSION)
    def setup
      super
      config = ActiveRecord::Base.connection.config
      jdbc_driver = ActiveRecord::ConnectionAdapters::JdbcDriver.new(config[:driver])
      @java_connection = jdbc_driver.connection(config[:url], config[:username], config[:password])
      @java_connection.setAutoCommit(true)
    end

    def teardown
      @java_connection.close
      super
    end

    def test_select_multibyte_string
      @java_connection.createStatement().
        execute("insert into entries (id, title, content) values (1, 'テスト', '本文')")
      entry = Entry.first
      assert_equal "テスト", entry.title
      assert_equal "本文", entry.content
      assert_equal entry, Entry.find_by_title("テスト")
    end

    def test_update_multibyte_string
      Entry.create!(:title => "テスト", :content => "本文")
      rs = @java_connection.createStatement().
        executeQuery("select title, content from entries")
      assert rs.next
      assert_equal "テスト", rs.getString(1)
      assert_equal "本文", rs.getString(2)
    end
  end

  def test_multibyte_aliasing
    str = "テスト"
    quoted_alias = Entry.connection.quote_column_name(str)
    sql = "SELECT title AS #{quoted_alias} from entries"
    records = Entry.connection.select_all(sql)
    records.each do |rec|
      rec.keys.each do |key|
        assert_equal str, key
      end
    end
  end

  def test_chinese_word
    chinese_word = '中文'
    new_entry = Entry.create(:title => chinese_word)
    new_entry.reload
    assert_equal chinese_word, new_entry.title
  end
end

module NonUTF8EncodingMethods
  def setup
    @connection = ActiveRecord::Base.remove_connection
    latin2_connection = @connection.dup
    latin2_connection[:encoding] = 'latin2'
    latin2_connection.delete(:url) # pre-gen url gets stashed; remove to re-gen
    ActiveRecord::Base.establish_connection latin2_connection
    CreateEntries.up
  end

  def teardown
    CreateEntries.down
    ActiveRecord::Base.establish_connection @connection
  end

  def test_nonutf8_encoding_in_entry
    prague_district = 'hradčany'
    new_entry = Entry.create :title => prague_district
    new_entry.reload
    assert_equal prague_district, new_entry.title
  end
end

module XmlColumnTests

  def self.included(base)
    base.send :include, TestMethods if base.ar_version('3.1')
  end

  class XmlModel < ActiveRecord::Base; end

  module TestMethods

    def test_create_xml_column
      create_xml_models! do |t|
        skip('TableDefinition#xml not-implemented') unless t.respond_to?(:xml)
      end

      xml_column = connection.columns(:xml_models).detect do |c|
        c.name == "xml_col"
      end

      assert_xml_type xml_column.sql_type
    ensure
      drop_xml_models! rescue false
    end

    def test_use_xml_column
      if created = ( ( create_xml_models! || true ) rescue nil )

        XmlModel.create! :xml_col => "<xml><LoVE><![CDATA[Rubyist's <3 XML!]]></LoVE></xml>"

        assert xml_model = XmlModel.first

        unless xml_sql_type =~ /text/i
          require 'rexml/document'
          doc = REXML::Document.new xml_model.xml_col
          assert_equal "Rubyist's <3 XML!", doc.root.elements.first.text
        end

      else
        skip('TableDefinition#xml not-implemented')
      end
    ensure
      drop_xml_models! if created
    end

    protected

    def assert_xml_type sql_type
      assert_equal xml_sql_type, sql_type
    end

    def xml_sql_type
      'text'
    end

    private

    def create_xml_models!
      connection.create_table(:xml_models) do |t|
        yield(t) if block_given?
        t.xml :xml_col
      end
    end

    def drop_xml_models!
      disable_logger(connection) do
        connection.drop_table(:xml_models)
      end
    end

  end

end

module ActiveRecord3TestMethods

  def self.included(base)
    base.send :include, TestMethods if base.ar_version('3.0')
  end

  module TestMethods

    def test_visitor_accessor
      adapter = Entry.connection
      assert_not_nil visitor_type = adapter.class.resolve_visitor_type(adapter.config)
      assert_not_nil adapter.visitor
      assert_kind_of visitor_type, adapter.visitor
    end if Test::Unit::TestCase.ar_version('3.1') # >= 3.2

    def test_where
      user = User.create! :login => "blogger"
      entry = Entry.create! :title => 'something', :content => 'JRuby on Rails !', :rating => 42.1, :user => user

      entries = Entry.where(:title => entry.title)
      assert_equal entry, entries.first
    end

    def test_update_all
      user = User.create! :login => "blogger"
      e1 = Entry.create! :title => 'JRuby #1', :content => 'Getting started with JRuby ...', :user => user
      e2 = Entry.create! :title => 'JRuby #2', :content => 'Setting up with JRuby on Rails', :user => user

      user.entries.update_all :rating => 12.3
      assert_equal 12.3, e1.reload.rating
      assert_equal 12.3, e2.reload.rating
    end

    def test_remove_nonexistent_index
      assert_raise(ArgumentError, ActiveRecord::StatementInvalid, ActiveRecord::JDBCError) do
        connection.remove_index :entries, :nonexistent_index
      end
    end

    def test_add_index_with_invalid_name_length
      index_name = 'x' * (connection.index_name_length + 1)
      assert_raise(ArgumentError) do
        connection.add_index "entries", "title", :name => index_name
      end
    end

    def test_model_with_no_id
      assert_nothing_raised do
        Thing.create! :name => "a thing"
      end
      assert_equal 1, Thing.count
    end

  end

end

module ResetColumnInformationTestMethods
  class Fhqwhgad < ActiveRecord::Base
  end

  def test_reset_column_information
    drop_fhqwhgads_table!
    create_fhqwhgads_table_1!
    Fhqwhgad.reset_column_information
    assert_equal ["id", "come_on"].sort, Fhqwhgad.columns.map{|c| c.name}.sort, "columns should be correct the first time"

    drop_fhqwhgads_table!
    create_fhqwhgads_table_2!
    Fhqwhgad.reset_column_information
    assert_equal ["id", "to_the_limit"].sort, Fhqwhgad.columns.map{|c| c.name}.sort, "columns should be correct the second time"
  ensure
    drop_fhqwhgads_table!
  end

  private

    def drop_fhqwhgads_table!
      ActiveRecord::Schema.define do
        suppress_messages do
          drop_table :fhqwhgads if table_exists? :fhqwhgads
        end
      end
    end

    def create_fhqwhgads_table_1!
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table :fhqwhgads do |t|
            t.string :come_on
          end
        end
      end
    end

    def create_fhqwhgads_table_2!
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table :fhqwhgads do |t|
            t.string :to_the_limit, :null=>false, :default=>'everybody'
          end
        end
      end
    end
end

module ExplainSupportTestMethods

  PRINT_EXPLAIN_OUTPUT = java.lang.Boolean.getBoolean('explain.support.output')

  def test_supports_explain
    assert ActiveRecord::Base.connection.supports_explain?
  end

  def test_explain_without_binds
    create_explain_data

    pp = ActiveRecord::Base.connection.explain(
      "SELECT * FROM entries JOIN users on entries.user_id = users.id WHERE entries.rating > 0"
    )
    puts "\n"; puts pp if PRINT_EXPLAIN_OUTPUT
    assert_instance_of String, pp
  end

  def test_explain_with_binds
    create_explain_data

    binds = [ [ Entry.columns.find { |col| col.name.to_s == 'rating' }, 0 ] ]
    pp = ActiveRecord::Base.connection.explain(
      "SELECT * FROM entries JOIN users on entries.user_id = users.id WHERE entries.rating > ?", binds
    )
    puts "\n"; puts pp if PRINT_EXPLAIN_OUTPUT
    assert_instance_of String, pp
  end

  private
  def create_explain_data
    user_1 = User.create :login => 'user_1'
    user_2 = User.create :login => 'user_2'

    Entry.create :title => 'title_1', :content => 'content_1', :rating => 1, :user_id => user_1.id
    Entry.create :title => 'title_2', :content => 'content_2', :rating => 2, :user_id => user_2.id
    Entry.create :title => 'title_3', :content => 'content', :rating => 0, :user_id => user_1.id
    Entry.create :title => 'title_4', :content => 'content', :rating => 0, :user_id => user_1.id
  end

end

module CustomSelectTestMethods

  def test_custom_select_float
    model = DbType.create! :sample_float => 1.42
    if ActiveRecord::VERSION::MAJOR >= 3
      model = DbType.where("id = #{model.id}").select('sample_float AS custom_sample_float').first
    else
      model = DbType.find(:first, :conditions => "id = #{model.id}", :select => 'sample_float AS custom_sample_float')
    end
    assert_equal 1.42, model.custom_sample_float
    assert_instance_of Float, model.custom_sample_float
  end

  def test_custom_select_decimal
    model = DbType.create! :sample_small_decimal => ( decimal = BigDecimal.new('5.45') )
    if ActiveRecord::VERSION::MAJOR >= 3
      model = DbType.where("id = #{model.id}").select('sample_small_decimal AS custom_decimal').first
    else
      model = DbType.find(:first, :conditions => "id = #{model.id}", :select => 'sample_small_decimal AS custom_decimal')
    end
    assert_equal decimal, model.custom_decimal
    assert_instance_of BigDecimal, model.custom_decimal
  end

  def test_custom_select_datetime
    my_time = Time.local 2013, 03, 15, 19, 53, 51, 0 # usec
    model = DbType.create! :sample_datetime => my_time
    if ActiveRecord::VERSION::MAJOR >= 3
      model = DbType.where("id = #{model.id}").select('sample_datetime AS custom_sample_datetime').first
    else
      model = DbType.find(:first, :conditions => "id = #{model.id}", :select => 'sample_datetime AS custom_sample_datetime')
    end
    assert_equal my_time, model.custom_sample_datetime
    sample_datetime = model.custom_sample_datetime
    assert sample_datetime.acts_like?(:time), "expected Time-like instance but got: #{sample_datetime.class}"
  end

  def test_custom_select_date
    my_date = Time.local(2000, 01, 30, 0, 0, 0, 0).to_date
    model = DbType.create! :sample_date => my_date
    if ActiveRecord::VERSION::MAJOR >= 3
      model = DbType.where("id = #{model.id}").select('sample_date AS custom_sample_date').first
    else
      model = DbType.find(:first, :conditions => "id = #{model.id}", :select => 'sample_date AS custom_sample_date')
    end
    assert_equal my_date, model.custom_sample_date
    sample_date = model.custom_sample_date
    assert sample_date.acts_like?(:date), "expected Date-like instance but got: #{sample_date.class}"
  end

end
