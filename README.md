# iprep

This is an IpReputation project. Is inspired by [http://www.chaosreigns.com/iprep/](http://www.chaosreigns.com/iprep/).  
Unfortunately iprep project by chaosreigns seems dead (at least I don't get any feedback from project founder), so I started my own project for my purposes.

Main purpose of the project is improve spamassassin accuracy (decreasing count of false-positives and false negatives).

How I achieved this:  
System counts spam and ham messages for each originating IP, and calculates reputation by following formula:  
`reputation = 100*ham_count / (ham_count+spam_count)`  

All data are stored in mysql database.  
Calculated reputation is provided to spamassassin thru dnsbl mechanism, and spamassassin sets appropriate scores.

So, if I don't got spam from one particular IP, the reputation for this IP equals 100.  
And if I got spam and only spam from IP, the reputation would be 0.

In dns reply the last octet is used to show score.  
For example IP 198.21.7.133 has reputation 100, and IP's 98.101.243.50 reputation is zero:

    $ host 133.7.21.198.iprep.propertyminder.com
    133.7.21.198.iprep.propertyminder.colo has address 127.0.0.100
    
    $ host 50.243.101.98.iprep.propertyminder.com
    50.243.101.98.iprep.propertyminder.colo has address 127.0.0.0

This system is running in production on my server.  
You can check system status here: [Iprep Status Page](http://valynkin.ru/iprep)  
If you wish to use my running instance of the iprep as dnsbl, or if you would like to connect to the project to feed data, please write me to <this project name>@valynkin.ru.


### General architecture

Scripts are written in perl. Used perl modules: 

    NetAddr::IP;
    Mail::SpamAssassin::Message::Metadata::Received qw(parse_received_line);
    Date::Parse; # str2time
    Mail::SpamAssassin::ArchiveIterator;
    DBI;

System contains two parts:

1. Client - running on spamassassin server, reads quarantined messages and provides IP to server
2. Server - running on mysql and bind server, gets data from client, puts data to mysql and updates dns-zone file.

See my [IPReputation system Scheme](https://docs.google.com/drawings/d/1Ly_778Fp9qDHfNt3xne4H1RC0voBg83umfspOTV0uew/edit?usp=sharing) drawings on Google Docs

I use the iprep.pl written by chaosreigns as a "Client".

### To install client do the following:

1) Edit spamassassin config, add following lines:  

    $QUARANTINEDIR = "$MYHOME/quarantine";
    $clean_quarantine_method = 'local:clean/%m';

2) Create quarantine dirs (in my case):  

    mkdir /opt/zimbra/data/amavisd/quarantine
    mkdir /opt/zimbra/data/amavisd/quarantine/clean
    mkdir /opt/zimbra/data/amavisd/quarantine/clean/ham
    mkdir /opt/zimbra/data/amavisd/quarantine/clean/spam

3) Put `start_iprep.sh`, `iprep.pl` and `prepare_quarantined_data.pl` to `/usr/local/bin/iprep/`  
4) Edit `.ipreprc` and put to home directory of the spamassassin user  
5) Put `iprep.cron` to `/etc/cron.d`  
6) Put `iprep.cf` to spamassassin local-configs dir (in my case `/opt/zimbra/conf/sa`)  

7) Restart spamassassin.  

### To install server do the following:

1) Put `iprep.pl` to `/usr/local/iprep/bin/` 
2) Create `/usr/local/iprep/data/`  
3) Configure rsyncd to put files in directory from 2)  
Example `/etc/rsyncd.conf`:
    
    [mx]
    path = /usr/local/iprep/data/mx
    comment = IpRep
    uid = nobody
    gid = nogroup
    #hosts allow = 192.168.1.0/24
    #hosts deny = *
    read only = No
    auth users = mx
    secrets file = /etc/rsyncd.pass

4) Add zone to bind (example in bind directory)  
5) Edit "configuration" section and subroutine "print_header" at bottom in  `/usr/local/iprep/bin/iprep.pl`  
6) Create mysql database (use `create_tables.sql`)  
7) Put `iprep.cron` to `/etc/cron.d/`  
8) Put `iprep_status.cgi` to cgi-bin directory of the server  

If you want to use zabbix:

1) Put `zabbix-iprep` to `/etc/zabbix/scripts` and put zabbix.cron to `/etc/cron.d/`  
2) Import `Template_App_Iprep.xml` into zabix
