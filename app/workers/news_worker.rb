class NewsWorker
  require 'simple-rss'
  require 'open-uri'
  require 'nokogiri'
  require 'cgi'
  
  NUM_STORIES = 25
  
  if Rails.env == 'production'
    ActiveStorage::Current.url_options = { protocol: 'https', host: 'newsfeedapi.ermacaz.com' }
  else
    ActiveStorage::Current.url_options = { protocol: 'http', host: 'localhost', port: '3001' }
  end
  
  ## TODO
  # cache images at thumb and modal size?
  # parse full pages with lazy load images with apparition?
  def scrape(sources=NewsSource.active, nocache=false)
    puts "Beginning run at #{Time.zone.now.in_time_zone('Arizona')}"
    threads = []
    NewsSource.update_teddit_source
    sources.each(&:reload)
    sources.each do |source|
      thread = Thread.new do
        begin
          if Rails.env == 'production'
            ActiveStorage::Current.url_options = { protocol: 'https', host: 'newsfeedapi.ermacaz.com' }
          else
            ActiveStorage::Current.url_options = { protocol: 'http', host: 'localhost', port: '3001' }
          end
          puts source.name
          skip_scan = false
          # unless ((source.scan_interval.nil? || source.last_scanned_at.nil?) || (source.last_scanned_at + source.scan_interval.minutes < Time.zone.now))
          #   skip_scan = true
          # end
          next if  skip_scan || source.feed.nil?
          # we reverse so older stories are cached first
          source.feed.entries.first(NUM_STORIES).reverse.each do |entry|
            cached_story_keys = source.get_cached_story_keys
            story = {:source=>source.name.downcase.gsub(' ','_'), :pub_date=>(entry[:pubDate]&.to_i || entry[:published]&.to_i || DateTime.now&.to_i)}
            if source.name == 'AZ Central'
              story[:link] = entry[:feedburner_origLink].encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe
            else
              # story[:link] = entry[:link].encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe.gsub(NewsSource::TEDDIT_URL,'reddit.com')
              story[:link] = entry[:link].encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe.gsub('reddit.com', NewsSource::TEDDIT_URL)
            end
            link_hash = Digest::MD5.hexdigest story[:link]
            if !nocache && cached_story_keys.include?(link_hash)
              story = source.get_cached_story(link_hash)
            else
              story[:title] = CGI.unescapeHTML(entry[:title].force_encoding('utf-8').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').gsub('&quot;', '"')).html_safe
              case source.name
              when 'AZ Central'
                article = Nokogiri.HTML(entry[:content_encoded])
              when 'NHK EasyNews'
                article = nil
              else
                article = Nokogiri.HTML(HTTParty.get(story[:link], :headers=>{'User-agent'=>'ermacaz'}).body)
              end
              if source.name == 'Google News'
                #capture real article from redirect page
                real_link = article.css('a').first.attribute('href').value
                article = Nokogiri.HTML(HTTParty.get(real_link, :headers=>{'User-agent'=>'ermacaz'}).body)
              end
              img_src = nil
              case source.name
              when 'Ars Technica'
                img_src = (Nokogiri.HTML(CGI.unescapeHTML(entry[:content_encoded])).xpath('//img').attribute('src').to_s rescue nil)
                parts = (article.css('.article-content').first.xpath("//p").map(&:content).drop(4) rescue [])
                comment_part = parts.select {|a| a.match?(/^You must login or create an account to comment/)}.first
                if comment_part # everything here and after is removable
                  index = parts.index(comment_part)
                  parts = parts.reverse.drop(parts.length-index).reverse
                end
              when "Hacker News", "Google News"
                img_src = article.xpath("//img")&.first&.attribute('src')&.to_s
                if img_src&.match?(/^\//)
                  img_src = nil
                end
                img_src = img_src_filter(img_src)
              when "Just One Cookbook"
                if entry[:content]
                  img_src = (Nokogiri.HTML(entry[:content]).xpath('//img').first.attr('src').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe rescue nil)
                else
                  img_src = (Nokogiri.HTML(entry[:description]).xpath('//img').first.attr('src').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe rescue nil)
                end
                # img_src = (Nokogiri.HTML(entry[:description]).xpath('//img').first.attr('src').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe rescue nil)
                story[:description] =  CGI.unescapeHTML((Nokogiri.HTML(entry[:description]).xpath("//p")[1].content.truncate(1000).encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe rescue nil))
              when "Kotaku"
                story[:description] =  CGI.unescapeHTML((Nokogiri.HTML(entry[:description]).xpath("//p").first.content.truncate(1000).encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe rescue nil))
                img_src = (Nokogiri.HTML(CGI.unescapeHTML(entry[:description])).xpath('//img').attribute('src').to_s rescue nil)
              when 'New York Times'
                img_src = entry[:media_content_url]
              when 'NHK'
                story[:description] = CGI.unescapeHTML(entry[:description].truncate(1000).gsub(' ', '  ').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe)
                img_src = (source.url + article.xpath("//img").first.attribute('data-src').to_s rescue nil)
                img_src = nil if img_src&.match?(/noimg_default/)
                if img_src&.match?(/^\//)
                  img_src = source.url + img_src
                end
                img_src = img_src_filter(img_src)
              when 'NHK EasyNews'
                story[:title] = story[:title].gsub(/^\[\d\d\/\d\d\/\d\d\d\d\]/, '').strip
              when 'No Recipes'
                story[:description] =  CGI.unescapeHTML((Nokogiri.HTML(entry[:description]).xpath("//p").first.content.truncate(1000).encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe rescue nil))
                img_src = article.xpath("//img")[5]&.attribute('src')&.to_s
                if img_src&.match?(/^\//)
                  img_src = source.url + img_src
                end
                img_src = img_src_filter(img_src)
              when 'PC GAMER'
                parts = article.css('#article-body').first.xpath("//p").map(&:content).map {|a| a.gsub('(opens in new tab)','')}
              when 'Phoenix New Times'
                img_src = (Nokogiri.HTML(CGI.unescapeHTML(entry[:description])).xpath('//img').attribute('src').to_s rescue nil)
                parts = article.css('.fdn-content-body').first.content.strip.split("\n\n")
              when 'Reddit'
                # post_type = article.css('shreddit-post').attribute('post-type').value
                # case post_type
                # when 'gallery'
                #   img_src = article.css('gallery-carousel img').first.attribute('src').value
                #   img = process_img(img_src, link_hash)
                #   if img
                #     story[:media_url_thumb] = img.thumb_url
                #     story[:media_url]       = img.story_image_url
                #     story[:content] = img.story_image_url
                #   end
                # when 'image'
                #   img_src = article.css('shreddit-post img').first.attribute('src').value
                #   img = process_img(img_src, link_hash)
                #   if img
                #     story[:media_url_thumb] = img.thumb_url
                #     story[:media_url]       = img.story_image_url
                #     story[:content] = img.story_image_url
                #   end
                # when 'video'
                #   j = (JSON.parse article.css('shreddit-player').attribute('packaged-media-json').value rescue nil)
                #   if j
                #     video_src = j['playbackMp4s']['permutations'].last['source']['url']
                #     filename = "#{link_hash}.mp4"
                #     unless story_video = StoryVideo.where(:link_hash=>link_hash, :filename=>filename).first
                #       v = URI.open(video_src, 'User-Agent'=>'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36')
                #       story_video =  StoryVideo.create_and_upload!(io: v, filename: filename, :link_hash=>link_hash)
                #       story[:content] = story_video.url
                #       story[:media_url_thumb] = story_video.preview(resize_to_limit: [StoryImage::THUMB_WIDTH, nil]).processed.url
                #     end
                #   else #text
                #     story[:content] = entry[:content].gsub('&lt;!-- SC_OFF --&gt;&lt;div class=&quot;md&quot;&gt;&lt;p&gt;','').gsub(/&lt;\/p&gt; &lt;\/div&gt;&lt;!-- SC_ON.*/, '')
                #   end
                # # teddit format
                if article.css('#post')&.first&.css('.image')&.first
                  story[:content] = ("https://#{NewsSource::TEDDIT_URL}" + Nokogiri.HTML(article.css('#post').first.css('.image').first.inner_html).xpath('//a').first.attribute('href').to_s rescue nil)
                  img_src = story[:content]
                elsif article.css('#post')&.first&.css('.video')&.first
                  filepath = (Nokogiri.HTML(article.css('#post').first.css('.video').first.inner_html).xpath('//a').first.attribute('href').to_s rescue nil)
                  if filepath
                    v =  URI.open(("https://#{NewsSource::TEDDIT_URL}" + filepath), 'User-Agent'=>'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36')
                    filename = "#{link_hash}.#{filepath.match(/\.(.*)$/)[1]}"
                    unless story_video = StoryVideo.where(:link_hash=>link_hash, :filename=>filename).first
                      story_video =  StoryVideo.create_and_upload!(io: v, filename: filename, :link_hash=>link_hash)
                    end
                    story[:content] = story_video.url
                    story[:media_url_thumb] = story_video.preview(resize_to_limit: [StoryImage::THUMB_WIDTH, nil]).processed.url
                  else
                    story[:content] = ("https://#{NewsSource::TEDDIT_URL}" + Nokogiri.HTML(article.css('#post').first.css('.video').first.inner_html).xpath('//a').first.attribute('href').to_s rescue nil)
                  end
                elsif article.css('.usertext-body').first
                  story[:content] = (article.css('.usertext-body').first.content.split("\n\n") rescue nil)
                end
              when 'Slashdot'
                parts = article.css('.body').first.content.strip.split("\n\n")
                img_src = article.xpath("//img")&.first&.attribute('src')&.to_s.gsub(/^\/\//,'https://')
                img_src = img_src_filter(img_src)
              when 'Smithsonian'
                img_src = article.xpath("//img").compact.select {|a| a.attribute('src')&.to_s&.match?(/jpe?g$/)}.first.attribute('src')
                unless img_src
                  img_src = (article.xpath("//img").compact[2]&.attribute('src')&.to_s.split(")/")[1] rescue nil)
                end
                if img_src&.to_s&.match?(/^\//)
                  img_src = source.url + img_src
                end
                img_src = img_src_filter(img_src)
              when 'The Verge'
                img_src = (Nokogiri.HTML(CGI.unescapeHTML(entry[:content])).xpath('//img').attribute('src').to_s rescue nil)
                story[:description] = (Nokogiri.HTML(CGI.unescapeHTML(entry[:content])).to_s.gsub(/(<([^>]+)>)/i, '').gsub(/\s/, ' ').strip rescue nil)
              when 'Washington Post'
                img_elem = article.xpath("//img").reject {|v| v.attribute('src')&.value&.match(/authors/)}.first
                img_src = (img_elem&.attribute('src')&.to_s rescue nil)
                unless img_src.present?
                  if srcset =  img_elem&.attribute('srcset')
                    img_src = srcset.to_s&.split(', ')&.last&.split(' ')&.first
                  end
                end
              end
              if story[:description].blank? && entry[:description].present?
                unless source.name.match?(/Google|Slashdot|Hacker|Reddit|Verge|EasyNews/)
                  story[:description] =  CGI.unescapeHTML(entry[:description].truncate(1000).encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').html_safe)
                end
              end
              unless img_src || source.name == 'Hacker News'
                if entry[:media_content_url].present?
                  img_src = entry[:media_content_url]
                elsif entry[:media_thumbnail_url].present?
                  img_src = entry[:media_thumbnail_url]
                elsif entry[:content_encoded].present?
                  img_src = (Nokogiri.parse(entry[:content_encoded])&.xpath("//img")&.first&.attribute('src')&.to_s rescue nil)
                end
                if img_src.blank? && article
                  img_src = article.xpath("//img")&.first&.attribute('src')&.to_s
                  if img_src&.match?(/^\//)
                    img_src = source.url + img_src
                  end
                  img_src = img_src_filter(img_src)
                end
              end
              if img_src&.strip&.present?
                story_image = process_img(img_src, link_hash)
                if story_image
                  story[:media_url_thumb] = story_image.thumb_url
                  story[:media_url]       = story_image.story_image_url
                elsif img_src.present?
                  story[:media_url_thumb] = story[:media_url] = img_src
                end
              end
              if story[:content].blank? && article  && source.name != 'Reddit'
                unless defined?(parts) && parts
                  if article.xpath("//article").any?
                    parts = (article.xpath("//article").first.xpath('//p').map(&:content) rescue article.xpath("//article").first.content.split("\n\n"))
                  else
                    parts = article.xpath('//p').map(&:content)
                  end
                end
                parts = parts.map(&:strip).reject(&:blank?).reject {|a| a.length < 5 || a.match?(/^PC Gamer is part of Future US Inc|^PC Gamer is supported by its audience|Future US, Inc. Full 7th Floor|^Advertisement$|^Supported by$|^Send any friend a story$|^Follow Al Jazeera|^Sponsor Message|^Sign in|First Look Institute|^Credit\.\.\.$|^Photographs by|10 gift articles to give each month/)}
                story[:content] = parts if parts.any?
              end
            end
            story[:cache_time] = Time.now.to_i
            REDIS.hset(source.cache_key, link_hash=>story.to_json)
            REDIS.sadd?("newsfeed_caches", source.cache_key)
          end
          source.update!(:last_scanned_at=>Time.zone.now)
          puts "#{source.name} complete"
        rescue Exception=>e
          puts e
          puts e.backtrace.select {|a| a.match?(/newsfeed/i)}.inspect
        end
      end
      thread.report_on_exception = false
      threads << thread
    end
    threads.each(&:join)
    puts "after thread join"
    index_data = NewsSource.update_index_cache
    # REDIS.call("SET", "newsfeed", set.to_json)
    # remove any stores not found when researching
    # REDIS.multi do |r|
    #   current_cached_stores.each do |link_hash| 
    #     r.hdel("newsfeed_cached_stories", link_hash)
    #     StoryImage.find_by_link_hash(link_hash)&.purge
    #   end
    # end
    # ActionCable.server.broadcast 'news_sources_channel', index_data
    return true
  end
  
  def img_src_filter(img_src)
    img_src = img_src&.to_s
    if img_src&.match?(/favicon/) || !img_src&.match?(/png|jpg|jpeg|gif|webp|webm/)
      img_src = nil
    end
    img_src
  end
  
  def process_img(img_src, link_hash)
    begin
      unless story_image = StoryImage.find_by_link_hash(link_hash)
        img = URI.open(img_src, 'User-Agent'=>'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36')
        case img_src
        when /\.jpe?g/i
          filename = "#{link_hash}.jpg"
        when /\.png/
          filename = "#{link_hash}.png"
        when /\.gif/
          filename = "#{link_hash}.gif"
        else
          filename = "#{link_hash}.jpg"
        end
        story_image = StoryImage.create_and_upload!(io: img, filename: filename, :link_hash=>link_hash)
        story_image.create_image_variants
      end
      story_image
    rescue Exception=>e
      Rails.logger.warn("unable to grab image at #{img_src}")
      Rails.logger.warn(e.message)
      Rails.logger.warn e.backtrace.select {|a| a.match?(/newsfeed/)}.inspect
      puts "unable to grab image at #{img_src}"
      puts e.message
      puts e.backtrace.select {|a| a.match?(/newsfeed/)}.inspect
    end
  end
end
