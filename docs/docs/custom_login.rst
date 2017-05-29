Create a custom login template
==============================

If you need custom login template create one and save it in templates/main/custom, e.g. custom\_login.html.ep

Configuration
-------------

Add your template in /etc/rvd\_front.conf

.. warning ::
   You must have a copy of rvd\_front.conf in /etc in order to make the custom login work. If the rvd\_front.conf has an example extension, after you copy it into the /etc directory erase that extension from the copy. Also, the file must have reading permissions (`chmod a+r /etc/rvd\_front.conf`).
   
,login\_custom => 'main/custom/custom\_login'

Path for CSS, js and images
---------------------------

If CSS, js or images are needed save in: public/css/custom,
public/js/custom or public/img/custom respectively.

.. note ::
    Make sure your CSS, JS or images in custom template refers to those paths.

Restart frontend
----------------

Finally restart rvd\_front:

::

    $ sudo systemctl restart rvd_front
