Create a custom login template
==============================

If you need custom login template create one and save it in ``/usr/share/ravada/templates/main/custom``, e.g. ``custom\_login.html.ep``

Custom login template contents
------------------------------

The default custom file can be found at ``/usr/share/ravada/templates/main/start.html.ep``.
Use it as a guide for your own template.

Be aware:

* form must be method=post
* keep the login input type name=login
* keep the password input type name=password
* keep the hidden input with the name=url entry
* the submit button must be called name=submit

Configuration
-------------

Add your template in ``/etc/rvd_front.conf``

.. warning ::
   Check that rvd_front.conf exists. If you work on a Development release you have an example here ``etc/rvd_front.conf.example``.
   
.. warning :: Do not include the extension file ``.html.ep`` in the path. E.g. ``custom_login.html.ep`` -> ``custom_login``

::

    ,login_custom => 'main/custom/custom_login'

Path for CSS, js and images
---------------------------

The custom files must be placed in  ``/usr/share/ravada/templates/main/custom``

If CSS, js or images are needed save in: ``public/css/custom``,
``public/js/custom`` or ``public/img/custom`` respectively. These files must be
located inside ``/usr/share/ravada/templates/public``.

.. note ::
    Make sure your CSS, JS or images in custom template refers to those paths.

Restart frontend
----------------

Finally restart rvd\_front:

.. prompt:: bash

    sudo systemctl restart rvd_front
