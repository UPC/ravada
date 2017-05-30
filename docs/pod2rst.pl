#!/usr/bin/perl

use warnings;
use strict;
use File::Find 'find';

for my $incl_dir ("lib")
{
    find
    {
        wanted => sub 
        {
            my $file = $_;

            # They have to end in .pm...
            return unless $file =~ /\.pm\z/;

            # Convert the path name to a module name...
            $file =~ s{^\Q$incl_dir/\E}{};
            $file =~ s{/}{::}g;
            $file =~ s{\.pm\z}{};

            # Hnadle standard subdirectories 
            $file =~ s{^.*\b[a-z_0-9]+::}{};
            $file =~ s{^\d+.\d+\.\d+::(?:[a-z_][a-z_0-9]*::)?}{};
            return if $file =~ m{^::};

            # Print the module's name (once)...
            print $file, "\n";
        },
        no_chdir => 1,
    }, $incl_dir;
}

