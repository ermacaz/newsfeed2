class CreateNewsSources < ActiveRecord::Migration[7.1]
  def change
    create_table :news_sources do |t|
      t.string :name
      t.string :slug
      t.string :url
      t.string :feed_url, :limit=>1023
      t.boolean :enabled, :default=>true
      t.boolean :multiple_feeds, :default=>false
      t.string :scan_interval
      t.string :integer
      t.datetime :last_scanned_at

      t.timestamps
    end
    
    add_index :news_sources, :slug
  end
end
