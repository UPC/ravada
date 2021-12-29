use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  VERSION   => '0.01',
  NAME => 'Ravada',
  PREREQ_PM => {
          'Mojolicious' => '7.01'
            ,'DateTime' => 0
     ,'DBIx::Connector' => 0
  ,'Authen::Passphrase' => 0
	      ,'IPC::Run3'  => 0
	      ,'JSON::XS'   => 0
	        ,'Moose'    => 0
	  ,'Net::LDAP'  => 0
      ,'Sys::Virt'  => 0
      ,'XML::LibXML'=> 0
             ,'YAML' => 0
    ,'Image::Magick' => 0
      ,'MooseX::Types::NetAddr::IP' => 0
	,'IO::Interface' => 0
	,'Sys::Statistics::Linux' => 0
    ,'Test::Pod::Coverage' => 0
    ,'Locale::Maketext::Lexicon' => 0
    ,'Mojolicious::Plugin::I18N' => 0
    ,'DBD::SQLite'      => 0
    ,'Net::DNS' => 0
    ,'Net::OpenSSH' => 0
    ,'File::Rsync' => 0
    ,'DateTime::Format::DateParse'=> 0
    ,'PBKDF2::Tiny' => 0
  },
  BUILD_REQUIRES => {
    'Test::Perl::Critic' => 0
    ,'Test::Moose::More' => 0
  },

  test      => {TESTS => 't/*.t t/*/*.t'},
  clean     => {FILES => ['t/.db', '/var/tmp/rvd_void','/var/tmp/node.lock','/var/tmp/fw.lock'] }

);
