#!/usr/bin/env ruby
class Neo2Vim
    def neovim_annotation line
        line.chomp.gsub(/^[^\(]*\('/, "").gsub(/'.*$/, "")
    end
    def on_neovim_line line
        if line.include? "plugin"
            @plugin_name = true
        else
            @names.each do |name|
                if line.include? name
                    @store[name] = neovim_annotation line
                end
            end
        end
    end
    def method_name line
        line.chomp.gsub(/^ *[^ ]* /, "").gsub(/\(.*/, "")
    end
    def on_line line
        line.gsub!("import neovim", "import vim")
        line.gsub!(/.*if neovim$*/, "")
        @dst.write  line
        if @plugin_name == true
            @plugin_name = line.chomp.gsub(/^[^ ]* /, "").gsub(/\(.*/, "")
        else
            @names.each do |name|
                if @store[name]
                    @stores[name] ||= {}
                    @stores[name][method_name(line)] = @store[name]
                    @store[name] = nil
                end
            end
        end
    end
    def initialize source, destination
        @names = ["function", "command", "autocmd"]
        @stores = {}
        @store = {}
        @plugin_name = nil
        run source, destination
    end
    def declarations
            ["function", "autocmd", "command"].each do |what|
                @stores[what].each do |k, v|
                    @dst.puts "fun! #{what == "function"?"":"En"}#{what == "function" ? v : k}(arg0, arg1)
python <<EOF
r = plugin.#{k}([vim.eval('a:arg0'), vim.eval('a:arg1')])
vim.command('let g:__result = ' + json.dumps(([] if r == None else r)))
EOF
let res = g:__result
unlet g:__result
return res
endfun"
                end
            end
@dst.puts "augroup Poi
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
            dst.puts "plugin = #{@plugin_name}(vim)"
            dst.puts "EOF"
            declarations
        end
    end
end
