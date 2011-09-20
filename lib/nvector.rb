require 'delegate'

delegate_class = 
  if Kernel.const_defined('NArray')
    # thinking of version 0.5.X
    require 'nvector/narray05'
    Nvector::NArray05
  else
    require 'nvector/ruby'
    Nvector::Ruby
  end

class Nvector < DelegateClass(delegate_class)
  def initialize(*args, &block)
    super(*args, &block)
  end
end

