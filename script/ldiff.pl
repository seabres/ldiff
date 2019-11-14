#!/usr/bin/perl

# $Id: ldiff.pl 32246 2010-08-23 13:51:54Z wsl $
# $URL: https://infix.uvt.nl/its-id/trunk/sources/ldiff/script/ldiff.pl $

# V2.2    30.6.2016   seabres
#  - Correct handling of attributes with emtry value on output
#  - Added interpreter to call it as executable

=encoding utf8

=head1 NAME

C<ldiff> calculate differences between LDIF files

=head1 SYNOPSIS

C<ldiff> C<-[ih]> I<file1> I<file2>

=head1 DESCRIPTION

Reads two RFC 2849 LDIF data description files and writes a series of
change records to stdout that describe how to go from I<file1> to I<file2>.

It determines the correct order to add and remove entries so that the LDAP
tree is always consistent.

=head1 USAGE

=over

=item C<-i>, C<--ignore>

Ignore the (comma or whitespace separated) attributes while making
the comparison.

=item C<-i>, C<--ignore>

Display a cheat sheet.

=back

=head1 EXAMPLE

 slapcat -l old.ldif
 sed s/Bob/Robert/g <old.ldif >new.ldif
 ldiff old.ldif new.ldif | ldapmodify

=head1 LIMITATIONS

This script is unable to deal with external sources (C<< cn:< >> type
entries, for example). Its LDIF parser is also not particularly robust
in the face of invalid input files.

=cut

# Datamodel:
#
# [
#   0  undef
#   1  undef
#   2  {
#         'ou=foo,o=quux,c=xyzzy' =>
#            {
#               'uvt-auth' =>
#                  {
#                    'foo/bar' => undef,
#                    'baz/bob' => undef,
#                    'fro/ber' => undef
#                  }
#            }
#         ...
#      }
#   3  {
#         ...
#      }
# ]
#
# De index in het hoofdarray slaat op het aantal komma's in de DN.
# Dit om er voor te zorgen dat nodes in de goede volgorde aangemaakt
# en weggegooid worden.

use strict;
use warnings FATAL => 'all';

use threads;

use MIME::Base64;
use IO::File;
use Encode;
use Getopt::Long qw(:config gnu_getopt);

my %ignore;

sub canonical_entry {
	my $line = $_[0];
	my $off = index $line, ':';
	die 'internal error' if $off == -1;
	my $key = substr $line, 0, $off;
	my $type = substr $line, $off + 1, 1;

	if($type eq '') {
		return (lc $key, '');
	} elsif($type eq ' ') {
		my $entry = substr $line, $off + 2;
		return (lc $key, encode_utf8($entry));
	} elsif($type eq ':') {
		my $entry = substr $line, $off + 3;
		return (lc $key, decode_base64($entry));
	} else {
		die "don't know how to handle '$type' type entries\n";
	}
}

sub canonical_dn {
	my $line = $_[0];
	die 'internal error' if lc(substr($line, 0, 3)) ne 'dn:';
	my $key = substr $line, 0, 2;
	my $type = substr $line, 3, 1;

	my $entry;

	if($type eq ' ') {
		$entry = encode_utf8(substr($line, 4));
	} elsif($type eq ':') {
		$entry = decode_base64(substr($line, 5));
		decode_utf8($entry, Encode::FB_CROAK);
	} else {
		die "don't know how to handle '$type' type dn\n";
	}

	$entry =~ s/\s+/ /g;
	$entry =~ s/^\s|\s$//g;
	$entry =~ s/\s?,\s?/,/g;
	$entry =~ s/,c=NL$/,c=NL/ig;

	return $entry;
}

sub level_dn {
	my $dn = $_[0];
	$dn =~ tr/,//cd;
	return length $dn;
}

sub dumpvalue {
	my ($key, $val, $prefix) = @_;

	$prefix = ''
		unless defined $prefix;

	if($val eq "") {
		print "$prefix$key:\n" or die $!;
	} elsif($val =~ /^[!-~]([ -~]*[!-~])?$/i) {
		print "$prefix$key: $val\n" or die $!;
	} else {
		my $base64 = encode_base64($val, '');
		print "$prefix${key}:: $base64\n" or die $!;
	}
}

sub dumprecord {
	my $ref = shift;
	my $rec = shift;
	my $modtype = shift;
	my $modify = shift;

	unless(defined $rec) {
		return unless defined $ref;
		dumpvalue('dn', $ref->{dn});
		print 'changetype: '.$modtype."\n" or die $!
			if defined $modtype;
		while(my ($key, $values) = each(%$ref)) {
			next if $key eq 'dn';
			foreach my $val (keys %$values) {
				dumpvalue($key, $val, '# ');
			}
		}
		print "\n" or die $!;
		return;
	}

	dumpvalue('dn', $rec->{dn});

	if(defined $modtype) {
		print 'changetype: '.$modtype."\n"
			or die $!;
	}

	while(my ($key, $values) = each(%$rec)) {
		next if $key eq 'dn';
		if(defined $modify) {
			next unless exists $modify->{$key};
			print $modify->{$key}.": ".$key."\n"
				or die $!;
		}
		if(exists $ref->{$key}) {
			foreach my $val (keys %{$ref->{$key}}) {
				dumpvalue($key, $val, '# ');
			}
		}
		foreach my $val (keys %$values) {
			dumpvalue($key, $val);
		}
		if(defined $modify) {
			print "-\n" or die $!;
		}
	}

	if(defined $modify) {
		while(my ($key, $val) = each(%$modify)) {
			next if exists $rec->{$key};
			print "$val: $key\n"
				or die $!;
			if(exists $ref->{$key}) {
				foreach my $val (keys %{$ref->{$key}}) {
					dumpvalue($key, $val, '# ');
				}
			}
			print "-\n" or die $!;
		}
	}

	print "\n" or die $!;
}

