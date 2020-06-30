Frontend Libraries
==================

When upgrading frontend libraries they must be changed in two places: scripts and fallback.

Scripts
-------

Change scripts pointed in the file ``templates/bootstrap/scripts.html.ep``

Fallback
--------

Fallback mode can be set up when the libraries are storedc in the
same Ravada server. A copy of all the libraries is downloaded following
`this guide </en/latest/docs/local_resources.html`_.

Change the fallback files list in the file ``etc/fallback.conf``

This file format is:

.. ::

  URL [optional directory/]

So the lines are like this. Notice the first one has the directory and the second line
doesn't need one.

.. ::

   https://cdnjs.cloudflare.com/ajax/libs/morris.js/0.5.1/morris.css morris.js/
   https://use.fontawesome.com/releases/v5.10.1/fontawesome-free-5.10.1-web.zip
   ...

Active the fallback, go to the ravada main source directory and fetch it to check it is working:

Enable Fallback
_______________

Set fallback to 1 in the file etc/rvd_front.conf, then restart the frontend.

Fetch the fallback
__________________


.. prompt:: bash $

  cd ravada
  ./etc/get_fallback.pl


