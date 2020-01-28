Run Hypnotoad service and Apache as a proxy for it.

Configure Hypnotoad proxy
-------------------------

First of all you need to tell *hypnotoad* we are behind a proxy.
This allows Mojolicious to automatically pick up the X-Forwarded-For
and X-Forwarded-Proto headers.

Edit the file */etc/rvd_front.conf* and make sure there is a line with *proxy => 1*
inside hypnotoad.

::

   hypnotoad => {
       pid_file => '/var/run/ravada/rvd_front.pid'
      ,listen => ['http://*:8081']
      ,proxy => 1
   }

Restart the front server to reload this configuration:


.. prompt:: bash $

    sudo systemctl restart rvd_front


Install Apache
--------------

.. prompt:: bash #

    apt-get install apache2

Enable apache modules
---------------------

.. prompt:: bash #

    a2enmod ssl proxy proxy_http proxy_connect proxy_wstunnel headers

Apache Proxy Configuration
--------------------------

Link the https configuration and add the proxy lines.

.. prompt:: bash #

    a2ensite default-ssl

Edit /etc/apache2/sites-enabled/default-ssl.conf

::

    <IfModule mod_ssl.c>
        <VirtualHost _default_:443>
            ProxyRequests Off
            ProxyPreserveHost On
            ProxyPass /ws/ ws://localhost:8081/ws/ keepalive=On
            ProxyPass / http://localhost:8081/ keepalive=On
            ProxyPassReverse / http://localhost:8081/
            RequestHeader set X-Forwarded-Proto "https"

Apache redirect to https
------------------------

Redirect all the connections to https.

Edit /etc/apache2/sites-enabled/000-default.conf

::

    <VirtualHost *:80>
        ServerName hostname.domainname
        Redirect / https://hostname.domainname/
    </virtualhost>
    
.. Tip:: Remember restart Apache2 service, with ``systemctl restart apache2`` or ``services apache2 restart``.

.. prompt:: bash $

    sudo systemctl restart apache2

