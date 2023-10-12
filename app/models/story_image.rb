class StoryImage < ActiveStorage::Blob
  
  THUMB_WIDTH = 200
  STORY_WIDTH = 800
  
  default_scope { where(:media_type=>:image )}
  
  before_create :set_media_type
  def set_media_type
    self.media_type = :image
  end
  
  def self.create_and_upload!(key: nil, io:, filename:, content_type: nil, metadata: nil, service_name: nil, identify: true, record: nil, link_hash: nil)
    create_after_unfurling!(key: key, io: io, filename: filename, content_type: content_type, metadata: metadata, service_name: service_name, identify: identify, link_hash: link_hash).tap do |blob|
      blob.upload_without_unfurling(io)
    end
  end
  
  def self.create_after_unfurling!(key: nil, io:, filename:, content_type: nil, metadata: nil, service_name: nil, identify: true, record: nil, link_hash: nil) # :nodoc:
    build_after_unfurling(key: key, io: io, filename: filename, content_type: content_type, metadata: metadata, service_name: service_name, identify: identify, link_hash: link_hash).tap(&:save!)
  end
  
  def self.build_after_unfurling(key: nil, io:, filename:, content_type: nil, metadata: nil, service_name: nil, identify: true, record: nil, link_hash: nil) # :nodoc:
    new(key: key, filename: filename, content_type: content_type, metadata: metadata, service_name: service_name, link_hash: link_hash).tap do |blob|
      blob.unfurl(io, identify: identify)
    end
  end
  
  def create_image_variants
    self.variant(:resize_to_limit=>[STORY_WIDTH,nil]).processed
    self.variant(:resize_to_limit=>[THUMB_WIDTH,nil]).processed
  end
  
  def story_image_url
    self.variant(resize_to_limit: [STORY_WIDTH, nil]).url
  end
  def thumb_url
    if Rails.env == 'production'
      ActiveStorage::Current.url_options = { protocol: 'https', host: 'newsfeedapi.ermacaz.com' }
    else
      ActiveStorage::Current.url_options = { protocol: 'http', host: 'localhost', port: '3001' }
    end
    self.variant(resize_to_limit: [THUMB_WIDTH, nil]).url
  end

end