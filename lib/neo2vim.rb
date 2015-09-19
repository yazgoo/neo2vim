#!/usr/bin/env ruby

require 'fileutils'
require 'stringio'

class Neo2Vim
    class PluginContent
        attr_reader :plugin
        attr_reader :autoload_py
        attr_reader :autoload
        def initialize
            @plugin = StringIO.new
            @autoload_py = StringIO.new
            @autoload = StringIO.new
        end
    end


    def neovim_annotation line
        if line =~ /^\s*@neovim\.(\w+)\('(\w+)'.*/
            {type: $1, name: $2}
        else
            nil
        end
    end
    def method_info(line, annotation = nil)
        {
            name: method_name(line),
            args: method_args(line),
            annotation: annotation,
        }
    end
    def method_args(line)
        start = line.index('(') + 1
        line[start..-1].scan(/\s*(\w+)(?:\s*=\s*[^,]+)?\s*(?:,|\))/).map(&:first)[1..-1]
    end
    def on_neovim_line line
        @annotation = nil
        if line.include? "plugin"
            @state = :plugin_class_definiton
            @in_plugin_class = true
        else
            @annotation = neovim_annotation line
            @state = :plugin_method_definition
        end
    end
    def method_name line
        line.chomp.gsub(/^ *[^ ]* /, "").gsub(/\(.*/, "")
    end
    def to_snake name
        name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
    def on_line line, contents
        line.gsub!("import neovim", "import vim")
        line.gsub!(/.*if neovim$*/, "")
        contents.autoload_py.write line
        case @state
        when :plugin_class_definiton
            @plugin_class_name = line.chomp.gsub(/^class\s+(\w+).*$/, '\1')
            @plugin_id = to_snake(@plugin_class_name)
            @state = :normal
        when :plugin_method_definition
            if @annotation && @names.include?(@annotation[:type])
                @stores[@annotation[:type]][method_name(line)] = method_info(line, @annotation)
            end
            @state = :normal
        when :normal
          if @in_plugin_class && line =~ /^[^#\s]/
            # TODO: deal with multi-line string literal
            @in_plugin_class = false
          end
          if @in_plugin_class && line =~ /^\s*def\s/ && method_name(line) !~ /^__/
            @stores["autoload_function"][method_name(line)] = method_info(line)
          end
        end
        @annotation = nil
    end
    def initialize source, destination
        @names = ["autoload_function", "function", "command", "autocmd"]
        @stores = @names.map {|name| [name, {}]}.to_h
        @annotation = nil
        @plugin_class_name = nil
        @in_plugin_class = false
        @plugin_id = nil
        @state = :normal
        run source, destination
    end
    def write_declarations contents
        ["autoload_function", "function", "autocmd", "command"].each do |what|
            @stores[what].each do |k, v|
                contents.autoload.puts <<-EOS
function! #{@plugin_id}\##{k}(#{v[:args].join(", ")}) abort
    return s:call_plugin('#{k}', [#{v[:args].map {|a| "a:" + a}.join(", ")}])
endfunction
                EOS
                contents.autoload.puts
            end
        end
        contents.plugin.puts <<-EOS
augroup #{@plugin_id}
    autocmd!
        EOS
        @stores["autocmd"].each do |k, v|
            contents.plugin.puts <<-EOS
    autocmd #{v[:annotation][:name]} * call #{@plugin_id}\##{k}(expand('<afile>'))
            EOS
        end
        contents.plugin.puts "augroup END"
        contents.plugin.puts

        @stores["command"].each do |k, v|
            contents.plugin.puts "command! -nargs=0 #{v[:annotation][:name]} call #{@plugin_id}\##{k}([])"
        end
        contents.plugin.puts

        @stores["function"].each do |k, v|
            contents.plugin.puts <<-EOS
function! #{v[:annotation][:name]}(#{v[:args].join(", ")}) abort
    return #{@plugin_id}##{k}(#{v[:args].map{|a| "a:" + a}.join(", ")})
endfunction
            EOS
        end
    end
    def run source, destination
        %w(plugin autoload).each do|dir|
            FileUtils.mkdir_p(File.join(destination, dir))
        end

        contents = File.open(source) {|f| parse f }

        File.open(File.join(destination, 'plugin', "#{@plugin_id}.vim"), "w") do |f|
            f.print(contents.plugin.string)
        end
        File.open(File.join(destination, 'autoload', "#{@plugin_id}.vim"), "w") do |f|
            f.print(contents.autoload.string)
        end
        File.open(File.join(destination, 'autoload', "#{@plugin_id}.vim.py"), "w") do |f|
            f.print(contents.autoload_py.string)
        end
    end

    def parse path
        contents = PluginContent.new

        nvim_guard = <<-EOS
if has('nvim')
  finish
endif
        EOS

        contents.plugin.puts(nvim_guard)

        contents.autoload.puts <<-EOS
if !has('nvim')
    execute 'pyfile' expand('<sfile>:p').'.py'
endif
        EOS
        contents.autoload.puts

        File.open(path) do |src|
            src.each_line do |line|
                if /^\s*@neovim/ =~ line
                    on_neovim_line line
                else
                    on_line line, contents
                end
            end
        end
        contents.autoload_py.puts "#{@plugin_id}_plugin = #{@plugin_class_name}(vim)"
        write_declarations(contents)

        contents.autoload.puts <<-EOS
function! s:call_plugin(method_name, args) abort
    " TODO: support nvim rpc
    if has('nvim')
      throw 'Call rplugin from vimscript: not supported yet'
    endif
    unlet! g:__error
    python <<PY
try:
  r = getattr(#{@plugin_id}_plugin, vim.eval('a:method_name'))(*vim.eval('a:args'))
  vim.command('let g:__result = ' + json.dumps(([] if r == None else r)))
except:
  vim.command('let g:__error = ' + json.dumps(str(sys.exc_info()[0]) + ':' + str(sys.exc_info()[1])))
PY
    if exists('g:__error')
      throw g:__error
    endif
    let res = g:__result
    unlet g:__result
    return res
endfunction
        EOS

        contents
    end
end
