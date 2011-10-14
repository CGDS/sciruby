class Vector
  def to_sv
    SparseVector.elements(self.to_a)
  end
end