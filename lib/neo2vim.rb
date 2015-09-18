#!/usr/bin/env ruby
class Neo2Vim
    def neovim_annotation line
        line.chomp.gsub(/^[^\(]*\('/, "").gsub(/'.*$/, "")
    end
    def on_neovim_line line
        if line.include? "plugin"
            @state = :plugin_class_definiton
        else
            @names.each do |name|
                if line.include? name
                    @store[name] = neovim_annotation line
                end
            end
            @state = :plugin_method_definition
        end
    end
    def method_name line
        line.chomp.gsub(/^ *[^ ]* /, "").gsub(/\(.*/, "")
    end
    def to_snake name
        name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
    def on_line line
        line.gsub!("import neovim", "import vim")
        line.gsub!(/.*if neovim$*/, "")
        @dst.write  line
        case @state
        when :plugin_class_definiton
            @plugin_class_name = line.chomp.gsub(/^[^ ]* /, "").gsub(/\(.*/, "")
            @plugin_id = to_snake(@plugin_class_name)
            @state = :normal
        when :plugin_method_definition
            @names.each do |name|
                if @store[name]
                    @stores[name] ||= {}
                    @stores[name][method_name(line)] = @store[name]
                    @store[name] = nil
                end
            end
            @state = :normal
        when :normal
        end
    end
    def initialize source, destination
        @names = ["function", "command", "autocmd"]
        @stores = {}
        @store = {}
        @plugin_class_name = nil
        @plugin_id = nil
        @state = :normal
        run source, destination
    end
    def declarations
            ["function", "autocmd", "command"].each do |what|
                @stores[what].each do |k, v|
                    @dst.puts "fun! #{what == "function"?"":"En"}#{what == "function" ? v : k}(arg0, arg1)
python <<EOF
r = #{@plugin_id}_plugin.#{k}([vim.eval('a:arg0'), vim.eval('a:arg1')])
vim.command('let g:__result = ' + json.dumps(([] if r == None else r)))
EOF
let res = g:__result
unlet g:__result
return res
endfun"
                end
            end
@dst.puts "augroup #{@plugin_id}
    autocmd!"
@stores["autocmd"].each do |k, v|
    @dst.puts "    autocmd #{v} * call En#{k}('', '')"
end
@dst.puts "augroup END"
@stores["command"].each do |k, v|
    @dst.puts "command! -nargs=0 #{v} call En#{k}('', '')"
end
    end
    def run source, destination
        File.open(destination, "w") do |dst|
            @dst = dst
            dst.puts "python <<EOF"
            File.open(source) do |src|
                @src = src
                src.each_line do |line|
                    if line.include? "@neovim"
                        on_neovim_line line
                    else
                        on_line line
                    end
                end
            end
            dst.puts "#{@plugin_id}_plugin = #{@plugin_class_name}(vim)"
            dst.puts "EOF"
            declarations
        end
    end
end
