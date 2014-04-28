#!/usr/bin/perl
#
#	Job-Bot
#	tuxwave.net
#	2009
###############################################################################
use warnings;
use strict;
###############################################################################
use WWW::Mechanize;
use HTML::FormatText::WithLinks;
use DBI;
use MIME::Lite;
use POSIX qw(strftime);
use File::Copy;
use utf8;
use Encode qw(encode decode encode_utf8 decode_utf8);
###############################################################################
my $logfile = '/home/muster/bewerbung/job-bot/logfile.txt';
###############################################################################
my $results_storage = '/home/muster/bewerbung/job-bot/cache/search_results';
my $csv_dir = '/home/muster/bewerbung/job-bot/datenbank';
my $csv_file = 'bewerbungen.csv';
my $csv_file_temp = 'bewerbungen_temp.csv';
###############################################################################
my $bewerbung = '/home/muster/bewerbung/job-bot/bewerbung/bewerbung.odt';
my $outdir = '/home/muster/bewerbung/job-bot/cache/outdir/';
###############################################################################
my $newest_fileage_mmin = '-10'; #Minuten
my $old_fileage_mtime = '40'; #Tage
###############################################################################
#Vars - Jobboerse
my $jobboerse = 'http://jobboerse.arbeitsagentur.de';
my $job_searchform = '/vamJB/stellenangeboteFinden.html';
my $job_expandpage = '/vamJB/stellenangeboteFinden.html?d_6827794_z=9999&d_6827794_p=1&execution=e1s2';
my @requests;
my $delay = 2;
push(@requests, {'jb.flow.event.hauptfunktion' => '_eventId_stellenangeboteSuchen', '_ahnlicheBerufe.wert.value' => 'on', 'nurStellenMitFolgendenBegriffen.wert' => 'IT-Systemadministrator', 'suchbegriffebeziehung.wert.wert' => '2', 'arbeitsort.plz.wert' => '81241', 'arbeitsort.ort.wert' => 'München', 'arbeitsort.region.wert.wert' => '2', 'umkreis.wert' => '30', '_behinderung.wert.value' => 'on'});
my @mail_blacklist = qw();
###############################################################################
#Objects
my $mech = WWW::Mechanize->new();
my $dbh = DBI->connect("DBI:CSV:f_dir=$csv_dir;csv_sep_char=\\;f_encoding=utf8") or die "Cannot connect: $DBI::errstr";
###############################################################################
my $db_index = 0;
my $job_workname = 'Foojob';
my $date = strftime("%d.%m.%Y", localtime);
unlink("$csv_dir/$csv_file_temp") if -f "$csv_dir/$csv_file_temp";
###############################################################################
getjobs();
jobgrabber();
set_index();
jobfile_task();
job_sender();
###############################################################################
sub getjobs
{
	foreach my $hashref (@requests)
	{
		$job_workname = $hashref->{'nurStellenMitFolgendenBegriffen.wert'};
		$mech->agent_alias('Windows Mozilla');
		$mech->add_header(Referer => $jobboerse);
		$mech->add_header(Encoding => 'utf-8');
		$mech->get($jobboerse . $job_searchform);
		$mech->submit_form(with_fields => {%$hashref});
		$mech->get($jobboerse . $job_expandpage);
		open(FILE, ">$results_storage/$hashref->{'nurStellenMitFolgendenBegriffen.wert'}.htm");
		binmode(FILE, ":utf8");
		print FILE $mech->content();
		close(FILE);
	}
}

