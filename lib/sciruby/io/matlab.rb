# Added by John Woods. Experimental.
#

require_relative "matlab/mat_file_5_reader"

module SciRuby
  module IO
    # IO components for Matlab.
    module Matlab
      class << self
        # Attempt to convert a Matlab .mat file's contents to a Ruby object.
        #
        # EXPERIMENTAL. At this time, only supports version 5.
        #
        def load_mat file_path
          MatFile5Reader.new(File.open(file_path, "rb+")).to_ruby
        end
      end
    end
  end
end