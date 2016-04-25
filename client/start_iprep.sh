#!/bin/bash
#
# This script is a part of the IpRep  project https://github.com/FastHart/iprep
#

# ========= Preferences ================= #
IPREP_DIR='/usr/local/bin/iprep'
SPAMASSASIN_SPAM_QUARANTINE_DIR='/var/lib/amavis/quarantine'
SPAMASSASIN_CLEAN_QUARANTINE_DIR='/var/lib/amavis/quarantine/clean'
# ========= End of preferences ========== #


if [ ! -d $IPREP_DIR ]; then
    echo "Directory $IPREP_DIR does not exists"
    exit
fi
if [ ! -d $SPAMASSASIN_SPAM_QUARANTINE_DIR ]; then
    echo "Directory $SPAMASSASIN_SPAM_QUARANTINE_SPAM_DIR does not exists"
    exit
fi
if [ ! -d $SPAMASSASIN_CLEAN_QUARANTINE_DIR ]; then
    echo "Directory $SPAMASSASIN_CLEAN_QUARANTINE_DIR does not exists"
    exit
fi


# ========= Main program ================ #

# if we run on zimbra server get zimbra environment
if [ -e /opt/zimbra/.bashrc ]; then source /opt/zimbra/.bashrc; fi

# if we use iprep_data_feeder.pl do the staff
if [ -e $IPREP_DIR/iprep_data_feeder.pl ]; then 
    # prepare files
    $IPREP_DIR/prepare_quarantined_data.pl
    find $SPAMASSASIN_SPAM_QUARANTINE_DIR -maxdepth 1 -type f -mmin -5 -exec cp -f "{}" $SPAMASSASIN_CLEAN_QUARANTINE_DIR/spam/ \;
    gunzip -f $SPAMASSASIN_CLEAN_QUARANTINE_DIR/spam/*.gz  >/dev/null 2>&1
    # analyse files with iprep_data_feeder.pl
    $IPREP_DIR/iprep_data_feeder.pl spam:dir:$SPAMASSASIN_CLEAN_QUARANTINE_DIR/spam ham:dir:$SPAMASSASIN_CLEAN_QUARANTINE_DIR/ham > /tmp/iprep/iprep.log 2>&1
fi

# if we use iprep_learn_from_files.pl do the staff
if [ -e $IPREP_DIR/iprep_learn_from_files.pl ]; then 
    # prepare files
    find $SPAMASSASIN_SPAM_QUARANTINE_DIR -maxdepth 1 -type f -mmin -5 -exec cp -f "{}" $SPAMASSASIN_CLEAN_QUARANTINE_DIR \;
    gunzip -f $SPAMASSASIN_CLEAN_QUARANTINE_DIR/*.gz >/dev/null 2>&1
    # analyse files with iprep_learn_from_files.pl
    $IPREP_DIR/iprep_learn_from_files.pl >/dev/null 2>&1
    # clean old files (uncomment if $REMOVE_OLD_FILES = 0; in iprep_learn_from_files.pl)
    #/bin/find $SPAMASSASIN_CLEAN_QUARANTINE_DIR -type f -cmin +15 -delete
fi

# ========= End of Main program ========= #
