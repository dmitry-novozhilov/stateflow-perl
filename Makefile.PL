#!/usr/bin/perl

use strict;
use warnings;
use ExtUtils::MakeMaker;
use ExtUtils::Manifest qw(mkmanifest);

mkmanifest();

WriteMakefile(
    NAME            => 'State::Flow',
	ABSTRACT		=> 'TODO:',
  	AUTHOR			=> 'Dmitry Novozhilov <Dmitry@Novozhilov.ru>',
    VERSION_FROM    => 'lib/State/Flow.pm',
	LICENSE			=> 'TODO:',
	test			=> {TESTS => 't/*.t t/*/*.t'},
	TEST_REQUIRES	=> {'Test::Spec' => 0},
	EXE_FILES		=> [],
	MIN_PERL_VERSION=> 5.008,
	PREREQ_PM		=> {
		"Const::Fast"	=> 0,
		"DBI"			=> 0,
	},
	META_MERGE		=> {
		'meta-spec'		=> { version => 2 },
		resources		=> {
			repository	=> {
				type	=> 'git',
				url		=> 'git://github.com/dmitry-novozhilov/TODO:.git',
				web		=> 'https://github.com/dmitry-novozhilov/TODO:',
			},
		},
	},
);
