# Database Changes

When changing code for this project you may add, remove or modify columns in the
SQL database. Those change must be updated too in the _sql_ directory.

## SQL tables

Modify the SQL table definitions in the directory _sql/mysql/_.

## Data

Some tables may require data, place them in the directory _sql/data_. The files
must be called with the _insert_ prefix to the table name. So if you create the
new table _domaindrivers_ you have to :

 * Create a file at sql/mysql/domaindrivers.sql
 * Optionally create a file at sql/data/insert\_domaindrivers.sql with the insertions

## SQLite

SQLite definitions are used for testing and are created from the MySQL files.
Once the _mysql_ file is created, add the new table name to the
_sql/mysql/Makefile_ and run make. It requires https://github.com/dumblob/mysql2sqlite

## Runtime upgrade

When ravada runs, it can check if the table defition is accurate.
Place the code following the examples at the function _upgrade\_tables_ in _Ravada.pm_

Example: To check if the table vms has the field vm\_type:

    $self->_upgrade_table('vms','vm_type',"char(20) NOT NULL DEFAULT 'KVM'");

