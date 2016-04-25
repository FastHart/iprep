#!/usr/bin/perl
#
# This script is a part of the IpRep  project https://github.com/FastHart/iprep
#
# This script reads files (which being quarantined by spamassasin) in $DATA_DIR (recursively), fetches IP addresses and recalculates (in mysql) spam/ham score for fetched IP's
# Usage: edit preferences and run by cron
# 
# Dependencies: NetAddr::IP; MIME::Parser; Date::Parse; DBI; Sys::Syslog;
#
# In ubuntu you can instal this modules as follows:
# sudo aptitude install libmime-tools-perl
# sudo aptitude install libnetaddr-ip-perl
# sudo aptitude install libdbd-mysql-perl
#

use strict;
use NetAddr::IP;
use MIME::Parser;
use Date::Parse; # str2time
use DBI;
use Sys::Syslog;
use subs qw/say/;
use subs qw/err/;

# ========= Preferences ================= #
my $TRUSTED_NETWORKS = '127.0.0.0/8 192.168.0.0/16';
my $WEIGHT = 1; # this value will be added to spam or ham counter for IP
my $SPAMASSASIN_SCORE_FOR_HAM  = 1; # all emails with smaller score is considered as ham
my $SPAMASSASIN_SCORE_FOR_SPAM = 5; # all emails with greater score is considered as spam

my $REMOVE_OLD_FILES = 1; # 1 - to remove, 0 - to stay on drive
my $FILES_RETENTION_TIME = 15; # in minutes

my $SPAMASSASIN_QUARANTINE_DIR = '/var/lib/amavis/quarantine/clean';
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
my $number_of_messages_ham = 0;
my $number_of_messages_spam = 0;
my $learned_counter = 0;
my @trusted_nets = ();
my @files = ();
# ========= End of gobal variables ====== #

# ========= Main program ================ #
# Prepare trusted networks objects
foreach (split ' ', $TRUSTED_NETWORKS) {
    my $net_obj = NetAddr::IP->new($_) || next;
    push @trusted_nets, $net_obj;
}

# Open log
openlog("$0", "nofatal,perror,pid", $LOG_FACILITY);

# Connect to DB
$dsn = "DBI:mysql:database=$DB_NAME;host=$DB_HOST;port=$DB_PORT";
eval {$dbh = DBI->connect($dsn, $DB_USER, $DB_PASSWORD, {'RaiseError' => 1}) }; err "can't connect to DB: $@\n" if $@;

# Find data files
eval {@files = `$FIND_BIN $SPAMASSASIN_QUARANTINE_DIR -type f`}; die "Can't open $SPAMASSASIN_QUARANTINE_DIR: $@" if $@;
if (!@files) {say "No files with emails found at $SPAMASSASIN_QUARANTINE_DIR. Exitting."; exit;}

# Read each file, extract last relay IP and spam srore, add IP to mysql with recalculating reputation
foreach my $file (@files) {
    my $is_spam = 0; 
    my $is_ham = 0;
    
    # open file
    chomp $file;
    eval {open (FILE, "<$file")};         err "Unable to open $file : $@'"  if $@;
    
    # parse message
    my $parser = MIME::Parser->new();
    $parser->output_to_core(1);      # don't write attachments to disk
    my $message  = $parser->parse(\*FILE) || err "Unable to read $file";
    my $head     = $message->head( ) || err "Unable to read $file";
    
    # get spam score
    my $spam_score = $head->get('X-Spam-Score');
    chomp $spam_score;
    next if (!$spam_score);
    print "$spam_score\t$file\n" if $debug;
    
    # make decision spam or ham 
    if ( $spam_score < $SPAMASSASIN_SCORE_FOR_HAM ) { $is_ham = 1; $number_of_messages_ham++; }
    elsif ( $spam_score > $SPAMASSASIN_SCORE_FOR_SPAM ) { $is_spam = 1; $number_of_messages_spam++; }
    else { next; }
    
    # get relay IP, timestamp and update DB
    my @received = $head->get('Received');
    foreach (@received) {
        (my $ip, my $timestamp) = &get_ip_form_line($_);
        next if (!$ip);
        next if (!$timestamp);
        next if (&check_trusted($ip));
        print "$ip\n$timestamp\n" if $debug;
        # !!! NB! here we update DB !!!
        $learned_counter++ if ( &update_db($ip, $timestamp, $is_spam, $is_ham) );
        last;
    }
}

