Using Let's Encrypt with Apache
===============================

Description
-----------

The Apache frontend requires an SSL certificate. The one provided by 
`Let's Encrypt <https://letsencrypt.org/>`__
is easy to setup. In this guide we configure it using the http challenge.

It requires port 80 of the server open for your certificate provider, wether it is
let's encrypt or another with the same protocol.

Configuration
-------------

Let's Encrypt
~~~~~~~~~~~~~

Go to 
`Let's Encrypt <https://letsencrypt.org/>`__
or your certificate provider, and sign up. Find out your HMAC , Key ID and Server
URL. You will need it for the final step.

Configuration directory
~~~~~~~~~~~~~~~~~~~~~~~

Create the directory for well known files:

.. prompt:: bash $

   sudo mkdir /var/www/html/.well-known/

Configure Apache Rewrites
~~~~~~~~~~~~~~~~~~~~~~~~~

Previously we reccomended use *Redirect* when *non-https* requests were received.
For Let's Encrypt certbot to work, we need to allow access to the .well-known
directory.

First enable the rewrite module:

.. prompt:: bash $

    sudo a2enmod rewrite

Edit the file /etc/apache2/sites-enabled/000-default.conf , comment the
*Redirect* line and add *Rewrites*.

::

    # Redirect / https://rvd4.upc.edu/

    # Redirect HTTP traffic to HTTPS, except ".well-known" directory
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteCond %{REQUEST_URI} !^/.well-known/
    RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R,L]

Configure Apache Letsencrypt certificate
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Let's Encrypt drops the certificates in this directory. We have to tell Apache
to load it from there. Do not restart Apache after changing this. Wait untill
the certificate is installed in the next steps.

Edit the file /etc/apache2/sites-enabled/default-ssl.conf and use the full
fqdm of your server instead of the example here *server.domain.com* . When
in doubt, at the next step when running certbot, it will display the names
of the certificate files.

::

	SSLCertificateFile /etc/letsencrypt/live/server.domain.com/fullchain.pem
	SSLCertificateKeyFile /etc/letsencrypt/live/server.domain.com/privkey.pem

Install Certbot
~~~~~~~~~~~~~~~

::

    sudo apt install certbot

Certificate Installation
------------------------

Installing the certificate requires port 80 open, run the certbot tool and restart
Apache.

Run Certbot
~~~~~~~~~~~

Run Certbot using webroot and the server URL Let's Encrypt or your SSL provider
gave you. You also need your Key ID and HMAC.

::

    certbot certonly -w /var/www/html --webroot --server  https://server.url.com/acme/xxxxxxx/directory \
 --eab-kid key --eab-hmac-key hmac -d server.domain.com

Restart Apache
~~~~~~~~~~~~~~


.. prompt:: bash $

   sudo systemctl restart apache2

Final
-----

When cerbot runs and you restart apache, connect to your server and check the
certificate has been renewed.
