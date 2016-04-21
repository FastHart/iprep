#!/usr/bin/perl
#
# This script is a part of the IpRep  project https://github.com/FastHart/iprep
#
# This script connects to Imap server, fetch IP's from all attachments founded in spam/ham folders and recalculates (in mysql) spam/ham score for fetched IP's
# Usage: edit preferences and run by cron
# 
# Dependencies: NetAddr::IP; Net::IMAP::Simple; MIME::Parser; Date::Parse; DBI; Sys::Syslog;
#
# In ubuntu you can instal this modules as follows:
# sudo aptitude install libnet-imap-simple-perl
# sudo aptitude install libmime-tools-perl
# sudo aptitude install libnetaddr-ip-perl
#

use strict;
use NetAddr::IP;
use Net::IMAP::Simple;
use MIME::Parser;
use Date::Parse; # str2time
use DBI;
use Sys::Syslog;
use subs qw/err/;

# ========= Preferences ================= #
my $TRUSTED_NETWORKS = '127.0.0.0/8 192.168.0.0/16';
my $WEIGHT = 5; # this value will be added to spam or ham counter

my $IMAP_SERVER = 'imap.example.com';
my $IMAP_USER_SPAM = 'spam@example.com';
my $IMAP_PASSWORD_SPAM = 'password';
my $IMAP_MAILBOX_SPAM = 'INBOX';
my $IMAP_USER_HAM = 'ham@example.com';
my $IMAP_PASSWORD_HAM = 'password';
my $IMAP_MAILBOX_HAM = 'INBOX';

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
my $number_of_messages;
my $learned_counter;
my @trusted_nets = ();
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

# Download messages form spam account and do things
syslog('notice', "Start learn iprep for spam from $IMAP_USER_SPAM.");
&loader($IMAP_USER_SPAM, $IMAP_PASSWORD_SPAM, $IMAP_MAILBOX_SPAM, $WEIGHT, 0);
syslog('notice', "Spam messages found: $number_of_messages, Learned SPAM IPs: $learned_counter");

# Download messages form ham account and do things
syslog('notice', "Start learn iprep for ham from $IMAP_USER_HAM.");
&loader($IMAP_USER_HAM, $IMAP_PASSWORD_HAM, $IMAP_MAILBOX_HAM, 0, $WEIGHT);
syslog('notice', "Ham messages found: $number_of_messages, Learned HAM IPs: $learned_counter");

$dbh->disconnect();
closelog();
exit;
# ========= End of Main program ========= #

# ========= Subroutines ================= #
sub loader {
    my ($user, $password, $folder, $spam, $ham) = @_;
    my $ip; my $timestamp;
    $learned_counter = 0;
    
    my $imap = new Net::IMAP::Simple( $IMAP_SERVER ) || err "Unable to connect to IMAP: $Net::IMAP::Simple::errstr";
    $imap->login( $user, $password ) || err "Can't login to imap: ". $imap->errstr;
    $number_of_messages = $imap->select( $folder ) || err "Can't read messages list from imap folder: ".$imap->errstr;
    print "Total messages to donload: $number_of_messages\n" if $debug;
    # Download emails
    foreach ( 1..$number_of_messages ) {
        my $fh = $imap->getfh( $_ ) || err "Can't read message from imap folder: ".$imap->errstr;
        my $parser = MIME::Parser->new();
        $parser->output_to_core(1);      # don't write attachments to disk
        my $message  = $parser->parse($fh);
        my $num_parts = $message->parts;
        # Read attachments
        for (my $i=0; $i < $num_parts; $i++) {
            my $part = $message->parts($i);
            next if ( $part->mime_type ne 'message/rfc822');
            my $body = $part->body_as_string;
            my $parser = MIME::Parser->new( );
            $parser->output_to_core(1);
            my $message  = $parser->parse_data($body); 
            my $head     = $message->head( );
            my @received = $head->get('Received');
            # Parse headers
            foreach (@received) {
                ($ip, $timestamp) = &get_ip_form_line($_);
                next if (!$ip);
                next if (!$timestamp);
                next if (&check_trusted($ip));
                print "$ip\n$timestamp\n" if $debug;
                $learned_counter++ if ( &update_db($ip, $timestamp, $spam, $ham) );
                last;
            }
        }
        #<stdin> if $debug;
        #last;
    }
    $imap->quit();
}

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
    my ($ip, $timestamp, $spam, $ham) = @_;
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

sub err {
    my $msg = shift;
    syslog('err', 'ERROR: '."$msg");
    die;
}
# ========= End of Subroutines ========== #
