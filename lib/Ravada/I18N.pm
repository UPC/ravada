package Ravada::I18N;

use warnings;
use strict;

use base 'Locale::Maketext';
use File::Basename qw/dirname/;
use Locale::Maketext::Lexicon {
    _auto => 1,
    _decode => 1,
    '*' => [Gettext => dirname(__FILE__) . '/I18N/*.po']
};

1;
