use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  VERSION   => '0.01',
  PREREQ_PM => {'Mojolicious' => '6.15'
      ,'Test::SQL::Data' => 0
      ,'Sys::Virt' => 0
  },
  test      => {TESTS => 't/*.t'}
);
