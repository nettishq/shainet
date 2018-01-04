require "logger"

module SHAInet
  alias CNN_layer = Conv_layer # | Relu_layer | Max_pool_layer | FC_layer

  # # layer types:
  # input(width, height ,channels = RGB)
  # conv(width, height ,filters = features)
  # relu - same volume as previous
  # pool(width, height ,filters = features) - reduces the width and height, usually max pool
  # dropout - randomly make some neurons activaton at 0 to force new pathways
  # fc(output = classes)- single vector that clasifies, fully conneted to previous layer

  class CNN
    getter :input_layers, :hidden_layers, :output_layers # , padding : Int32

    def initialize
      @input_layers = Array(CNN_input_layer).new
      @hidden_layers = Array(CNN_layer).new
      @output_layers = Array(Layer).new
    end

    def add_l_input(input_volume : Array(Int32))
      @input_layers << CNN_input_layer.new(input_volume)
    end

    def add_l_conv(input_volume : Array(Int32),
                   filters_num : Int32,
                   window_size : Int32,
                   stride : Int32,
                   padding : Int32 = 0)
      @hidden_layers << Conv_layer.new(input_volume, filters_num, window_size, stride, padding)
    end

    def run(input_data : Array(Array(Array(GenNum))))
      # Input the data into the first layer
      input_data.size.times do |channel|
        channel.times do |row|
          row.times do |col|
            @input_layers.first.neurons[channel][row][col].activation = input_data[channel][row][col]
          end
        end
      end

      # Activate all hidden layers one by one
      @hidden_layers.size.times do |l|
        if l == 0
          @hidden_layers[l].activate(@input_layers.last)
          # else
          #   @hidden_layers[l].activate(@hidden_layers[l - 1])
        end
      end
    end
  end

  class CNN_input_layer
    property :neurons
    getter :output

    def initialize(input_volume : Array(Int32))
      unless input_volume.size == 3
        raise CNNInitializationError.new("Input volume must be an array of Int32: [width, height, channels].")
      end

      unless input_volume[0] == input_volume[1]
        raise CNNInitializationError.new("Width and height of input must be of the same size.")
      end

      @neurons = Array(Array(Array(Neuron))).new(input_volume[2]) {
        Array(Array(Neuron)).new(input_volume[0]) {
          Array(Neuron).new(input_volume[1]) { Neuron.new("memory") }
        }
      }

      @output = Array(Array(Array(GenNum))).new(input_volume[2]) {
        Array(Array(GenNum)).new(input_volume[0]) { Array(GenNum).new(input_volume[1]) { 0.0 } }
      }
    end

    def activate(target : CNN_layer)
    end
  end

  class Conv_layer
    getter filters : Array(Filter), window_size : Int32, stride : Int32, padding : Int32, output : Array(Array(Array(Float64)))

    def initialize(input_volume : Array(Int32),
                   filters_num : Int32,
                   @window_size : Int32,
                   @stride : Int32,
                   @padding : Int32 = 0)
      raise CNNInitializationError.new("Padding value must be Int32 >= 0") if @padding < 0

      unless input_volume.size == 3
        raise CNNInitializationError.new("Input volume must be an array of Int32: [width, height, channels].")
      end

      output_surface = ((input_volume[0] - @window_size + 2*@padding)/@stride + 1)

      unless output_surface.class == Int32
        raise CNNInitializationError.new("Output volume must be a whole number, change: window size or stride or padding")
      end

      @filters = Array(Filter).new(filters_num) { Filter.new([input_volume[0], input_volume[1]], window_size) }

      @output = Array(Array(Array(Float64))).new(filters_num) {
        Array(Array(Float64)).new(output_surface) {
          Array(Float64).new(output_surface) { 0.0 }
        }
      }
    end

    def pad(input_data : Array(Array(Array(Neuron))))
      if @padding == 0
        return input_data
      else
        blank_neuron = Neuron.new("memory")
        padded_data = input_data
        padded_data.each do |channel|
          channel.each do |row|
            @padding.times { row << blank_neuron }
            @padding.times { row.insert(0, blank_neuron) }
          end
          padding_row = Array(Neuron).new(channel.first.size) { blank_neuron }
          @padding.times { channel << padding_row }
          @padding.times { channel.insert(0, padding_row) }
        end
        return padded_data
      end
    end

    # Use each filter to create feature map
    def activate(input_layer : CNN_input_layer | CNN_layer)
      padded_data = pad(input_layer.neurons)

      # padded_data = [[[0, 0, 0, 0, 0], [0, 1, 1, 1, 0], [0, 1, 1, 1, 0], [0, 1, 1, 1, 0], [0, 0, 0, 0, 0]],
      #                [[0, 0, 0, 0, 0], [0, 2, 2, 2, 0], [0, 2, 2, 2, 0], [0, 2, 2, 2, 0], [0, 0, 0, 0, 0]]]

      padded_data.size.times do |channel|
        @filters.each do |filter|
          input_x = input_y = output_x = output_y = 0

          # Zoom in on a small window out of the data matrix and update
          until input_y == (padded_data[channel].size - @stride - 1)
            until input_x == (padded_data[channel][input_y].size - @stride - 1)
              window = padded_data[channel][input_y..(input_y + @window_size - 1)].map { |m| m[input_x..(input_x + @window_size - 1)] }
              @output[channel][output_y][output_x] = filter.receptive_field.prpogate_forward(window, filter.neurons[output_y][output_x])
              puts "row: #{input_y} col: #{input_x} window: #{window.each { |r| puts r }}"
              input_x += @stride
              output_x += 1
            end
            input_x = output_x = 0
            input_y += @stride
            output_y += 1
          end
          puts "-------------"
        end
      end
    end
  end

  class Filter
    getter neurons : Array(Array(Neuron)), receptive_field : Receptive_field

    def initialize(input_surface : Array(Int32), window_size : Int32)
      @neurons = Array(Array(Neuron)).new(input_surface[1]) { Array(Neuron).new(input_surface[0]) { Neuron.new("memory") } }
      @receptive_field = Receptive_field.new(window_size)
    end
  end

  # This is somewhat similar to a synapse
  class Receptive_field
    property weights : Array(Array(Float64)), bias : Float64
    getter :window_size

    def initialize(@window_size : Int32)
      @weights = Array(Array(Float64)).new(@window_size) { Array(Float64).new(@window_size) { rand(0.0..1.0).to_f64 } }
      @bias = rand(-1..1).to_f64
    end

    # Takes a small window from the input data to preform feed forward
    def prpogate_forward(input_window : Array(Array(Neuron)), target_neuron : Neuron)
      weighted_sum = Float64.new(0)
      @weights.size.times do |row|
        @weights.size.times do |col|
          weighted_sum += input_window[row][col].activation*@weights[row][col]
        end
      end
      target_neuron.activation = weighted_sum + @bias
      return target_neuron.activation
    end

    def prpogate_backward
    end
  end

  # class Relu_layer
  # end

  # class Max_pool_layer
  # end

  # class Drop_out_layer
  # end

  # class FC_layer
  # end
end
