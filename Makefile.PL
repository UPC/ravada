use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  VERSION   => '0.01',
  PREREQ_PM => {
   'Authen::Passphrase' => 0
     ,'DBIx::Connector' => 0
           ,'IPC::Run3' => 0
         ,'Mojolicious' => '6.15'
               ,'Moose' => 0
           ,'Sys::Virt' => 0
                ,'YAML' => 0
  },

  test      => {TESTS => 't/*.t t/*/*.t'}
);
