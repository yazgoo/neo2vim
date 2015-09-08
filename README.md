# neo2vim
aims at translating neovim python plugins into vim plugins
# install
    
    gem install neo2vim

([rubygems.org](https://rubygems.org/gems/neo2vim) web page of the gem)

# usage

    neo2vim /path/to/input/plugin.py /path/to/output_dir

# File structure

`NAME` is extracted from neovim plugin class name.

* `plugin/{NAME}.vim`: Definitions of autocommands, commands, and functions
* `autoload/{NAME}.vim`: VimScript-Python bridge
* `autoload/{NAME}.vim.py`: Plugin implementation


