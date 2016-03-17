# iprep

This is an IpReputation project. Is inspired by [http://www.chaosreigns.com/iprep/](http://www.chaosreigns.com/iprep/).  
Unfortunately iprep project by chaosreigns seems dead (at least I don't get any feedback from project founder), so I started my own project for my purposes.
If you would like to connect to the project to feed data, please write me to iprep@valynkin.ru

Main purpose of the project is improve spamassassin accuracy (decreasing count of false-positives and false negatives).

How I achieved this:  
System counts spam and ham messages for each originating IP, then calculates reputation by following formula:  
`reputation = 100*ham_count / (ham_count+spam_count)`  

Calculated reputation is provided to spamassassin thru dnsbl mechanism, and spamassassin sets appropriate scores.

So, if I don't got spam from one praticular IP, the reputation for this IP equals 100.  
And if I got spam and only spam from IP, the reputation would be 0.

In dns reply the last octet is used to show score.  
For example IP 198.21.7.133 has reputation 100, and IP's 98.101.243.50 reputation is zero:

    $ host 133.7.21.198.iprep.propertyminder.com
    133.7.21.198.iprep.propertyminder.colo has address 127.0.0.100
    
    $ host 50.243.101.98.iprep.propertyminder.com
    50.243.101.98.iprep.propertyminder.colo has address 127.0.0.0

### To install client do following:

1. Edit spamassasin config, add folowing lines:
    $QUARANTINEDIR = "$MYHOME/quarantine";
    $clean_quarantine_method = 'local:clean/%m';
2. Create quarantine dirs 
    In my case:
    mkdir /opt/zimbra/data/amavisd/quarantine
    mkdir /opt/zimbra/data/amavisd/quarantine/clean
    mkdir /opt/zimbra/data/amavisd/quarantine/clean/ham
    mkdir /opt/zimbra/data/amavisd/quarantine/clean/spam
3. Put `start_iprep.sh`, `iprep.pl` and `prepare_quarantined_data.pl` to `/usr/local/bin/iprep/`
4. Edit `.ipreprc` and put to home directory of the spamassasin user
5. Put `iprep.cron` to `/etc/cron.d`
6. Put `iprep.cf` to spamassasin local-configs dir (in my case `/opt/zimbra/conf/sa`)

7. Restart spamassasin.

### To install server do following:

1. Put i`prep.pl` to `/usr/local/iprep/bin/`
2. Create `/usr/local/iprep/data/`
3. Configure rsyncd to put files in directory fom 2)
    Example /etc/rsyncd.conf:
    
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

4. Add zone to bind (example in bind directory)
5. Edit "configuration" section and subroutine "print_header" at bottom in  `/usr/local/iprep/bin/iprep.pl`
6. Create mysql database (use `create_tables.sql`)
7. Put `iprep.cron` to `/etc/cron.d/`
8. Put `iprep_status.cgi` to `cgi-bin` directory of the server

If you want use zabbix:

1. Put `zabbix-iprep` to `/etc/zabbix/scripts` and put `zabbix.cron` to `/etc/cron.d/`
2. Import `Template_App_Iprep.xml` into zabix