sub jobgrabber
{
	foreach my $hashref (@requests)
	{
		open(FILE, "<$results_storage/$hashref->{'nurStellenMitFolgendenBegriffen.wert'}.htm");
		binmode(FILE, ":utf8");
		while(<FILE>)
		{
			chomp($_);
			if($_ =~ /Zu den Details des Stellenangebots/ && $_ =~ /internerLink/)
			{
				if($_ =~ /<a href="(.+)".*\<span\>(.*)\<\/span\>.*$/)
				{
					my $job_page = $1;
					my $job_page_title = $2;
					$job_page_title =~ s/\&uuml\;/ü/g;
					$job_page_title =~ s/\&ouml\;/ö/g;
					$job_page_title =~ s/\&auml\;/ä/g;
					$job_page_title =~ s/\&szlig\;/ß/g;
					$job_page_title =~ s/\&amp;/&/g;
					$job_page =~ s/\&amp;/&/g;
					$mech->get($jobboerse . $job_page);
					my $html2text = HTML::FormatText::WithLinks->new();
					my $job_page_content = $html2text->parse($mech->content());
					my $job_page_reference_nr = $1 if $job_page_content =~ /(\d+-\d+-S)/;
					next if(!$job_page_reference_nr || !$job_page_title);
					my $filename = $results_storage . '/' . $job_page_reference_nr . '.txt';
					unless(-f "$filename")
					{
						open(JOBFILE, ">$filename");
						binmode(JOBFILE, ":utf8");
						print JOBFILE "$job_page_reference_nr $job_page_title\n\n";
						print JOBFILE $job_page_content;
						close(JOBFILE);
					}
					#Comment out next line if ready
					exit;
					sleep($delay);
				}
			}
		}
		close(FILE);
	}

}

sub set_index
{
	if(-f "$csv_dir/$csv_file")
	{
		my $sth = $dbh->prepare("SELECT INDEX FROM $csv_file ORDER BY INDEX DESC");
		$sth->execute();
		while (my $result = $sth->fetchrow_hashref('NAME_uc'))
		{
			$db_index = $result->{INDEX} if $result->{INDEX};
			last if $db_index > 0;
		}
	}
}

sub jobfile_task
{
	system("/usr/bin/find $results_storage -type f -mtime $old_fileage_mtime -exec rm {} \\;");
	open(FIND, "/usr/bin/find $results_storage -type f -mmin $newest_fileage_mmin|");
	while(<FIND>)
	{
		next if $_ =~ /^\..*/;
		jobfile_parser($_);
	}
	close(FIND);	
}

sub jobfile_parser
{
	my $jobfile = $_[0];
	my ($job_reference, $job_title, $job_mail, $job_tel, $job_address, $job_contact, $job_gender);
	my $trigger = 0;
	my $counter = 0;
	open(FILE, "<$jobfile");
	binmode(FILE, ":utf8");
	while(<FILE>)
	{
		chomp($_);
		$counter++;
		($job_reference = $1, $job_title = $2,) if $_ =~ /(\d+-\d+-S)\s(.*)$/ && $counter == 1;
		$job_mail = $1 if $_ =~ /mailto:(.*\@.*\..*)/;
		$job_tel = $1 if $_ =~ /Telefonnummer:\s(.*)/;
		$job_tel =~ s/\s|\(|\)//g if $job_tel;

		if($_ =~ /Bewerbungen an/)
		{
			$trigger = 1;
			next;
		}
		$trigger = 0 if($_ =~ /Telekommunikation|Externer\sLink/);
		if($trigger == 1)
		{	
			$_ =~ s/^\s+//g;
			$_ =~ s/\n+/\n/g;
			$_ =~ s/^\n//g;
			if($_ =~ /(Frau|Herr)\s(.*)/)
			{
				$job_gender = $1;
				$job_contact = $2;
				if($job_contact =~ /(.*)\s(.*)/)
				{
					$job_contact = $2;
				}
				next;
			}
			$job_address .= "$_\n" if length($_) > 0;
		}
	}
	open(LOG, ">$logfile");
	binmode(FILE, ":utf8");
	print LOG "Reference: $job_reference\n" if $job_reference;
	print LOG "Title: $job_title\n" if $job_title;
	print LOG "Contact: $job_gender $job_contact\n" if $job_contact;
	print LOG "E-Mail: $job_mail\n" if $job_mail;
	print LOG "Telephone: $job_tel\n" if $job_tel;
	print LOG "Address:\n$job_address" if $job_address;
	print LOG "-------------------------------------------------------------\n";
	close(LOG);
	my $sth;
	my $duplicate = 0;
	unless(-f "$csv_dir/$csv_file")
	{	
		$sth = $dbh->prepare("CREATE TABLE $csv_file (INDEX VARCHAR(50), DATUM VARCHAR(50), REFERENZ VARCHAR(50),JOBTITEL VARCHAR(50),ANREDE VARCHAR(50), ANSPRECHPARTNER VARCHAR(50),ADRESSE VARCHAR(50),TELEFON VARCHAR(50),E_MAIL VARCHAR(50),BEWERBUNGSART VARCHAR(50),STATUS VARCHAR(50))");
		$sth->execute() or die "Cannot execute: " . $sth->errstr ();
	}
	$sth = $dbh->prepare("SELECT REFERENZ FROM $csv_file WHERE REFERENZ = ?");
	$sth->execute($job_reference);
	while (my $result = $sth->fetchrow_hashref('NAME_uc'))
	{
		$duplicate = 1 if $result->{REFERENZ} eq $job_reference;
	}
	unless($duplicate)
	{
		if($job_mail)
		{
			my $mail_blacklisted = 0;
			foreach(@mail_blacklist)
			{
				$mail_blacklisted = 1 if($job_mail =~ /$_/);
			}
			unless($mail_blacklisted == 1)
			{
				$job_contact = "Damen und Herren" if !$job_contact;
				$sth = $dbh->prepare("INSERT INTO $csv_file (INDEX, REFERENZ, JOBTITEL, ANREDE, ANSPRECHPARTNER, ADRESSE, TELEFON, E_MAIL, BEWERBUNGSART) VALUES (?,?,?,?,?,?,?,?,?)");
				$sth->execute(++$db_index, $job_reference, $job_title, $job_gender, $job_contact, $job_address, $job_tel, $job_mail, '5') or die "Cannot execute: " . $sth->errstr ();
			}
		}
	}
	close(FILE);
}

