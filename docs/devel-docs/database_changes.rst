Database Changes
================

When changing code for this project you may add, remove or modify
columns in the SQL database. Those change must be updated too in the
*sql* directory.

SQL tables
----------

Modify the SQL table definitions in the directory *sql/mysql/*.

Data
----

Some tables may require data, place them in the directory *sql/data*.
The files must be called with the *insert* prefix to the table name. So
if you create the new table *domaindrivers* you have to :

-  Create a file at sql/mysql/domaindrivers.sql
-  Optionally create a file at sql/data/insert\_domaindrivers.sql with
   the insertions

SQLite
------

SQLite definitions are used for testing and are created from the MySQL
files. Once the *mysql* file is created, add the new table name to the
*sql/mysql/Makefile* and run make. It requires
https://github.com/dumblob/mysql2sqlite

Runtime upgrade
---------------

When ravada runs, it can check if the table defition is accurate. Place
the code following the examples at the function *upgrade\_tables* in
*Ravada.pm*

Example: To check if the table vms has the field vm\_type:

::

    $self->_upgrade_table('vms','vm_type',"char(20) NOT NULL DEFAULT 'KVM'");
