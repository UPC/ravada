Create a custom login template
==============================

If you need custom login template create one and save it in ``/usr/share/ravada/templates/main/custom``, e.g. ``custom\_login.html.ep``

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

If CSS, js or images are needed save in: ``public/css/custom``,
``public/js/custom`` or ``public/img/custom`` respectively.

.. note ::
    Make sure your CSS, JS or images in custom template refers to those paths.

Restart frontend
----------------

Finally restart rvd\_front:

.. prompt:: bash

    sudo systemctl restart rvd_front
