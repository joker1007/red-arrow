# Copyright 2017 Kouhei Sutou <kou@clear-code.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Arrow
  class Slicer
    def initialize(table)
      @table = table
    end

    def [](column_name)
      column = @table[column_name]
      return nil if column.nil?
      ColumnCondition.new(column)
    end

    def respond_to_missing?(name, include_private)
      return true if self[name]
      super
    end

    def method_missing(name, *args, &block)
      if args.empty?
        column_condition = self[name]
        return column_condition if column_condition
      end
      super
    end

    class Condition
      def evaluate
        message = "Slicer::Condition must define \#evaluate: #{inspect}"
        raise NotImplementedError.new(message)
      end

      def &(condition)
        AndCondition.new(self, condition)
      end

      def |(condition)
        OrCondition.new(self, condition)
      end

      def ^(condition)
        XorCondition.new(self, condition)
      end
    end

    class LogicalCondition < Condition
      def initialize(condition1, condition2)
        @condition1 = condition1
        @condition2 = condition2
      end

      def evaluate
        values1 = @condition1.evaluate.each
        values2 = @condition2.evaluate.each
        raw_array = []
        begin
          loop do
            value1 = values1.next
            value2 = values2.next
            if value1.nil? or value2.nil?
              raw_array << nil
            else
              raw_array << evaluate_value(value1, value2)
            end
          end
        rescue StopIteration
        end
        BooleanArray.new(raw_array)
      end
    end

    class AndCondition < LogicalCondition
      private
      def evaluate_value(value1, value2)
        value1 and value2
      end
    end

    class OrCondition < LogicalCondition
      private
      def evaluate_value(value1, value2)
        value1 or value2
      end
    end

    class XorCondition < LogicalCondition
      private
      def evaluate_value(value1, value2)
        value1 ^ value2
      end
    end

    class ColumnCondition < Condition
      def initialize(column)
        @column = column
      end

      def evaluate
        data = @column.data
        if data.n_chunks == 1
          array = data.get_chunk(0)
          if array.is_a?(BooleanArray)
            array
          else
            array.cast(BooleanDataType.new)
          end
        else
          raw_array = []
          data.each_chunk do |chunk|
            if chunk.is_a?(BooleanArray)
              boolean_array = chunk
            else
              boolean_array = chunk.cast(BooleanDataType.new)
            end
            boolean_array.each do |value|
              raw_array << value
            end
          end
          BooleanArray.new(raw_array)
        end
      end

      def !@
        NotColumnCondition.new(@column)
      end

      def null?
        self == nil
      end

      def ==(value)
        EqualCondition.new(@column, value)
      end

      def !=(value)
        NotEqualCondition.new(@column, value)
      end

      def <(value)
        LessCondition.new(@column, value)
      end

      def <=(value)
        LessEqualCondition.new(@column, value)
      end

      def >(value)
        GreaterCondition.new(@column, value)
      end

      def >=(value)
        GreaterEqualCondition.new(@column, value)
      end

      def select(&block)
        SelectCondition.new(@column, block)
      end

      def reject(&block)
        RejectCondition.new(@column, block)
      end
    end

    class NotColumnCondition < Condition
      def initialize(column)
        @column = column
      end

      def evaluate
        data = @column.data
        raw_array = []
        data.each_chunk do |chunk|
          if chunk.is_a?(BooleanArray)
            boolean_array = chunk
          else
            boolean_array = chunk.cast(BooleanDataType.new)
          end
          boolean_array.each do |value|
            if value.nil?
              raw_array << value
            else
              raw_array << !value
            end
          end
        end
        BooleanArray.new(raw_array)
      end

      def !@
        ColumnCondition.new(@column)
      end
    end

    class EqualCondition < Condition
      def initialize(column, value)
        @column = column
        @value = value
      end

      def !@
        NotEqualCondition.new(@column, @value)
      end

      def evaluate
        case @value
        when nil
          raw_array = @column.collect(&:nil?)
          BooleanArray.new(raw_array)
        else
          raw_array = @column.collect do |value|
            if value.nil?
              nil
            else
              @value == value
            end
          end
          BooleanArray.new(raw_array)
        end
      end
    end

    class NotEqualCondition < Condition
      def initialize(column, value)
        @column = column
        @value = value
      end

      def !@
        EqualCondition.new(@column, @value)
      end

      def evaluate
        case @value
        when nil
          raw_array = @column.collect do |value|
            not value.nil?
          end
          BooleanArray.new(raw_array)
        else
          raw_array = @column.collect do |value|
            if value.nil?
              nil
            else
              @value != value
            end
          end
          BooleanArray.new(raw_array)
        end
      end
    end

    class LessCondition < Condition
      def initialize(column, value)
        @column = column
        @value = value
      end

      def !@
        GreaterEqualCondition.new(@column, @value)
      end

      def evaluate
        raw_array = @column.collect do |value|
          if value.nil?
            nil
          else
            @value > value
          end
        end
        BooleanArray.new(raw_array)
      end
    end

    class LessEqualCondition < Condition
      def initialize(column, value)
        @column = column
        @value = value
      end

      def !@
        GreaterCondition.new(@column, @value)
      end

      def evaluate
        raw_array = @column.collect do |value|
          if value.nil?
            nil
          else
            @value >= value
          end
        end
        BooleanArray.new(raw_array)
      end
    end

    class GreaterCondition < Condition
      def initialize(column, value)
        @column = column
        @value = value
      end

      def !@
        LessEqualCondition.new(@column, @value)
      end

      def evaluate
        raw_array = @column.collect do |value|
          if value.nil?
            nil
          else
            @value < value
          end
        end
        BooleanArray.new(raw_array)
      end
    end

    class GreaterEqualCondition < Condition
      def initialize(column, value)
        @column = column
        @value = value
      end

      def !@
        LessCondition.new(@column, @value)
      end

      def evaluate
        raw_array = @column.collect do |value|
          if value.nil?
            nil
          else
            @value <= value
          end
        end
        BooleanArray.new(raw_array)
      end
    end

    class SelectCondition < Condition
      def initialize(column, block)
        @column = column
        @block = block
      end

      def !@
        RejectCondition.new(@column, @block)
      end

      def evaluate
        BooleanArray.new(@column.collect(&@block))
      end
    end

    class RejectCondition < Condition
      def initialize(column, block)
        @column = column
        @block = block
      end

      def !@
        SelectCondition.new(@column, @block)
      end

      def evaluate
        raw_array = @column.collect do |value|
          evaluated_value = @block.call(value)
          if evaluated_value.nil?
            nil
          else
            not evaluated_value
          end
        end
        BooleanArray.new(raw_array)
      end
    end
  end
end
