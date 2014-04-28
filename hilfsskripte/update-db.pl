#!/usr/bin/perl
#
#       Update Job-Bot DB
#       tuxwave.net
#       2009
###############################################################################
use strict;
use warnings;
###############################################################################
use IO::Handle;
use DBI;
autoflush STDIN;
###############################################################################
my $csv_dir = '/home/muster/bewerbung/job-bot/';
my $csv_file = 'bewerbungen.csv';
###############################################################################
my $dbh = DBI->connect("DBI:CSV:f_dir=$csv_dir;csv_sep_char=\\;") or die "Cannot connect: $DBI::errstr";
###############################################################################
print "Enter Reference-ID:";
my $reference = <STDIN>;
chomp($reference);
if($reference !~ /\d+-\d+-S/)
{
	exit;
}
print <<END;
Selection:
	1 - Status: Absage
	2 - Status: Durchsicht_Bewerbung
	3 - Status: Vorgestellt
	4 - Status: Auswahlverfahren
	5 - Status: Beworben
	6 - Status: Termin_VGespraech
END
my $selection = <STDIN>;
chomp($selection);
exit if ($selection =~ //);
my $status;
$status = 'Absage' if($selection eq '1');
$status = 'Durchsicht_Bewerbung' if($selection eq '2');
$status = 'Vorgestellt' if($selection eq '3');
$status = 'Auswahlverfahren' if($selection eq '4');
$status = 'Beworben' if($selection eq '5');
$status = 'Termin_VGespraech' if($selection eq '6');
if($selection > 6)
{
	print "Wrong selection\n";
	exit;
}
###############################################################################
my ($string, $string2) = ($dbh->quote($status), $dbh->quote($reference));
my $sth = $dbh->prepare("UPDATE $csv_file SET STATUS = $string WHERE REFERENZ LIKE $string2");
$sth->execute() or die "Cannot execute: " . $sth->errstr ();
###############################################################################
