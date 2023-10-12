class NewsSource < ApplicationRecord
  scope :active, -> {where(:enabled=>true)}
  
  TEDDIT_URL = "teddit.ermacaz.com"
  
  def self.update_teddit_source
    NewsSource.find_by_name('Reddit').update!(:feed_url=>"https://#{NewsSource::TEDDIT_URL}/r/All?api&type=rss")
  end
  
  before_save :set_slug
  def set_slug
    self.slug = self.name.downcase.gsub(' ', '_')
  end
  
  attr_accessor :feed
  
  def scrape
    NewsWorker.new.scrape([self])
  end
  
  def self.clear_old_caches
    puts "Beginning run at #{Time.zone.now.in_time_zone('Arizona')}"
    current_caches = REDIS.smembers("newsfeed_caches")
    current_caches.each do |caches_key|
      current_cached_stories = REDIS.hkeys(caches_key)
      stories_to_del = current_cached_stories.select do |cache|
        store = REDIS.hget(caches_key, cache)
        begin
          story = JSON.parse(store)
          story.keys.exclude?("cache_time") || Time.at(story["cache_time"].to_i) < 48.hours.ago
        rescue
          # if the json cant be parsed just delete
          true
        end
      end
      if stories_to_del.count > 0
        puts caches_key
      end
      REDIS.multi do |r|
        stories_to_del.each do |link_hash|
          r.hdel(caches_key, link_hash)
          StoryImage.where(:link_hash=>link_hash).each(&:purge)
          StoryVideo.where(:link_hash=>link_hash).each(&:purge)
        end
      end
    end
  end
  
  def feed
    unless @feed
      begin
        if self.multiple_feeds
          feed_urls = self.feed_url.split(";")
          feeds = []
          feed_urls.each do |feed_url|
            feeds << (SimpleRSS.parse URI.open(feed_url, 'User-Agent'=>'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36') rescue nil)
          end
          @feed = feeds.map {|f| f.entries.first(25)}.flatten.uniq {|x| x[:title]}.sort {|x,y| y[:pubDate] <=> x[:pubDate]}.first(25)
        else
          if self.name == 'No Recipes'
            @feed = (SimpleRSS.parse HTTParty.get(self.feed_url, :headers=>{'User-agent'=>'ermacaz'}) rescue nil)
          else
            @feed = (SimpleRSS.parse URI.open(self.feed_url, 'User-Agent'=>'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36') rescue nil)
          end
        end
        if @feed.nil?
          @feed = (SimpleRSS.parse HTTParty.get(self.feed_url, :headers=>{'User-agent'=>'ermacaz'}) rescue nil)
        end
      rescue Exception=>e
        Rails.logger.error("Error getting feed for source #{self.name}")
        Rails.logger.error(e.message)
        @feed =nil
      end
    end
    @feed
  end
  
  def self.clear_all_caches
    current_caches = REDIS.smembers("newsfeed_caches")
    current_caches.each do |caches_key|
      current_cached_stories = REDIS.hkeys(caches_key)
      REDIS.hdel(caches_key, current_cached_stories)
      StoryImage.where(:link_hash=>current_cached_stories).each(&:purge)
      StoryVideo.where(:link_hash=>current_cached_stories).each(&:purge)
    end
  end
  
  def get_cached_stories
    REDIS.hgetall(cache_key)
  end
  
  def get_cached_story_keys
    REDIS.hkeys(cache_key)
  end
  
  def delete_cached_stories
    current_cached_stories = REDIS.hkeys(self.cache_key)
    REDIS.hdel(self.cache_key, current_cached_stories)
    StoryImage.where(:link_hash=>current_cached_stories).each {|a| begin a.purge rescue puts "unable to purge image/video with hash #{a.link_hash}" end}
    StoryVideo.where(:link_hash=>current_cached_stories).each {|a| begin a.purge rescue puts "unable to purge image/video with hash #{a.link_hash}" end}
  end
  
  def get_cached_story(link_hash)
    store = REDIS.hget(self.cache_key, link_hash)
    if store
      JSON.parse(store)
    else
      nil
    end
  end
  
  def cache_key
    "cached_stories:#{self.name.downcase.gsub(' ','_')}"
  end
  
  def self.update_index_cache
    index_data = self.build_index
    REDIS.call("SET", "newsfeed", index_data.to_json)
  end
  
  def self.build_index
    full_set = []
    NewsSource.find_each do |source|
      set = {:source_name=>source.name, :source_url=>source.url, :stories=>[]}
      cached_feed = source.get_cached_stories
      if cached_feed
        cached_feed = cached_feed.sort {|a,b| ((JSON.parse(b[1])['pub_date'] || JSON.parse(b[1])['cache_time']) rescue 5.years.ago.to_i) <=>  ((JSON.parse(a[1])['pub_date'] || JSON.parse(a[1])['cache_time']) rescue 5.years.ago.to_i)}.first(NewsWorker::NUM_STORIES)
        cached_feed.each do |story|
          s = JSON.parse(story[1])
          # dont send full content just mark its present
          s['content'] = true if s['content']
          set[:stories] << s
        end
      end
      full_set << set
    end
    full_set
  end
end
