# frozen_string_literal: true

require "tempfile"

module Flipbook
  module Output
    module_function

    def open(writer_class, path, **options)
      target = File.expand_path(path)
      mode = File.exist?(target) ? File.stat(target).mode & 0o777 : 0o666 & ~File.umask
      io = Tempfile.new(".flipbook-", File.dirname(target))
      io.binmode
      writer = writer_class.new(io, **options)
      writer.instance_variable_set(:@owns_io, true)
      writer.instance_variable_set(:@target_path, target)
      writer.instance_variable_set(:@target_mode, mode)
      return writer unless block_given?

      yield writer
      writer.close
      path
    rescue Exception
      io&.close!
      raise
    end

    def finish(io, target, mode)
      io.close unless io.closed?
      File.chmod(mode, io.path)
      File.rename(io.path, target)
    rescue Exception
      io.close!
      raise
    end
  end
end