sub readldif {
	my $file = shift;
	my $entry = '';

	my $dn;
	my @records;
	my $record = {};

	{
		my %h;
		keys %h = 100000;
		$records[3] = \%h;
	}

	my $fh = new IO::File($file, '<:utf8')
		or die "$file: $!\n";

	while(defined(my $line = $fh->getline)) {
		chomp $line;
		eval {
			if($line eq '') {
				if($entry ne '') {
					if(defined $dn) {
						my ($key, $val) = canonical_entry $entry;
						undef $record->{$key}{$val}
							unless exists $ignore{$key};
					} else {
						$dn = lc($record->{dn} = canonical_dn $entry);
					}
					$entry = '';
				}
				if(defined $dn) {
					$records[level_dn $dn]{$dn} = $record;
					undef $dn;
					my %h;
					keys %h = 10;
					$record = \%h;
				}
			} elsif(ord($line) == 32) { # space
				$entry .= substr($line, 1);
			} elsif(ord($line) != 35) { # hash
				if($entry ne '') {
					if(defined $dn) {
						my ($key, $val) = canonical_entry $entry;
						undef $record->{$key}{$val}
							unless exists $ignore{$key};
					} else {
						$dn = lc($record->{dn} = canonical_dn $entry);
					}
				}
				$entry = $line;
			}
		};
		if($@) {
			my $line = $fh->input_line_number;
			die "$file:$line: $@";
		}
	}
	$fh->eof or die "$file: $!\n";
	$fh->close or die "$file: $!\n";
	undef $fh;

	if($entry ne '') {
		if(defined $dn) {
			my ($key, $val) = canonical_entry $entry;
			undef $record->{$key}{$val}
				unless exists $ignore{$key};
		} else {
			$dn = lc($record->{dn} = canonical_dn $entry);
		}
	}

	if(defined $dn) {
		$records[level_dn $dn]{$dn} = $record;
		undef $dn;
		$record = {};
	}

	return \@records;
}

sub addsmods {
	my ($a, $b) = @_;
	for(my $i = 0; $i < @$b; $i++) {
		my $bl = $b->[$i];
		next unless defined $bl;
		my $al = $a->[$i];
		while(my ($dn, $rec) = each(%$bl)) {
			if(defined $al && exists $al->{$dn}) {
				my $ref = $al->{$dn};
				my %update;
				my $dosomething;
				# compare records
				FIELD: while(my ($key, $val) = each(%$rec)) {
					next if $key eq 'dn';
					unless(exists $ref->{$key}) {
						$update{$key} = 'add';
						$dosomething = 1;
						next FIELD;
					}
					my $vax = $ref->{$key};
					foreach my $v (keys %$val) {
						unless(exists $vax->{$v}) {
							$update{$key} = 'replace';
							$dosomething = 1;
							next FIELD;
						}
					}
					foreach my $v (keys %$vax) {
						unless(exists $val->{$v}) {
							$update{$key} = 'replace';
							$dosomething = 1;
							next FIELD;
						}
					}
				}
				while(my ($key, $val) = each(%$ref)) {
					next if $key eq 'dn';
					unless(exists $rec->{$key}) {
						$update{$key} = 'delete';
						$dosomething = 1;
						next;
					}
				}
				dumprecord($ref, $rec, 'modify', \%update)
					if $dosomething;
			} else {
				dumprecord({}, $rec, 'add');
			}
		}
	}
}

sub deletes {
	my ($a, $b) = @_;
	for(my $j = @$a; $j > 0; $j--) {
		my $i = $j - 1;
		while(my ($dn, $ref) = each(%{$a->[$i]})) {
			unless(exists $b->[$i]{$dn}) {
				dumprecord($ref, undef, 'delete');
			}
		}
	}
}

sub parse_ignore {
	@ignore{grep($_, split(/[,\s]+/, lc $_[1]))} = ();
}

sub usage {
	my $fh = shift;
	print $fh "Usage: findlinks [options] [dir [dir ...]]\n",
		" -h, --help           Show usage information\n",
		" -i, --ignore cn,uid  List of attrs to ignore\n";
}

sub help {
	usage *STDOUT;
	exit 0;
}

unless(GetOptions(
	'h|help' => \&help,
	'i|ignore=s' => \&parse_ignore
)) {
	usage *STDERR;
	exit 1;
}

my $draadje = threads->create(\&readldif, $ARGV[0]);

#my $a = readldif($ARGV[0]);
my $b = readldif($ARGV[1]);

my $a = $draadje->join;

addsmods($a, $b);
deletes($a, $b);
