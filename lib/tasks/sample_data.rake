namespace :db do
  desc 'Fill database with sources'
  task populate: :environment do
    Rake::Task["db:reset"].invoke
    begin
      REDIS.del("newsfeed_cached_stories")
    rescue Exception=>e
      puts e.message
    end
    NewsSource.create(name: 'Reddit',
                      url: 'https://reddit.com',
                      feed_url: "https://#{NewsSource::TEDDIT_URL}/?api&type=rss",
                      :scan_interval=>60)
    NewsSource.create(name: 'New York Times',
                      url: 'https://nytimes.com',
                      feed_url: 'http://feeds.feedburner.com/nytimes/QwEB')
    NewsSource.create(name: 'Washington Post',
                      url: "https://washingtonpost.com",
                      feed_url: "http://feeds.washingtonpost.com/rss/world")
    NewsSource.create(name: 'Google News',
                      url: 'https://news.google.com',
                      feed_url: 'https://news.google.com/?output=rss')
    NewsSource.create(name: 'NPR',
                      url: 'https://npr.org',
                      feed_url: 'https://feeds.npr.org/1001/rss.xml')
    NewsSource.create(name: 'The Intercept',
                      url: 'https://theintercept.com/',
                      feed_url: 'https://theintercept.com/feed/?lang=en')
    NewsSource.create(name: 'NHK',
                      url: 'https://www3.nhk.or.jp/',
                      feed_url: 'http://www3.nhk.or.jp/rss/news/cat0.xml')
    NewsSource.create(name: 'Al Jazeera',
                      url: 'https://www.aljazeera.com/',
                      feed_url: 'https://www.aljazeera.com/xml/rss/all.xml')
    # NewsSource.create(name: 'Huffington Post',
    #                   url: 'https://huffingtonpost.com',
    #                   feed_url: 'https://www.huffingtonpost.com/feeds/index.xml')
    NewsSource.create(name: 'AZ Central',
                      url: 'https://azcentral.com',
                      feed_url: "https://rssfeeds.azcentral.com/phoenix/travelandexplore&x=1;https://rssfeeds.azcentral.com/phoenix/dining&x=1;https://rssfeeds.azcentral.com/phoenix/events&x=1;https://rssfeeds.azcentral.com/phoenix/thingstodo&x=1;https://rssfeeds.azcentral.com/phoenix/thingstodo&x=1;http://rssfeeds.azcentral.com/phoenix/local&x=1",
                      multiple_feeds: true
    )
    NewsSource.create(name: 'Phoenix New Times',
                      url: 'https://www.phoenixnewtimes.com/',
                      feed_url: 'https://www.phoenixnewtimes.com/phoenix/Rss.xml')
    NewsSource.create(name: 'Slashdot',
                      url: 'https://slashdot.org',
                      feed_url: 'http://rss.slashdot.org/Slashdot/slashdot/to')
    NewsSource.create(name: 'Hacker News',
                      url: 'https://news.ycombinator.com',
                      feed_url: 'https://news.ycombinator.com/rss',
                      :scan_interval=>60)
    # NewsSource.create(name: 'Kotaku',
    #                   url: 'https://kotaku.com',
    #                   feed_url: 'https://kotaku.com/rss')
    NewsSource.create(name: 'PC GAMER',
                      url: 'https://www.pcgamer.com/',
                      feed_url: 'https://www.pcgamer.com/rss/')
    NewsSource.create(name: 'The Verge',
                      url: 'https://www.theverge.com',
                      feed_url: 'https://www.theverge.com/rss/frontpage')
    NewsSource.create(name: 'Ars Technica',
                      url: 'https://arstechnica.com',
                      feed_url: 'https://arstechnica.com/rss'
    )
    NewsSource.create(name: 'Smithsonian',
                      url: 'https://www.smithsonianmag.com',
                      feed_url: 'https://www.smithsonianmag.com/rss/latest_articles/'
    )
    NewsSource.create(name: 'No Recipes',
                      url: 'https://norecipes.com',
                      feed_url: 'https://norecipes.com/feed',
                      :scan_interval=>2000)
    NewsSource.create(name: 'Just One Cookbook',
                      url: 'https://www.justonecookbook.com',
                      feed_url: 'https://www.justonecookbook.com/rss',
                      :scan_interval=>2000)
    NewsSource.create(name: 'NHK EasyNews',
                      url: 'https://www3.nhk.or.jp/news/easy/index.html',
                      feed_url: 'https://www.reddit.com/r/NHKEasyNews/.rss',
                      :scan_interval=>500)
  end
end
