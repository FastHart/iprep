#!/usr/bin/perl
use strict;
use warnings;
#
# This script moves files from /opt/zimbra/data/amavisd/quarantine/clean to ...clean/ham and ...clean/spam
#
my $spam_treshold = 5;
my $ham_treshold = 1;
my $debug = 0;

my $SPAMMY_AND_CLEAN_QUARANTINE_DIR = '/opt/zimbra/data/amavisd/quarantine/clean';
#my $SPAMMY_AND_CLEAN_QUARANTINE_DIR = '/tmp/iprep/quarantine/clean';
my $SPAM_QUARANTINE_DIR = '/opt/zimbra/data/amavisd/quarantine/clean';
#
my $find = "/bin/find";
my $mv = "/bin/mv";
my $rm = "/bin/rm";
my @files;
my $counter = 0;
#
# Read files from clean-and-spammy quarantine and move to appropriate folders
#

# here we get array with full path to file /tmp/iprep/quarantine/clean/0-UAUQTx7mZr
eval {@files = `$find $SPAMMY_AND_CLEAN_QUARANTINE_DIR -maxdepth 1 -type f`}; die "Can't open $SPAMMY_AND_CLEAN_QUARANTINE_DIR: $@" if $@;

foreach my $file (@files) {
    if ($debug) { $counter++; print "$counter\t"; }
    # here we have $file with full path like this: /tmp/iprep/quarantine/clean/0-86y4iKMkwZ
    # so split full path to path and filename
    $file =~ /(.+)\/(.+$)/;
    my $dir = $1; $file = $2;
    print "$dir / $file\t" if ($debug);
    open IN,"<$dir/$file";
    my $score = 0;
    while (<IN>) {
        if ( $_ =~ /^X-Spam-Score\: (\-*\d+\.\d+).*/ ) { $score = $1; }
    }
    close IN;
    print "score: $score\n" if ($debug);
    if ( $score < $ham_treshold ) { 
       eval {`$mv -f $dir/$file $dir/ham/$file`}; die "Can't move file $SPAMMY_AND_CLEAN_QUARANTINE_DIR/$file to ham: $@" if $@;  
       next;
       }
    if ( $score > $spam_treshold ) { 
       eval {`$mv -f $dir/$file $dir/spam/$file`}; die "Can't move file $SPAMMY_AND_CLEAN_QUARANTINE_DIR/$file to spam: $@" if $@;
        next;
        }
    eval {`$rm -f $dir/$file`}; die "Can't delete file $SPAMMY_AND_CLEAN_QUARANTINE_DIR/$file: $@" if $@;
}
exit;
