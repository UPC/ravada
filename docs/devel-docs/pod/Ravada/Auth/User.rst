.. highlight:: perl


****
NAME
****


Ravada::Auth::User - User management and tools library for Ravada

BUILD
=====


Internal OO builder


messages
========


List of messages for this user


.. code-block:: perl

     my @messages = $user->messages();



unread_messages
===============


List of unread messages for this user


.. code-block:: perl

     my @unread = $user->unread_messages();



unshown_messages
================


List of unshown messages for this user


.. code-block:: perl

     my @unshown = $user->unshown_messages();



show_message
============


Returns a message by id


.. code-block:: perl

     my $message = $user->show_message($id);


The data is returned as h hash ref.


mark_message_read
=================


Marks a message as read


.. code-block:: perl

     $user->mark_message_read($id);


Returns nothing


mark_message_shown
==================


Marks a message as shown


.. code-block:: perl

     $user->mark_message_shown($id);


Returns nothing


mark_message_unread
===================


Marks a message as unread


.. code-block:: perl

     $user->mark_message_unread($id);


Returns nothing


mark_all_messages_read
======================


Marks all message as read


.. code-block:: perl

     $user->mark_all_messages_read();


Returns nothing


