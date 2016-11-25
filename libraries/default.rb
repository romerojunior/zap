# encoding: utf-8
#
# Cookbook Name:: zap
# HWRP:: zap
#
# Author:: Joseph J. Nuspl Jr. <nuspl@nvwls.com>
#
# Copyright:: 2014, Joseph J. Nuspl Jr.
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
#
class Chef
  # resource
  class Resource::Zap < Resource
    def initialize(name, run_context = nil)
      super

      # supported features
      @supports = []

      @delayed = false
      @pattern = '*'
      @filter = lambda { |_| true }

      # Set the resource name and provider
      @resource_name = :zap
      @provider = Provider::Zap

      # Set default actions and allowed actions
      @action = :delete
      @allowed_actions.push(:delete, :remove)
    end

    def pattern(arg = nil)
      set_or_return(:pattern, arg, kind_of: String)
    end

    def filter(&block)
      if !block.nil? && !@supports.include?(:filter)
        Chef::Log.warn "#{@resource_name} does not support filter"
      end
      set_or_return(:filter, block, kind_of: Proc)
    end

    def collect(&block)
      set_or_return(:collect, block, kind_of: Proc)
    end

    def select(&block)
      set_or_return(:select, block, kind_of: Proc)
    end

    def delayed(arg = nil)
      if arg == true
        @delayed = true
      elsif @delayed == false && immediately == false
        r = dup
        r.delayed(true)
        @run_context.resource_collection.all_resources << r
      end
      @delayed
    end

    def klass(arg = nil)
      return @klass if arg.nil?
      @klass = [arg].flatten.map do |obj|
        if obj.is_a?(Class)
          obj
        else
          begin
            obj.split('::').reduce(Module, :const_get)
          rescue
            fail "Cannot convert #{obj.inspect} into Class"
          end
        end
      end
    end

    def immediately(arg = nil)
      set_or_return(:immediately, arg, equal_to: [true, false], default: false)
    end
  end

  # provider
  class Provider::Zap < Provider::LWRPBase
    def load_current_resource
      @name  = @new_resource.name
      @klass = @new_resource.klass
      @pattern = @new_resource.pattern
      @filter = @new_resource.filter
      @collector = @new_resource.collect || method(:collect)
      @selector = @new_resource.select || method(:select)
    end

    def whyrun_supported?
      true
    end

    def action_delete
      iterate(:delete)
    end

    def action_remove
      iterate(:remove)
    end

    private

    def collect
      []
    end

    def select(r)
      r.name if @klass.include?(r.class)
    end

    # rubocop:disable MethodLength
    def iterate(act)
      return unless @new_resource.delayed || @new_resource.immediately

      # collect all existing resources
      extraneous = @collector.call

      # keep only those that match the specified pattern
      extraneous.select! { |name| ::File.fnmatch(@pattern, name) }

      @run_context.resource_collection.each do |r|
        name = @selector.call(r)
        if name && extraneous.delete(name)
          Chef::Log.debug "#{@new_resource} keeping #{name}"
        end
      end

      converge_by(@new_resource.to_s) do
        extraneous.each do |name|
          r = zap(name, act)
          Chef::Log.debug "#{@new_resource} zapping #{r}"
          if @new_resource.immediately
            r.run_action(act)
          end
          @run_context.resource_collection << r
        end
      end unless extraneous.empty?
    end
    # rubocop:enable MethodLength

    def zap(name, act, klass = nil)
      klass = @klass.first if klass.nil?

      r = klass.new(name, @run_context)
      r.cookbook_name = @new_resource.cookbook_name
      r.recipe_name = @new_resource.recipe_name
      r.action(act)
      r
    end
  end
end
