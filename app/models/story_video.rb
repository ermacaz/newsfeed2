class StoryVideo < ActiveStorage::Blob
  
  default_scope { where(:media_type=>:video )}
  
  before_create :set_media_type
  def set_media_type
    self.media_type = :video
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
end