sub file_prepare
{
	my $inr = $_[0];
	unless(-f "$outdir/bewerbung_out_$inr.pdf")
	{
		system("/usr/local/openoffice/bin/oowriter -invisible \"macro:///Standard.Module1.DBMerge\"");
		#system("/usr/local/openoffice/bin/oowriter \"macro:///Standard.Module1.DBMerge\"");
	}
	open(DIR, "find $outdir -type f -name '*.odt'|");
	while(<DIR>)
	{
		chomp($_);
		system("/usr/local/openoffice/bin/oowriter -invisible \"macro:///Standard.Module1.ConvertWordToPDF($_)\"\n");
		#system("/usr/local/openoffice/bin/oowriter \"macro:///Standard.Module1.ConvertWordToPDF($_)\"\n");
		unlink("$_");
		move("$outdir/bewerbung0.pdf", "$outdir/bewerbung_out_$inr.pdf");
		#move("$outdir/bewerbung0.pdf", "/home/muster/bewerbung/job-bot/test//bewerbung_out_$inr.pdf");
	}
	close(DIR);
}

sub mail_sender
{
	my $mail_index = shift;
	my $mail_recipient = shift;
	my $mail_reference = shift;
	my $mail_anrede = shift;
	my $mail_ansprechpartner = shift;
	
	my $anrede = "";
	if($mail_anrede eq "Herr")
	{
		$anrede = "geehrter";
	}
	else
	{
		$anrede = "geehrte";
	}

$mail_ansprechpartner = decode('ISO-8859-15', $mail_ansprechpartner);

my $msgtext = <<ENDE;

Sehr $anrede $mail_anrede $mail_ansprechpartner,

ich möchte mich bei Ihnen als $job_workname bewerben.
Bitte beachten Sie hierfür die Bewerbungsunterlagen im Anhang.

Mit freundlichen Grüßen

Mustername

ENDE
$msgtext = encode_utf8($msgtext);
	my $msg = MIME::Lite->new(
	From =>'mustername@muster.net',
	To => $mail_recipient,
#	To => 'mustername@muster.net',
	Bcc =>'bewerbungen_sent@tuxwave.net',
	Subject => encode('MIME-B', "Bewerbung als $job_workname - $mail_reference"),
	Type =>'multipart/mixed'
	);
	$msg->attr('content-type.charset' => 'UTF-8');
	$msg->attach(
        Type =>'text/plain;charset=utf-8',
        Data =>$msgtext
    	);
	$msg->attach(
        Type     =>'application/pdf',
        Path     =>"$outdir/bewerbung_out_$mail_index.pdf",
        Filename =>'Bewerbung-Mustername.pdf',
        Disposition => 'attachment',
        Encoding =>'base64',
	);
	$msg->attach(
        Type     =>'text/plain;charset=utf-8',
        Path     =>"$csv_dir/Skills_Mustername.txt",
        Filename =>'Skills-Mustername.txt',
        Disposition => 'attachment',
	);
	my $pass = 'foo';
	if($msg->send('smtp','smtp.web.de', AuthUser=> 'mustername@web.de', AuthPass=> $pass))
#	if($msg->send('smtp','localhost'))
	{
		my ($string, $string2) = ($dbh->quote($date), $dbh->quote($mail_reference));
		my $sth = $dbh->prepare("UPDATE $csv_file SET DATUM = $string WHERE REFERENZ LIKE $string2");
		$sth->execute() or die "Cannot execute: " . $sth->errstr ();
		($string, $string2) = ($dbh->quote("Beworben"), $dbh->quote($mail_reference));
		$sth = $dbh->prepare("UPDATE $csv_file SET STATUS = $string WHERE REFERENZ LIKE $string2");
		$sth->execute() or die "Cannot execute: " . $sth->errstr ();
	}
	else
	{
		my ($string, $string2) = ($dbh->quote($date), $dbh->quote($mail_reference));
		my $sth = $dbh->prepare("UPDATE $csv_file SET DATUM = $string WHERE REFERENZ LIKE $string2");
		$sth->execute() or die "Cannot execute: " . $sth->errstr ();
		($string, $string2) = ($dbh->quote("Bewerbung fehlgeschlagen"), $dbh->quote($mail_reference));
		$sth = $dbh->prepare("UPDATE $csv_file SET STATUS = $string WHERE REFERENZ LIKE $string2");
		$sth->execute() or die "Cannot execute: " . $sth->errstr ();
	}
}

