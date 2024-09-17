For small Ravada installations users can be added manually
from the administration web page. There are more options for
adding users and groups.

Users Batch Uploading
=====================

From the users administration page there is a button "New user".
There users can be added one by one or uploaded from a file
clicking in "Batch Upload"

Plain users and password
~~~~~~~~~~~~~~~~~~~~~~~~

We consider plain users as usernames stored in the SQL database.
Create a file with names and passwords separated by colon (:)
and upload it.

.. image:: images/upload_users_plain.png

Delegated login
~~~~~~~~~~~~~~~

Access can be delegated to another third party application.
Currently these are suported:

* LDAP
* CAS
* OpenID

By default, any user that is granted access is allowed to
use Ravada. In some environments the administrator may want to
filter the users allowed. In this case, first disable
"Auto create users" at the administration settings.
From now on only previously authorized users can log in.

Then upload a file with a list of allowed usernames.

.. image:: images/upload_users_openid.png

Groups
======

It is also possible to populate a group either manually one
by one or uploading a list of members.

Uploading with web browser
~~~~~~~~~~~~~~~~~~~~~~~~~~

Just create a text file with a list of users, one at each line
and upload from the "Group Administration" page.

.. image:: images/manage_group_members.png

CLI
~~~

It is also possible to upload the group members from the command line.
In the Ravada host server use the rvd_back command.

Add members to one group
------------------------

By default, the group name will be the name of the file. So this command
will create the group "students" and will add all the names in the file
to it.

::

  sudo rvd_back --upload-group-members=students.txt

The group name can be supplied if necessary:

::

  sudo rvd_back --upload-group-members=members.txt --group=students

Add members to many groups
--------------------------

If you want to create a large amount of groups, store the files in
a directory and pass it to the CLI. All the groups will be created
using the filenames as names for each group.

::

  sudo rvd_back --upload-group-members=/var/lib/groups/
