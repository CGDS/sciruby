# Added by John Woods. Experimental.
#

require_relative "./mat_file_reader.rb"

module SciRuby::IO::Matlab
  # Reader (and eventual writer) for a version 5 .mat file.
  class MatFile5Reader < MatFileReader
    class Header < Struct.new(:desc, :data_offset, :version, :endian)

      include Packable

      BYTE_ORDER_LENGTH   = 2
      DESC_LENGTH         = 116
      DATA_OFFSET_LENGTH  = 8
      VERSION_LENGTH      = 2
      BYTE_ORDER_POS      = 126

      ## TODO: TEST WRITE.
      def write_packed packedio, options
        packedio << [desc, {:bytes => DESC_LENGTH}] << [data_offset, {:bytes => DATA_OFFSET_LENGTH}] << [version, {:bytes => VERSION_LENGTH}] << [byte_order, {:bytes => BYTE_ORDER_LENGTH}]
      end

      def read_packed packedio, options
        self.desc, self.data_offset, self.version, self.endian = packedio >>
            [String, {:bytes => DESC_LENGTH}] >>
            [String, {:bytes => DATA_OFFSET_LENGTH}] >>
            [Integer, {:bytes => VERSION_LENGTH, :endian => options[:endian]}] >>
            [String, {:bytes => 2}]
        self.desc.strip!
        self.data_offset.strip!; self.data_offset = nil if self.data_offset.empty?
        self.endian == 'IM' ? :little : :big
      end
    end

    class Tag < Struct.new(:data_type, :raw_data_type, :bytes)
      include Packable

      DATA_TYPE_OPTS = BYTES_OPTS = {:bytes => 4, :signed => false}
      LENGTH = DATA_TYPE_OPTS[:bytes] + BYTES_OPTS[:bytes]

      ## TODO: TEST WRITE.
      def write_packed packedio, options
        packedio << [data_type, DATA_TYPE_OPTS] << [bytes, BYTES_OPTS]
      end

      def read_packed packedio, options
        self.raw_data_type, self.bytes = packedio >> [Integer, DATA_TYPE_OPTS.merge(options)] >> [Integer, BYTES_OPTS.merge(options)]
        self.data_type = MatFileReader::MDTYPES[self.raw_data_type]
      end

      def inspect
        "#<#{self.class.to_s} data_type=#{data_type}[#{raw_data_type}][#{raw_data_type.to_s(2)}] bytes=#{bytes}>"
      end
    end


    class MatrixData < Struct.new(:cells, :logical, :global, :complex, :nonzero_max, :matlab_class, :dimensions, :matlab_name, :real_part, :imaginary_part, :row_index, :column_index)
      include Packable

      def write_packed packedio, options
        raise(NotImplementedError)
        packedio << [info, {:bytes => padded_bytes}.merge(options)]
      end

      def to_ruby
        case matlab_class
          when :mxSPARSE
            return to_sparse_matrix
          when :mxCELL
            return self.cells.collect { |c| c.to_ruby }
          else
            return to_matrix
        end
      end

      def to_matrix
        return to_sparse_matrix if matlab_class == :mxSPARSE
        raise(NotImplementedError, "Only supports two dimensions or less, currently") if dimensions.size > 2
        Matrix.build(*dimensions) do |row, col|
          self.complex ? Complex(real_part[dimensions[1]*col + row], imaginary_part[dimensions[1]*col + row]) : real_part[dimensions[1]*col + row]
        end
      end

      def to_sparse_matrix
        raise(NotImplementedError, "Only supports two dimensions or less, currently") if dimensions.size > 2
        return to_matrix.to_sparse_matrix unless matlab_class == :mxSPARSE # Read as matrix first
        SparseMatrix.build(*dimensions) do |i, j|
          ir = row_index
          jc = column_index

          # http://www.unc.edu/depts/case/BMELIB/apiguide.pdf
          # See top of page 1-6.
          if i >= jc[j] && i < jc[j+1]
            self.complex ? Complex(real_part[jc[j]], imaginary_part[jc[j]]) : real_part[jc[j]]
          else
            0
          end
        end
      end

      def read_packed packedio, options
        flags_class, self.nonzero_max = packedio.read([Element, options]).data

        self.matlab_class   = MatFileReader::MCLASSES[flags_class % 16]
        #STDERR.puts "Matrix class: #{self.matlab_class}"
        
        self.logical        = (flags_class >> 8) % 2 == 1 ? true : false
        self.global         = (flags_class >> 9) % 2 == 1 ? true : false
        self.complex        = (flags_class >> 10) % 2 == 1 ? true : false

        dimensions_tag_data = packedio.read([Element, options])
        self.dimensions     = dimensions_tag_data.data
        ignore_padding(packedio, dimensions_tag_data.tag.bytes % 8) # Read padding on dimensions
        #STDERR.puts "dimensions: #{self.dimensions}"

        name_tag_data       = packedio.read([Element, options])
        self.matlab_name    = name_tag_data.data.collect { |i| i.chr }.join('')
        ignore_padding(packedio, (name_tag_data.tag.bytes + 4) % 8) unless self.matlab_name.size == 0 # Read padding on name

        #STDERR.puts [flags_class.to_s(2), self.complex, self.global, self.logical, nil, self.mclass, self.nonzero_max].join("\t")
        if self.matlab_class == :mxCELL
          # Read what may be a series of matrices
          self.cells = []
          STDERR.puts("Warning: Cell array does not yet support reading multiple dimensions") if dimensions.size > 2 || (dimensions[0] > 1 && dimensions[1] > 1)
          number_of_cells = dimensions.inject(1) { |prod,i| prod * i }
          number_of_cells.times { self.cells << packedio.read([Element, options]) }
        else
          if self.matlab_class == :mxSPARSE
            # STDERR.puts "nzmax: #{self.nonzero_max}"
            row_index_tag_data = packedio.read([Element, options])
            ignore_padding(packedio, row_index_tag_data.tag.bytes % 8)
            col_index_tag_data = packedio.read([Element, options])
            ignore_padding(packedio, col_index_tag_data.tag.bytes % 8)

            self.row_index, self.column_index = row_index_tag_data.data, col_index_tag_data.data
            #STDERR.puts "row and col indeces: #{self.row_index.inspect}, #{self.column_index.inspect}"
          end

          real_part_tag_data = packedio.read([Element, options])
          self.real_part     = real_part_tag_data.data
          ignore_padding(packedio, real_part_tag_data.tag.bytes % 8) # Read padding on real part

          if self.complex
            i_part_tag_data  = packedio.read([Element, options])
            self.imaginary_part = i_part_tag_data.data
            ignore_padding(packedio, i_part_tag_data.tag.bytes % 8)
          end
        end

      end

      def ignore_padding packedio, bytes
        packedio.read([Integer, {:unsigned => true, :bytes => bytes}]) if bytes > 0
      end
    end

    class Element < Struct.new(:tag, :data)
      include Packable

      def write_packed packedio, options
        packedio << [tag, {}] << [data, {}]
      end

      def read_packed packedio, options
        raise(ArgumentError, "Missing mandatory option :endian") unless options.has_key?(:endian)
        tag = packedio.read([Tag, {:endian => options[:endian]}])
        #STDERR.puts tag.inspect
        data_type = MDTYPE_UNPACK_ARGS[tag.data_type]

        self.tag = tag

        raise(TypeError, "Unrecognized Matlab type #{tag.data_type}") if data_type.nil?
        if tag.bytes > 0
          number_of_reads = data_type[1].has_key?(:bytes) ? tag.bytes / data_type[1][:bytes] : 1

          data_type[1].merge!({:endian => options[:endian]})
          #STDERR.puts "Read #{data_type.inspect} #{number_of_reads} times"

          self.data = begin # data may consist of multiple values
            ary = []
            number_of_reads.times do
              ary << packedio.read(data_type)
            end
            number_of_reads == 1 ? ary[0] : ary
          end
        else
          #STDERR.puts "tag bytes = 0"
          self.data = []
        end
      end

      def to_ruby
        data.to_ruby
      end
    end

    class Compressed
      include Packable
      # include TaggedDataEnumerable

      def initialize stream = nil, byte_order = nil, content_or_bytes = nil
        @stream = stream
        @byte_order = byte_order
        if content_or_bytes.is_a?(String)
          @content = content_or_bytes
        elsif content_or_bytes.is_a?(Fixnum)
          @padded_bytes = content_or_bytes
        #else
        #  raise(ArgumentError, "Need a content string or a number of bytes; content_or_bytes is #{content_or_bytes.class.to_s}")
        end
      end
      attr_reader :byte_order

      def compressed
        @compressed ||= Zlib::Deflate.deflate(content) # [2..-5] removes headers
      end

      def content
        @content ||= extract
      end

      def padded_bytes
        @padded_bytes ||= content.size % 4 == 0 ? content.size : (content.size / 4 + 1) * 4
      end

      def write_packed packedio, options
        packedio << [compressed, {:bytes => padded_bytes}.merge(options)]
      end

      def read_packed packedio, options
        @compressed = (packedio >> [String, options]).first
        content
      end

    protected
      def extract
        zstream = Zlib::Inflate.new #(-Zlib::MAX_WBITS) # No header
        buf = zstream.inflate(@compressed)
        zstream.finish
        zstream.close
        buf
      end
    end

    MDTYPE_UNPACK_ARGS = MatFileReader::MDTYPE_UNPACK_ARGS.merge({
      :miCOMPRESSED => [Compressed, {}],
      :miMATRIX     => [MatrixData, {}]
    })
    # include TaggedDataEnumerable

    FIRST_TAG_FIELD_POS = 128

    attr_reader :file_header, :first_tag_field, :first_data_field

    def initialize stream, options = {}
      super(stream, options)
      @file_header = seek_and_read_file_header
    end

    def to_a
      ary = []
      self.each do |element|
        ary << element
      end
      ary
    end

    def to_ruby
      ary = to_a
      return ary.first.to_ruby if ary.size == 1
      ary.collect { |item| item.to_ruby }
    end

    def guess_byte_order
      stream.seek(Header::BYTE_ORDER_POS)
      mi = stream.read(Header::BYTE_ORDER_LENGTH)
      stream.seek(0)
      mi == 'IM' ? :little : :big
    end

    def seek_and_read_file_header
      stream.seek(0)
      stream.read(FIRST_TAG_FIELD_POS).unpack(Header, {:endian => byte_order})
    end

    def each &block
      stream.each(Element, {:endian => byte_order}) do |element|
        if element.data.is_a?(Compressed)
          StringIO.new(element.data.content, "rb+").each(Element, {:endian => byte_order}) do |compressed_element|
            yield compressed_element.data
          end
        else
          yield element.data
        end
      end
      stream.seek(FIRST_TAG_FIELD_POS) # Go back to the beginning in case we want to do it again.
      self
    end

  end
end