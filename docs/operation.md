
# Create users


    sudo ./usr/sbin/rvd_back --add-user=username

    sudo ./usr/sbin/rvd_back --add-user-ldap=username


# Import KVM virtual machines.

Usually, virtual machines are created within ravada, but they can be
imported from existing KVM domains. Once the domain is created :

    sudo ./usr/sbin/rvd_back --import-domain=a

It will ask the name of the user the domain will be owned by.


# View all rvd_back options

In order to manage your backend easily, rvd_back has a few flags that
lets you made different things (like changing the password for an user).

If you want to view the full list, execute:

    sudo rvd_back --help

# Admin

## Create Virtual Machine

Go to Admin -> Machines and press _New Machine_ button.

If anything goes wrong check Admin -> Messages for information
from the Ravada backend.

## ISO MD5 missmatch

When downloading the ISO, it may fail or get old. Check the error
message for the name of the ISO file and the ID.

### Option 1: clean ISO and MD5

* Remove the ISO file shown at the error message
* Clean the MD5 entry in the database:

    mysql -u rvd_user -p ravada
    mysql> update iso_images set md5='' WHERE id=_ID_

Then you have to create the machine again from scratch and make it download
the ISO file.

### Option 2: refresh the ISO table

If you followed _Option 1_ and it still fails you may have an old
version of the information in the _isoimages_ table. Remove that
entry and insert the data again:

    $ mysql -u rvd_user -p ravada -e "DELETE FROM iso_images WHERE id=_ID_"

Insert the data from the SQL file installed with the package:

    $ mysql -u rvd_user -p ravada -f < /usr/share/doc/ravada/sql/data/insert_iso_images.sql

It will report duplicated entry errors, but the removed row should be inserted
again.
