#!/bin/bash
source /opt/zimbra/.bashrc
# copy quarantined files
/usr/local/bin/iprep/prepare_quarantined_data.pl
find /opt/zimbra/data/amavisd/quarantine -maxdepth 1 -type f -mmin -5 -exec cp -f "{}" /opt/zimbra/data/amavisd/quarantine/clean/spam/ \;
gunzip -f /opt/zimbra/data/amavisd/quarantine/clean/spam/*.gz
# analyse files with iprep
/usr/local/bin/iprep/iprep.pl spam:dir:/opt/zimbra/data/amavisd/quarantine/clean/spam ham:dir:/opt/zimbra/data/amavisd/quarantine/clean/ham > /tmp/iprep/iprep.log 2>&1
# clean quarantine
/bin/find /opt/zimbra/data/amavisd/quarantine/clean -type f -cmin +15 -delete
