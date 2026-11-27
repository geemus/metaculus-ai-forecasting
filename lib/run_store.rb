# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

# Durable store for pipeline run records (see RunRecord), keyed by
# S3-style paths:
#
#   runs/{post_id}/{recorded_at}-{run_id}.json
#
# Records are immutable and append-only: every run writes a new key and no key
# is ever rewritten, so concurrent jobs never conflict and the layout copies
# unchanged between backends (a local directory, a git branch, S3).
#
# This is the local-filesystem backend. CI writes here, then the workflow
# copies the directory to S3 with the AWS CLI, which keeps AWS credentials and
# SDKs out of the Ruby code. Readers (the retro, a front-end build) sync the
# bucket down to a local directory and read it through the same interface.
class RunStore
  DEFAULT_ROOT = './tmp/run_store'

  attr_reader :root

  def initialize(root: ENV.fetch('RUN_STORE_DIR', DEFAULT_ROOT))
    @root = root
  end

  # Key for one run of one post. recorded_at sorts lexically, so listing a
  # post's prefix returns its runs oldest first.
  def self.run_key(post_id, recorded_at:, run_id:)
    stamp = recorded_at.utc.strftime('%Y%m%dT%H%M%SZ')
    "runs/#{post_id}/#{stamp}-#{run_id}.json"
  end

  # Write a record. Raises if the key already exists, since records are
  # immutable; a collision means two runs got the same id.
  def put(key, data)
    path = path_for(key)
    raise ArgumentError, "RunStore key already exists: #{key}" if File.exist?(path)

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(data))
    key
  end

  def get(key)
    JSON.parse(File.read(path_for(key)))
  end

  # Keys under prefix, sorted.
  def list(prefix = '')
    Dir.glob(File.join(root, prefix, '**', '*.json'))
       .map { |path| path.delete_prefix("#{root}/") }
       .sort
  end

  private

  def path_for(key)
    raise ArgumentError, "invalid RunStore key: #{key}" if key.start_with?('/') || key.split('/').include?('..')

    File.join(root, key)
  end
end
