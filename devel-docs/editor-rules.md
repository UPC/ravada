Editor configuration rules
==========================

If you work with Ravada code it will be easier for all of us if you
follow a minimun configuration rules.

- expand tabs to spaces
- one tab are 4 spaces

Highlight unwanted spaces
-------------------------
Please, don't remove unwanted spaces if aren't yours. Highlight them with these tips: http://vim.wikia.com/wiki/Highlight_unwanted_spaces

To disable autoremove of trailing spaces in Atom: 
In Atom Preferences->Packages, select the whitespace package.
In the whitespace package settings, disable "Remove Trailing Whitespace".


Vim Example
-----------
Set those options in your .vimrc to match ours

    set tabstop=4
    set expandtab
    "hightlight unwanted spaces
    highlight ExtraWhitespace ctermbg=red guibg=red
    match ExtraWhitespace /\s\+$/
