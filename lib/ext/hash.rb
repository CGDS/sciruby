# Mostly based on github.com/hmcfletch/sparse-matrix

class Hash
  #
  # Assumes that self is a hash of hashes and transposes the rows and columns
  #
  def transpose
    h = {}
    self.each_pair do |j,h2|
      h2.each_pair do |i,v|
        h[i] ||= {}
        h[i][j] = v
      end
    end
    h
  end
end