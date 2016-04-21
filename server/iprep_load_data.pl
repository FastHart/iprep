#! /usr/bin/perl
#
# This script is a part of the IpRep  project https://github.com/FastHart/iprep
#
# This script reads files (which being prepared by iprep_data_feeder.pl script) in $DATA_DIR (recursively), fetches IP addresses and recalculates (in mysql) spam/ham score for fetched IP's
# Files must contain 'ham' or 'spam' words in names to be loaded and will be deleted after load.
# Usage: edit preferences and run by cron
# 
# Dependencies: DBI; Sys::Syslog;
#
use strict;
use warnings;
use Sys::Syslog;
use subs qw/err/;
use subs qw/say/;
use DBI;

# ========= Preferences ================= #
my $DATA_DIR = '/usr/local/iprep/data';
my $FIND_BIN = '/usr/bin/find';

my $DB_NAME = 'iprep';
my $DB_HOST = 'localhost';
my $DB_PORT = '3306';
my $DB_USER = 'root';
my $DB_PASSWORD = '';

my $LOG_FACILITY='local0';
my $debug = 0; # debug levels: 0, 1
# ========= End of preferences ========== #

# ========= Global variables ============ #
my $dsn; my $dbh;
my $db_field_to_increment;
my $counter;
# ========= End of gobal variables ====== #

# ========= Main program ================ #
# Open log
openlog("$0", "nofatal,perror,pid", $LOG_FACILITY);
# Connect to DB
$dsn = "DBI:mysql:database=$DB_NAME;host=$DB_HOST;port=$DB_PORT";
eval {$dbh = DBI->connect($dsn, $DB_USER, $DB_PASSWORD, {'RaiseError' => 1}) }; err "Unable connect to DB: $@\n" if $@;

# Find data files
my @spam_files = `$FIND_BIN $DATA_DIR -type f -name *spam*`;
my @ham_files = `$FIND_BIN $DATA_DIR -type f -name *ham*`;
if (!@spam_files && !@ham_files) {say "Files with data not found, exitting"; exit;}

# Feed spam data to DB
$counter = 0;
&update_db(\@spam_files, 1, 0); # &update_db(files array, is_spam, is_ham);
say "Registered $counter IPs as spam form files @spam_files" if (@spam_files);

# Feed ham data to DB
$counter = 0;
&update_db(\@ham_files, 0, 1);
say "Registered $counter IPs as ham form files @ham_files" if (@ham_files);

$dbh->disconnect();
closelog();
exit;
# ========= End of Main program ========= #

# ========= Subroutines ================= #
sub update_db {
    my @files_list = @{shift @_};
    my ($spam, $ham) = @_;
    
    my $db_table_rawdata = 'rawdata';
    my $db_table_iprep = 'iprep';
    my $db_field_ip = 'ip';
    my $db_field_id = 'id';
    my $db_field_ham = 'ham';
    my $db_field_spam = 'spam';
    my $db_field_reputation = "reputation";
    my $db_field_timestamp = 'timestamp';
    my $db_field_linuxtimestamp = 'linuxtimestamp';
    my $db_field_to_increment;
    my $sth;
    
    if ( $spam ) { $db_field_to_increment = $db_field_spam; }
    elsif ( $ham ) { $db_field_to_increment = $db_field_ham; }
    else { err "Neither spam nor ham parameters was given in update_db procedure!"; }
    
    foreach my $file (@files_list) {
        eval {open (IN, "<$file")};         err "Unable to open $file : $@'"  if $@;
        while ( my $line = <IN>) {
            chomp $line;
            (my $timestamp,my $ip) = split (/\s/, $line);
            # check if this e-mail is already counted early
            $sth = $dbh->prepare("SELECT $db_field_id FROM $db_table_rawdata WHERE $db_field_ip = '$ip' AND $db_field_linuxtimestamp = $timestamp");
            eval { $sth->execute()};
                err "Unable connect to db: $@\n" if $@;
            if ( $sth->rows > 0 ) {$sth->finish; next;}
                $sth->finish;
            eval { $dbh->do("INSERT INTO $db_table_rawdata ($db_field_linuxtimestamp,$db_field_ip,$db_field_ham,$db_field_spam) VALUES ($timestamp,'$ip',$ham,$spam)")  };
                err "Unable insert into db $db_table_rawdata: $@\n" if $@;
            #  folowing query increase spam counter for IP if IP found in db, or insert new row into db if this IP not in db.
            eval { $dbh->do("INSERT INTO $db_table_iprep ($db_field_ip,$db_field_ham,$db_field_spam,$db_field_reputation) VALUES ('$ip',$ham,$spam,(100*$ham/($ham+$spam))) ON DUPLICATE KEY UPDATE $db_field_to_increment = $db_field_to_increment + 1, $db_field_reputation=100*$db_field_ham/($db_field_ham+$db_field_spam);") };
                err "Unable insert into db $db_table_iprep: $@\n" if $@;        
            $counter++;
            }
        close IN;
        eval {`/bin/rm -f $file`};         err "Unable delete $file : $@'"  if $@;
    }
}

sub say {
    my $msg = shift;
    syslog('info', "$msg");
}

sub err {
    my $msg = shift;
    syslog('err', 'ERROR: '."$msg");
    die;
}
# ========= End of Subroutines ========== #
