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

    class Tag < Struct.new(:data_type, :raw_data_type, :bytes, :small)
      include Packable

      DATA_TYPE_OPTS = BYTES_OPTS = {:bytes => 4, :signed => false}
      LENGTH = DATA_TYPE_OPTS[:bytes] + BYTES_OPTS[:bytes]

      ## TODO: TEST WRITE.
      def write_packed packedio, options
        packedio << [data_type, DATA_TYPE_OPTS] << [bytes, BYTES_OPTS]
      end

      def small?
        self.bytes > 0 && self.bytes <= 4
      end

      def size
        small? ? 4 : 8
      end

      def read_packed packedio, options
        self.raw_data_type = packedio.read([Integer, DATA_TYPE_OPTS.merge(options)])

        upper, lower = self.raw_data_type >> 16, self.raw_data_type & 0xFFFF # Borrowed from a SciPy patch
        if upper > 0 # Small data element format
          raise(IOError, "Small data element format indicated, but length is more than 4 bytes!") if upper > 4
          self.bytes          = upper
          self.raw_data_type  = lower
        else
          self.bytes         = packedio.read([Integer, BYTES_OPTS.merge(options)])
        end
        self.data_type = MatFileReader::MDTYPES[self.raw_data_type]
      end

      def inspect
        "#<#{self.class.to_s} data_type=#{data_type}[#{raw_data_type}][#{raw_data_type.to_s(2)}] bytes=#{bytes} size=#{size}#{small? ? ' small' : ''}>"
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
        
        ir = row_index
        jc = column_index

        mat = {}
        (0...dimensions[1]).each do |j|
          p_0 = jc[j]
          p_n = jc[j+1]-1

          (p_0..p_n).each do |p|
            mat[j] ||= {}
            mat[j][ir[p]] = complex ? Complex(real_part[p], imaginary_part[p]) : real_part[p]
          end
        end

        SparseMatrix.send(:new, mat, dimensions[1], dimensions[0]).transpose
      end

      def read_packed packedio, options
        flags_class, self.nonzero_max = packedio.read([Element, options]).data

        self.matlab_class   = MatFileReader::MCLASSES[flags_class % 16]
        #STDERR.puts "Matrix class: #{self.matlab_class}"
        
        self.logical        = (flags_class >> 8) % 2 == 1 ? true : false
        self.global         = (flags_class >> 9) % 2 == 1 ? true : false
        self.complex        = (flags_class >> 10) % 2 == 1 ? true : false
        #STDERR.puts "nzmax: #{self.nonzero_max}"

        dimensions_tag_data = packedio.read([Element, options])
        self.dimensions     = dimensions_tag_data.data
        #STDERR.puts "dimensions: #{self.dimensions}"

        begin
          name_tag_data       = packedio.read([Element, options])
          self.matlab_name    = name_tag_data.data.is_a?(Array) ? name_tag_data.data.collect { |i| i.chr }.join('') : name_tag_data.data.chr
        rescue ElementDataIOError => e
          STDERR.puts "ERROR: Failure while trying to read Matlab variable name: #{name_tag_data.inspect}"
          STDERR.puts "Element Tag:"
          STDERR.puts "    #{e.tag}"
          STDERR.puts "Previously, I read these dimensions:"
          STDERR.puts "    #{dimensions_tag_data.inspect}"
          STDERR.puts "Unpack options were: #{options.inspect}"
          raise(e)
        end

        #STDERR.puts [flags_class.to_s(2), self.complex, self.global, self.logical, nil, self.mclass, self.nonzero_max].join("\t")
        if self.matlab_class == :mxCELL
          # Read what may be a series of matrices
          self.cells = []
          STDERR.puts("Warning: Cell array does not yet support reading multiple dimensions") if dimensions.size > 2 || (dimensions[0] > 1 && dimensions[1] > 1)
          number_of_cells = dimensions.inject(1) { |prod,i| prod * i }
          number_of_cells.times { self.cells << packedio.read([Element, options]) }
        else
          if self.matlab_class == :mxSPARSE

            row_index_tag_data = packedio.read([Element, options])
            col_index_tag_data = packedio.read([Element, options])

            self.row_index, self.column_index = row_index_tag_data.data, col_index_tag_data.data
            # STDERR.puts "row and col indeces: #{self.row_index.size}, #{self.column_index.size}"
          end

          real_part_tag_data = packedio.read([Element, options])
          self.real_part     = real_part_tag_data.data

          if self.complex
            i_part_tag_data  = packedio.read([Element, options])
            self.imaginary_part = i_part_tag_data.data
          end
        end

      end

      def ignore_padding packedio, bytes
        packedio.read([Integer, {:unsigned => true, :bytes => bytes}]) if bytes > 0
      end
    end

    class ElementDataIOError < IOError
      def initialize tag=nil, msg=nil
        @tag = tag
        super msg
      end

      def to_s
        @tag.inspect + "\n" + super
      end
      attr_reader :tag
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
        #STDERR.puts self.tag.inspect

        raise(ElementDataIOError.new(tag, "Unrecognized Matlab type #{tag.raw_data_type}")) if data_type.nil?

        if tag.bytes == 0
          self.data = []
        else
          number_of_reads = data_type[1].has_key?(:bytes) ? tag.bytes / data_type[1][:bytes] : 1
          data_type[1].merge!({:endian => options[:endian]})

          if number_of_reads == 1
            self.data = packedio.read(data_type)
          else
            self.data = begin
              ary = []; number_of_reads.times do
                ary << packedio.read(data_type)
              end
              ary
            end
          end
          begin
            ignore_padding(packedio, (tag.bytes + tag.size) % 8) unless [:miMATRIX, :miCOMPRESSED].include?(tag.data_type)
          rescue EOFError
            STDERR.puts self.tag.inspect
            raise(ElementDataIOError.new(tag, "Ignored too much"))
          end
        end
      end

      def ignore_padding packedio, bytes
        if bytes > 0
          #STDERR.puts "Ignored #{8 - bytes} on #{self.tag.data_type}"
          ignored = packedio.read(8 - bytes)
          ignored_unpacked = ignored.unpack("C*")
          raise(IOError, "Nonzero padding detected: #{ignored_unpacked}") if ignored_unpacked.any? { |i| i != 0 }
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