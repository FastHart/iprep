#! /usr/bin/perl
use strict;
use warnings;
use DBI;

# configuration
my $data_dir = '/usr/local/iprep/data';
my $zone_file = '/etc/bind/iprep/iprep.propertyminder.colo';
my $rawdata_retention_days = 7;
my $find = '/usr/bin/find';
my $db_name = 'iprep';
my $db_host = 'localhost';
my $db_port = '3306';
my $db_user = 'root';
my $db_password = '';
# end of configuretion

my $dsn; my $dbh; my $sth;
my $spam; my $ham; my $db_field_to_increment;
my $db_table_rawdata = 'rawdata';
my $db_table_iprep = 'iprep';
my $db_field_ip = 'ip';
my $db_field_id = 'id';
my $db_field_ham = 'ham';
my $db_field_spam = 'spam';
my $db_field_reputation = "reputation";
my $db_field_timestamp = 'timestamp';
my $db_field_linuxtimestamp = 'linuxtimestamp';

$dsn = "DBI:mysql:database=$db_name;host=$db_host;port=$db_port";
eval {$dbh = DBI->connect($dsn, $db_user, $db_password, {'RaiseError' => 1}) };
die "can't connect to db: $@\n" if $@;

# 
# Feed data to DB
#
my @spam_files = `$find $data_dir -type f -name *spam*`;
my @ham_files = `$find $data_dir -type f -name *ham*`;

$spam="1"; $ham="0"; $db_field_to_increment=$db_field_spam;
&update_db(\@spam_files);

$spam="0"; $ham="1"; $db_field_to_increment=$db_field_ham;
&update_db(\@ham_files);

#
# Fetch data from DB and write to zone-file
#
eval {`/bin/mv -f $zone_file $zone_file.bkp`} if (-e $zone_file);
die "can't backup zonefile: $@" if $@;

open (OUT, ">$zone_file");
&print_header();
$sth = $dbh->prepare("SELECT $db_field_ip,$db_field_ham,$db_field_spam,$db_field_reputation FROM $db_table_iprep ORDER BY $db_field_reputation DESC");
eval { $sth->execute()};    die "can't connect to db: $@\n" if $@;
while ( (my $ip, my $ham, my $spam, my $reputation) = $sth->fetchrow_array()) {
    # in dns zone we need back-writed IP, so perform reverting
    $ip = join ".",reverse(split /\./,$ip);
    print OUT "$ip\tA\t127.0.0.$reputation\n";
  }
eval { $sth->finish() };    die "can't connect to db: $@\n" if $@;

#
# Remove old records from rawdata
#
$sth = $dbh->prepare("delete from rawdata where timestamp < (NOW() - INTERVAL $rawdata_retention_days DAY)");
eval { $sth->execute()};    die "can't connect to db: $@\n" if $@;
eval { $sth->finish() };    die "can't connect to db: $@\n" if $@;

close OUT;
$dbh->disconnect();
exit;

sub update_db {
    my @files_list = @{shift @_};
    foreach my $file (@files_list) {
        eval {open (IN, "<$file")};         die "can't open $file : $@'"  if $@;
        while ( my $line = <IN>) {
            chomp $line;
            (my $timestamp,my $ip) = split (/\s/, $line);
            # check if this e-mail is already counted early
            $sth = $dbh->prepare("SELECT $db_field_id FROM $db_table_rawdata WHERE $db_field_ip = '$ip' AND $db_field_linuxtimestamp = $timestamp");
            eval { $sth->execute()};    die "can't connect to db: $@\n" if $@;
            if ( $sth->rows > 0 ) {$sth->finish; next;}
            $sth->finish;
            eval { $dbh->do("INSERT INTO $db_table_rawdata ($db_field_linuxtimestamp,$db_field_ip,$db_field_ham,$db_field_spam) VALUES ($timestamp,'$ip',$ham,$spam)") };
            die "can't insert into db $db_table_rawdata: $@\n" if $@;
            #  folowing query increase spam counter for IP if IP found in db, or insert new row into db if this IP not in db.
            eval { $dbh->do("INSERT INTO $db_table_iprep ($db_field_ip,$db_field_ham,$db_field_spam,$db_field_reputation) VALUES ('$ip',$ham,$spam,(100*$ham/($ham+$spam))) ON DUPLICATE KEY UPDATE $db_field_to_increment = $db_field_to_increment + 1, $db_field_reputation=100*$db_field_ham/($db_field_ham+$db_field_spam);") };
            die "can't insert into db $db_table_iprep: $@\n" if $@;        
            }
        close IN;
        eval {`/bin/rm -f $file`};         die "can't delete $file : $@'"  if $@;
    }
}
    
sub print_header {
    my $linuxtimestamp = time();
    print OUT "\$TTL    60\n";
    print OUT "@       43200   SOA     iprep.propertyminder.colo.      admins.propertyminder.com.      ($linuxtimestamp 3600 300 432000 600)\n";
    print OUT "        IN      NS      iprep.propertyminder.colo.\n";
    print OUT "        A       172.17.100.18\n";
    print OUT "\n";
}
