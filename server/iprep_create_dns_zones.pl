#! /usr/bin/perl
#
# This script is a part of the IpRep  project https://github.com/FastHart/iprep
#
# This script creates dns-zone files in DNSBL format for use with bind.
# Also script clean up old records from 'rawdata' table.
# Usage: edit preferences and run by cron
# 
# Dependencies: DBI; Sys::Syslog;
#

use strict;
use warnings;
use DBI;
use Sys::Syslog;
use subs qw/err/;
use subs qw/say/;

# ========= Preferences ================= #
my $DOMAIN = 'example.com';
my $ZONE_REPUTATION_NAME = 'iprep';
my $ZONE_BLACKLIST_NAME = 'iprep-black';
my $ZONE_WHITELIST_NAME = 'iprep-white';
my $ZONES_DIRECTORY = './';
my $ZONE_SOA_EMAIL = 'admins.example.com'; # this e-mail will be added to SOA rocord (so use SOA syntax only)

my $DB_NAME = 'iprep';
my $DB_HOST = 'localhost';
my $DB_PORT = '3306';
my $DB_USER = 'root';
my $DB_PASSWORD = '';
my $RAW_DATA_RETENTION_DAYS = 7;

my $LOG_FACILITY='local0';

# records in DB with $ham or $spam below folowing tresholds are not writed to dns files
my $MIN_MSG_COUNT_FOR_REPUTATION = 5;
my $MIN_MSG_COUNT_FOR_GREY  = 100;
my $MIN_MSG_COUNT_FOR_WHITE = 100;


my $debug = 0; # debug levels: 0, 1
# ========= End of preferences ========== #

# ========= Global variables ============ #
my $dsn; my $dbh;
# ========= End of gobal variables ====== #

# ========= Main program ================ #
# Open log
openlog("$0", "nofatal,perror,pid", $LOG_FACILITY);
# Connect to DB
$dsn = "DBI:mysql:database=$DB_NAME;host=$DB_HOST;port=$DB_PORT";
eval {$dbh = DBI->connect($dsn, $DB_USER, $DB_PASSWORD, {'RaiseError' => 1}) }; err "Unable connect to DB: $@\n" if $@;

# Create zone files
&create_zone($ZONE_REPUTATION_NAME, $MIN_MSG_COUNT_FOR_REPUTATION, 0, 100);
&create_zone($ZONE_BLACKLIST_NAME, $MIN_MSG_COUNT_FOR_GREY, 0, 10);
&create_zone($ZONE_WHITELIST_NAME, $MIN_MSG_COUNT_FOR_WHITE, 90, 100);
`/usr/bin/pkill -HUP named`;

# Remove old records from rawdata
my $sth = $dbh->prepare("delete from rawdata where timestamp < (NOW() - INTERVAL $RAW_DATA_RETENTION_DAYS DAY)");
eval { $sth->execute()};    err "Unable connect to db: $@\n" if $@;
eval { $sth->finish() };    err "Unable connect to db: $@\n" if $@;

$dbh->disconnect();
closelog();
exit;
# ========= End of Main program ========= #

# ========= Subroutines ================= #
sub create_zone {
    my ($zone_name, $min_msg_count, $reputation_min, $reputation_max) = @_;
    my $sth; my $counter;
    my $db_table_rawdata = 'rawdata';
    my $db_table_iprep = 'iprep';
    my $db_field_ip = 'ip';
    my $db_field_id = 'id';
    my $db_field_ham = 'ham';
    my $db_field_spam = 'spam';
    my $db_field_reputation = "reputation";
    my $db_field_timestamp = 'timestamp';
    my $db_field_linuxtimestamp = 'linuxtimestamp';
    
    my $zone_file = $ZONES_DIRECTORY.'/'.$zone_name.'.'.$DOMAIN;
    rename $zone_file, $zone_file.'.bak'  || err "Unable to rename $zone_file to $zone_file.'.bak': $!\n";
    
    open (OUT, ">$zone_file") || err "Unable to create output file $zone_file: $!\n";
    &print_header($zone_name);
    $sth = $dbh->prepare("SELECT $db_field_ip,$db_field_ham,$db_field_spam,$db_field_reputation FROM $db_table_iprep 
                            WHERE ($db_field_ham + $db_field_spam ) > $min_msg_count AND $db_field_reputation >= $reputation_min AND $db_field_reputation <= $reputation_max 
                             ORDER BY $db_field_reputation DESC");
    eval { $sth->execute()};    err "Unable connect to db: $@\n" if $@;
    while ( (my $ip, my $ham, my $spam, my $reputation) = $sth->fetchrow_array()) {
        $counter++;
        print OUT "\n;ip:$ip ham:$ham spam:$spam reputation:$reputation\n";
        # in dns zone we need back-writed IP, so perform reverting
        $ip = join ".",reverse(split /\./,$ip);
        print OUT "$ip\tA\t127.0.0.$reputation\n";
    }
    eval { $sth->finish() };    err "Unable connect to db: $@\n" if $@;
    say "Created $zone_file with $counter records";
}

sub print_header {
    my $zone_name = shift;
    my $linuxtimestamp = time();
    err "Please use SOA syntax in ZONE_SOA_EMAIL constant (i.e. replace \@ with \.)" if $ZONE_SOA_EMAIL =~ /.+\@.+/;
    print OUT "\$TTL    60\n";
    print OUT "@       43200   SOA     $zone_name.$DOMAIN.      $ZONE_SOA_EMAIL.      ($linuxtimestamp 3600 300 432000 600)\n";
    print OUT "        IN      NS      $zone_name.$DOMAIN.\n";
    print OUT "        A       172.17.100.18\n";
    print OUT "\n";
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
