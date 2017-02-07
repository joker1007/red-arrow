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
  module IO
    class Loader < GObjectIntrospection::Loader
      class << self
        def load
          super("ArrowIO", IO)
        end
      end

      private
      def pre_load(repository, namespace)
        require "arrow/io/auto-closable"
      end

      def post_load(repository, namespace)
        require_libraries
      end

      def require_libraries
      end

      def load_object_info(info)
        super

        klass = @base_module.const_get(rubyish_class_name(info))
        if klass.respond_to?(:open)
          klass.singleton_class.prepend(AutoClosable)
        end
      end
    end
  end
end