sub job_sender
{
	my $sth = $dbh->prepare("SELECT * FROM $csv_file");
	$sth->execute();
	my $dbh2 = DBI->connect("DBI:CSV:f_dir=$csv_dir;csv_sep_char=\\;f_encoding=utf8") or die "Cannot connect: $DBI::errstr";
	my $sth2;
	while (my $result = $sth->fetchrow_hashref('NAME_uc'))
	{
		if($result->{STATUS})
		{
			next if $result->{STATUS} =~ /Beworben|Vorgestellt|Auswahlverfahren|Absage|Durchsicht_Bewerbung|Termin_VGespraech/;
		}
		unless(-f "$csv_dir/$csv_file_temp")
		{
			$sth2 = $dbh2->prepare("CREATE TABLE $csv_file_temp (INDEX VARCHAR(50), DATUM VARCHAR(50), REFERENZ VARCHAR(50),JOBTITEL VARCHAR(50),ANREDE VARCHAR(50), ANSPRECHPARTNER VARCHAR(50),ADRESSE VARCHAR(50),TELEFON VARCHAR(50),E_MAIL VARCHAR(50),BEWERBUNGSART VARCHAR(50),STATUS VARCHAR(50))");
			$sth2->execute() or die "Cannot execute: " . $sth->errstr ();
		}
		$sth2 = $dbh2->prepare("INSERT INTO $csv_file_temp (INDEX, REFERENZ, JOBTITEL, ANREDE, ANSPRECHPARTNER, ADRESSE, TELEFON, E_MAIL, BEWERBUNGSART) VALUES (?,?,?,?,?,?,?,?,?)");
		$sth2->execute($result->{INDEX}, $result->{REFERENZ}, $result->{JOBTITEL}, $result->{ANREDE}, $result->{ANSPRECHPARTNER}, $result->{ADRESSE}, $result->{TELEFON}, $result->{E_MAIL}, $result->{BEWERBUNGSART}) or die "Cannot execute: " . $sth->errstr ();
		file_prepare($result->{INDEX});
		if(-f "$outdir/bewerbung_out_$result->{INDEX}.pdf")
		{
			mail_sender($result->{INDEX}, $result->{E_MAIL}, $result->{REFERENZ}, $result->{ANREDE}, $result->{ANSPRECHPARTNER});
		}
		unlink("$outdir/bewerbung_out_$result->{INDEX}.pdf");
		unlink("$csv_dir/$csv_file_temp");
	}
}
