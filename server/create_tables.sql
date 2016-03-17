DROP DATABASE iprep;
CREATE DATABASE iprep character set utf8;
use iprep;
create table iprep
(
    id          bigint(20) auto_increment not null,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ip		varchar(16),
    ham		bigint(20) DEFAULT 0,
    spam	bigint(20) DEFAULT 0,
    reputation	bigint(20) DEFAULT 0,
    primary key     (id),
    key 	    (reputation),
    unique          (ip)
) ENGINE=MyISAM;

create table rawdata
(
    id          bigint(20) auto_increment not null,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    linuxtimestamp	int,
    ip		varchar(16),
    ham		int(1) DEFAULT 0,
    spam	int(1) DEFAULT 0,
    primary key     (id),
    key	(ip),
    key	(linuxtimestamp)
) ENGINE=MyISAM;
