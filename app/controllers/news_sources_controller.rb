class NewsSourcesController < ApplicationController
  include ActiveStorage::SetCurrent
  
  # GET /news_sources
  def index
    unless result = REDIS.call('get', 'newsfeed')
      NewsWorker.new.scrape
      result = REDIS.call('get', 'newsfeed')
    end
    @sources = JSON.parse(result).map do |set|
      OpenStruct.new(:name=>set['source_name'], :url=>set['source_url'], :stories=>set['stories'])
    end
    
  end
  
  def get_news
    NewsSourcesChannel.broadcast_to('news_sources_channel', JSON.parse(REDIS.call('get', 'newsfeed')))
    render :head=>:ok
  end
  
  def rss_feed
    @news_source = NewsSource.find_by_slug(params[:slug])
    cached_stories = REDIS.hvals(@news_source.cache_key).map {|s| JSON.parse(s)}.sort {|a| a['cached_time']}.reverse.first(10)
    if cached_stories.any?
      rss = RSS::Maker.make("atom") do |maker|
        maker.channel.author = "ermacaz"
        maker.channel.updated = Time.now.to_s
        maker.channel.about = "https://newsfeed.ermacaz.com/news_sources/rss_feed/#{params[:slug]}.rss"
        maker.channel.title = "Feed for #{@news_source.name}"
        
        cached_stories.each do |story|
          maker.items.new_item do |item|
            item.link = story["link"]
            item.title = story["title"]
            item.updated = Time.at(story["cache_time"]).to_s
          end
        end
      end
    end
  end
  
  def rss
    cache = JSON.parse(REDIS.call('get', 'newsfeed') || "[]").reject {|c| c['source_name'] == 'Reddit'}
    latest_stories = cache.map {|a| a['stories'].sort {|x,y| (x['pub_date'] || x['cache_time']) <=> (y['pub_date'] || y['cache_time'])}.reverse.first(3)}.flatten.sort {|x,y| (x['pub_date'] || x['cache_time']) <=> (y['pub_date'] || y['cache_time'])}.reverse.first(15)
    if latest_stories.any?
      rss = RSS::Maker.make("2.0") do |maker|
        maker.channel.author = "ermacaz"
        maker.channel.updated = Time.now.to_s
        maker.channel.about = "https://newsfeed.ermacaz.com/news_sources/rss.rss"
        maker.channel.link = "https://newsfeed.ermacaz.com/news_sources/rss.rss"
        maker.channel.description = "All feeds"
        maker.channel.title = "All feeds"
        
        latest_stories.each do |story|
          maker.items.new_item do |item|
            link_hash = Digest::MD5.hexdigest(story['link'])
            item.link = "https://newsfeed.ermacaz.com/#/#{story['source']}/#{link_hash}"
            item.title = story["title"]
            item.description = story["description"]
            item.updated = Time.at(story['pub_date'] || story["cache_time"]).to_s
          end
        end
      end
    else
      rss = ""
    end
    render :xml=>rss.to_s, :layout=>false
  end
  
  def get_story
    source = NewsSource.find_by_slug(params[:source_name])
    render :json=>REDIS.hget(source.cache_key, params[:story_hash])
  end
  #
  # # GET /news_sources/1
  # def show
  #   render json: @news_source
  # end
  #
  # # POST /news_sources
  # def create
  #   @news_source = NewsSource.new(news_source_params)
  #
  #   if @news_source.save
  #     render json: @news_source, status: :created, location: @news_source
  #   else
  #     render json: @news_source.errors, status: :unprocessable_entity
  #   end
  # end
  #
  # # PATCH/PUT /news_sources/1
  # def update
  #   if @news_source.update(news_source_params)
  #     render json: @news_source
  #   else
  #     render json: @news_source.errors, status: :unprocessable_entity
  #   end
  # end
  #
  # # DELETE /news_sources/1
  # def destroy
  #   @news_source.destroy
  # end
  
  private
  # Use callbacks to share common setup or constraints between actions.
  def set_news_source
    @news_source = NewsSource.find(params[:id])
  end
  
  # Only allow a trusted parameter "white list" through.
  def news_source_params
    params.require(:news_source).permit(:name, :feed_url)
  end
end
