# IpRep

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

In addition to the main iprep reputation zone (iprep) system provides other two dnsbl zones  (`iprep-black` and `iprep-white`), which contains IP adresses with very poor or very good reputation respectively.  
This two zones can be used by `greylisting`, `postscreen` or by other anti-spam mechanisms.

Now IpRep is running in production on my server.  
You can check system status here: [Iprep Status Page](http://valynkin.ru/iprep)  
If you wish to use my running instance of the iprep as dnsbl, or if you would like to connect to the project to feed data, please write me to `<this project name>@valynkin.ru`.


### General architecture

Scripts are written in perl. Used perl modules: 

    NetAddr::IP;
    Mail::SpamAssassin::Message::Metadata::Received qw(parse_received_line);
    Date::Parse; # str2time
    Mail::SpamAssassin::ArchiveIterator;
    Sys::Syslog;
    Net::IMAP::Simple;
    MIME::Parser;
    DBI;

System contains globally of two parts:

1. Server - running mysql and bind server, gets data from clients, calculate reputation (stores data in to mysql)  and provides reputation data to clients thru dnsbl mechanism.
2. Client/Data-feeder - running spamassassin, and provides spam/ham IP to server. 

See my [IPReputation system Scheme](https://docs.google.com/drawings/d/1Ly_778Fp9qDHfNt3xne4H1RC0voBg83umfspOTV0uew/edit?usp=sharing) drawings on Google Docs

In details system consists of the following scripts:

Server side:

- `iprep_create_dns_zones.pl`: This script creates dns-zone files in DNSBL format for use with bind.
- `iprep_load_data.pl`: This script reads files (which being prepared by `iprep_data_feeder.pl` script) in `$DATA_DIR` (recursively), fetches IP addresses and recalculates (in mysql) spam/ham score for fetched IP's.
 Files must contain 'ham' or 'spam' words in names to be loaded and will be deleted after load.
- `iprep_learn_from_imap.pl`: This script connects to Imap server, fetch IP addresses of incoming relays from all attachments founded in spam/ham accounts INBOX and recalculates spam/ham score for fetched IP's.
 To use you must have `spam` and `ham` mailboxes on server, where users have to send complaints.

Client side:

- `iprep_learn_from_quarantine.pl`: This script read emails quarantined by spamassassin, fetch IP addresses of incoming relays, and recalculates spam/ham score for fetched IP's. Needs connection to mysql on server side.
- `iprep_data_feeder.pl`: Originally it is a `iprep.pl` written by chaosreigns. This script read emails quarantined by spamassassin, fetch IP addresses of incoming relays, create files with fetched IP's and push this data files to server by rsync.
 On server side this files will be eaten by `iprep_load_data.pl`. Data files contains two fields `timestamp` and `IP` (devided by space) line by line for each processed email. This script is usable for clients which don't have access to mysql running on server side.

Also on client side i use two helper scripts:

- `iprep_sort_quarantined_mails_by_score.pl`: Must be run before `iprep_data_feeder.pl`. Script reads files quarantined by spamassassin and moves each file in spam/ham folder according spamassassin score.
- `start_iprep.sh`: Main starter script on client side. 

To use you should edit preferences section of each script and run it as cron job.

So let's consider two cases of usage:

## 1. Use `iprep_data_feeder.pl` on client side to provide data to server

### To install server do the following:

1) Download and unzip archive  
2) Create `/usr/local/iprep/bin` directory and put `iprep_create_dns_zones.pl` and `iprep_load_data.pl` into it  
3) Create data directory `/usr/local/iprep/data/`  
4) Configure rsyncd to put files into directory from step 2  
Example `/etc/rsyncd.conf`:
    
    [mx]
    path = /usr/local/iprep/data/mx
    comment = IpRep
    uid = nobody
    gid = nogroup
    read only = No
    auth users = mx
    secrets file = /etc/rsyncd.pass

5) Add zone to bind (example in bind directory)  
6) Edit "configuration" section  in `iprep_load_data.pl` and  `iprep_create_dns_zones.pl`  
7) Create mysql database (use `create_tables.sql`)  
8) Put `iprep-server.cron` into `/etc/cron.d/`  
9) Put `iprep_status.cgi` into cgi-bin directory of the server  

If you want to use zabbix:

10) Put `zabbix-iprep` into `/etc/zabbix/scripts` and put zabbix.cron into `/etc/cron.d/`  
11) Import `Template_App_Iprep.xml` to zabix


### To install client do the following:

1) Edit spamassassin config, add following lines:  

    $QUARANTINEDIR = "$MYHOME/quarantine";
    $clean_quarantine_method = 'local:clean/%m';

2) Create quarantine dirs (in my case):  

    mkdir /opt/zimbra/data/amavisd/quarantine
    mkdir /opt/zimbra/data/amavisd/quarantine/clean
    mkdir /opt/zimbra/data/amavisd/quarantine/clean/ham
    mkdir /opt/zimbra/data/amavisd/quarantine/clean/spam

3) Put `start_iprep.sh`, `iprep_sort_quarantined_mails_by_score.pl` and `iprep_data_feeder.pl` to `/usr/local/bin/iprep/`  
4) Edit `.ipreprc` and put to home directory of the spamassassin user  
5) Put `iprep.cron` to `/etc/cron.d`  
6) Put `iprep.cf` to spamassassin local-configs dir (in my case `/opt/zimbra/conf/sa`)  

7) Restart spamassassin.  

## 2. Use `iprep_learn_from_files` on client side to provide data to server

### To install server do the following:

1) Download and unzip archive  
2) Create `/usr/local/iprep/bin` directory and put `iprep_create_dns_zones.pl` into it  
3) Add zone to bind (example in bind directory)  
4) Edit "configuration" section  in `iprep_create_dns_zones.pl`  
5) Create mysql database (use `create_tables.sql`), allow to connect to mysql from client    
6) Edit `iprep-server.cron` and put it into `/etc/cron.d/`  
7) Put `iprep_status.cgi` into cgi-bin directory of the server  

If you want to use zabbix:

8) Put `zabbix-iprep` to `/etc/zabbix/scripts` and put zabbix.cron to `/etc/cron.d/`  
9) Import `Template_App_Iprep.xml` into zabix


### To install client do the following:

1) Edit spamassassin config, add following lines:  

    $QUARANTINEDIR = "$MYHOME/quarantine";
    $clean_quarantine_method = 'local:clean/%m';

2) Create quarantine dirs (in my case):  

    mkdir /var/lib/amavis/quarantine
    mkdir /var/lib/amavis/quarantine/clean

3) Put `start_iprep.sh` and `iprep_learn_from_files.pl` into `/usr/local/bin/iprep/`    
4) Edit settings section of the `iprep_learn_from_files.pl` and `start_iprep.sh`  
5) Put `iprep.cron` to `/etc/cron.d`  
6) Put `iprep.cf` to spamassassin local-configs dir (in my case `/etc/spamassassin/`)  

7) Restart spamassassin.  
