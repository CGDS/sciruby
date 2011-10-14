class Matrix
  def to_sm
    SparseMatrix.rows(self.to_a)
  end
end