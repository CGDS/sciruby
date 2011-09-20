
describe 'an Nvector', :shared do
  @some_size = 4
  @some_array = [4,5,6]
  describe 'a 1D Nvector' do
    describe 'initializing' do
      # subject = Nvector class
      it 'can be initialized with an array of integers' do
        pending 'working code'
        subject.new @some_array
        # gets passed to Nvector[]
      end
      it 'can be initialized with an integer to specify size (defaults to :float64)' do
        pending 'working code' 
        Nvector.new(@some_size).dtype == :float64
        # create a float64 Nvector of size 4
      end
      [:int32, :float64, :complex128].each do |tp|
        it "can be cast to a #{tp} with :dtype option (or last arg???)" do
          pending 'working code'
          # could also see this being the last arg, rather than hash...
          Nvector.new(4, :dtype => tp).dtype.should == tp
        end
      end
    end
    #{:int32 => 12, :float64 => 12.0, :complex128 => Complex.new(12,0) }.each do |tp, num|
    #  p tp
    #  p num
    #end
    #describe 'creating with Nvector[]' do
    #  describe 'choosing the highest type' do
    #    it 'becomes an :int32 if highest is Integer' do
    #      Nvector[3,4,5].dtype.should == :int32
    #    end
    #    it 'becomes a :float64 if highest is Float' do
    #      Nvector[3,4,5.0].dtype.should == :float64
    #    end
    #    it 'becomes a :complex128 if highest is Complex' do
    #      Nvector[3,4,Complex.new(5.0,0)].dtype.should == :complex128
    #    end
    #  end
    #end
    #subject { Nvector[4,5,6] }
  end

  #describe 'a 2D Nvector'
end
