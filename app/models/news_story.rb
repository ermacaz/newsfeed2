class NewsStory
  
  attr_accessor :source, :pub_date, :link, :link_hash, :title, :content, :media_url_thumb, :media_url, :cache_time, :description
  def initialize(**kwargs)
    @source = kwargs[:source]
    @pub_date = kwargs[:pub_date]
    @link = kwargs[:link]
    @link_hash = Digest::MD5.hexdigest(story['link'])
    @title = kwargs[:title]
    @content = kwargs[:content]
    @media_url_thumb = kwargs[:media_url_thumb]
    @media_url = kwargs[:media_url]
    @cache_time = kwargs[:cache_time]
    @description = kwargs[:description]
  end
  
  def story_url
    "#/#{self.source}/#{self.link_hash}"
  end
end