say "Spam messages found: $number_of_messages_spam, Ham messages found: $number_of_messages_ham, Learned IPs: $learned_counter";

if ($REMOVE_OLD_FILES) {
        eval {@files = `$FIND_BIN $SPAMASSASIN_QUARANTINE_DIR -type f -cmin +$FILES_RETENTION_TIME -delete`}; die "Unabe to remove old files in $SPAMASSASIN_QUARANTINE_DIR: $@" if $@;
}

$dbh->disconnect();
closelog();
exit;
# ========= End of Main program ========= #

# ========= Subroutines ================= #
sub get_ip_form_line {
    my $line = shift;
    print $line if $debug;
    # example $line (multiline):
    # from mta5.zipyourflyer.com (mta5.zipyourflyer.com [69.33.98.230])
	#by mx.propertyminder.com (Postfix) with ESMTP id 8690210547C
	#for <bijan@reobankers.com>; Fri,  8 Apr 2016 10:23:37 -0700 (PDT)
    #
    $line =~ m/from.+\[(\d+\.\d+\.\d+\.\d+)\].+by.+;\s(.+)$/s;
    my $ip = $1;
    my $timestamp = str2time($2);
    #print "$ip\t$timestamp\t$2\n";
    return $ip, $timestamp;
}

sub check_trusted {
    my $ip = shift;
    my $relay = NetAddr::IP->new($ip);
    my $istrusted = 0;
    foreach my $trusted (@trusted_nets) {
        #print "$ip\t$trusted\n";
        if ($trusted->contains($relay)) {
            $istrusted = 1;
            print "Trusted.\n" if $debug;
        }
        last if ($istrusted);
    }
    return $istrusted;
}

sub update_db {
    my (my $ip, my $timestamp, my $spam, my $ham) = @_;
    my $sth; my $db_field_to_increment;
    my $db_table_rawdata = 'rawdata';
    my $db_table_iprep = 'iprep';
    my $db_field_ip = 'ip';
    my $db_field_id = 'id';
    my $db_field_ham = 'ham';
    my $db_field_spam = 'spam';
    my $db_field_reputation = "reputation";
    my $db_field_timestamp = 'timestamp';
    my $db_field_linuxtimestamp = 'linuxtimestamp';

    if ( $spam ) { $db_field_to_increment = $db_field_spam; }
    elsif ( $ham ) { $db_field_to_increment =  $db_field_ham; }
    else { err "Error in parameters in update_db procedure! neither spam nor ham parameters was given!"; }

    # check if this e-mail is  counted early
    $sth = $dbh->prepare("SELECT $db_field_id FROM $db_table_rawdata WHERE $db_field_ip = '$ip' AND $db_field_linuxtimestamp = '$timestamp'");
        eval { $sth->execute()};   err "can't connect to db: $@\n" if $@;
    if ( $sth->rows > 0 ) { $sth->finish; return 0; }
    $sth->finish;
    # add record to rawdata
    eval { $dbh->do("INSERT INTO $db_table_rawdata ($db_field_linuxtimestamp,$db_field_ip,$db_field_ham,$db_field_spam) VALUES ($timestamp,'$ip',$ham,$spam)") };  err "can't insert into db $db_table_rawdata: $@\n" if $@;
    #  folowing query increase spam or ham counter for IP if IP found in db, or insert new row into db if this IP not in db.
    eval { $dbh->do("INSERT INTO $db_table_iprep ($db_field_ip,$db_field_ham,$db_field_spam,$db_field_reputation) VALUES ('$ip',$ham,$spam,(100*$ham/($ham+$spam))) ON DUPLICATE KEY UPDATE $db_field_to_increment = $db_field_to_increment + $ham + $spam, $db_field_reputation=100*$db_field_ham/($db_field_ham+$db_field_spam);") };            err "can't insert into db $db_table_iprep: $@\n" if $@;
    return 1;
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
