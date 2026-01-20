Restrict Access to Ravada
=========================

Description
-----------

In this guide we show a method to restrict access to Ravada using
configuration in the Apache server.

Configuration
-------------

The configuration has three steps: first we require users connect from
the proper IP network, then we enable the error message. Finally you must
write an error message for your users.

Require IP Address
~~~~~~~~~~~~~~~~~~

Edit /etc/apache2/sites-enabled/default-ssl.conf and deny access
to everything but the allowed networks:

::

	   <Location />
		   Require all denied
		   Require ip 10.0.0.0/8
		   Require ip 192.168.1.0/24

           ErrorDocument 403 /error/access_restricted.html
	   </Location>


Allow default
~~~~~~~~~~~~~

Edit /etc/apache2/sites-enabled/default-ssl.conf and allow access
to the error pages

::

       <Location /error>
            Require all granted
        </Location>

        <Location /favicon.ico>
            Require all granted
        </Location>

        ProxyPass /error/ !


Create an error message
~~~~~~~~~~~~~~~~~~~~~~~

Create a subdirectory in the apache server to host the error message:

.. prompt:: bash $

   sudo mkdir -p /var/www/html/error
    
Edit the file access_restricted.html in /var/www/html/error/ with a proper
message for your users.

If you do not want a customized error message, remove the line for the
ErrorDocument in the previous steps.

Enable configuration
--------------------

Restart the apache server to reload this configuration:


.. prompt:: bash $

    sudo systemctl apache2


