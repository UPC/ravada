Set access restrictions to Virtual Machines
===========================================

When a base is set as public , all the users have access to create clones by default.
If you want to set access restrictions to base you can filter by LDAP attributes.

Access restrictions
-------------------

Restrictions can be defined given a base and the value of an LDAP attribute.
For example, you could set that only users who have the attribute "typology" as "teacher"
are allowed to clone a virtual machine. Or you could deny "student" users access to
another base.

Configuration
-------------

Actually there is a form to configure the access restrictions in the works. Until it
is done you have to set this directly in the database.

Grant access
^^^^^^^^^^^^

To grant access add an entry in the table access_ldap_attribute with the id of the
base, the name of the attribute, the value of the attribute. The optional field allowed
can be used to deny access to a virtual machine.

To remove a grant delete the row from the table access_ldap_attribute.


Examples
--------

Example 1: grant access
^^^^^^^^^^^^^^^^^^^^^^^

Grant access to a virtual machine, only to those users that have typology = teacher.

First you need to know the id of the base virtual machine.

::

  mysql> select id,name from domains where name ='mymachine';
  +------+--------------------------+
  | id   | name                     |
  +------+--------------------------+
  | 88   | mymachine                |

Then add the restriction:

::

  mysql> insert into access_ldap_attribute (id_domain, attribute,value) VALUES(88,'typology','teacher');

Example 2: deny access
^^^^^^^^^^^^^^^^^^^^^^

Deny access to a virtual machine, to those users that have typology = student.

First you need to know the id of the base virtual machine.

::

  mysql> select id,name from domains where name ='mymachine2';
  +------+--------------------------+
  | id   | name                     |
  +------+--------------------------+
  | 89   | mymachine2                |

Then add the restriction:

::

  mysql> insert into access_ldap_attribute (id_domain, attribute,value,allowed) VALUES(89,'typology','student',0);

Example 3: remove an access restriction
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

We have some a restriction to deny access to students we want to remove because we want
everybody access to that virtual machine:

::

  mysql> select * from access_ldap_attribute;
  +----+-----------+-----------+---------+---------+
  | id | id_domain | attribute | value   | allowed |
  +----+-----------+-----------+---------+---------+
  |  2 |        88 | typology  | teacher |       1 |
  |  3 |        89 | typology  | student |       0 |
  +----+-----------+-----------+---------+---------+
  mysql> delete from access_ldap_attribute where id=3;

