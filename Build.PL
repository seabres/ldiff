#! /usr/bin/env perl

# $Id: Build.PL 32247 2010-08-23 13:52:11Z wsl $
# $URL: https://infix.uvt.nl/its-id/trunk/sources/ldiff/Build.PL $

use strict;
use warnings FATAL => 'all';
use utf8;

use Script::Build;

my $build = new Script::Build(
	dist_name => 'ldiff',
	dist_version => '2.1',
	dist_abstract => 'Generate differences between two LDIF files',
	dist_author => 'Wessel Dankers <wsl@uvt.nl>',
	license => 'perl',
	create_makefile_pl => 'small'
);
$build->create_build_script;
