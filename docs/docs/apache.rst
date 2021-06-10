Apache
======

You can set up any Web server on top of Ravada. In this doc we
show how to run Apache as a proxy. Settings another tool like
Nginx should be similar.

Upgrading
---------

Even if you had Apache proxy already set up you must add some
configuration options. Check Hypnotoad, modules and configuration
and make sure it is exactly like this.

Configure Hypnotoad proxy
-------------------------

Hypnotoad is the engine that runs the web Ravada frontend.
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

Enable these modules.

.. Tip:: Do it even it is not the first time you set up Apache. We added some modules in the latest release.

.. prompt:: bash #

    a2enmod ssl proxy proxy_http proxy_connect proxy_wstunnel headers

In this example we are using self signed certificate that comes with Apache SSL.
You can request a real certificate from any vendor like *LetsEncrpt*.

Apache Proxy Configuration
--------------------------

Link the https configuration and add the proxy lines.

.. prompt:: bash #

    a2ensite default-ssl

Edit /etc/apache2/sites-enabled/default-ssl.conf.

.. Tip:: Do not forget new *ProxyPass* and *RequestHeader* lines added in the last release.

::

    <IfModule mod_ssl.c>
        <VirtualHost _default_:443>
            ProxyRequests Off
            ProxyPreserveHost On
            ProxyPass /ws/ ws://localhost:8081/ws/ keepalive=On
            ProxyPass / http://localhost:8081/ keepalive=On
            ProxyPassReverse / http://localhost:8081/
            RequestHeader set X-Forwarded-Proto "https"

More information about SSL configuration from `Mozilla <https://ssl-config.mozilla.org/#server=apache&version=2.4.41&config=modern&openssl=1.1.1d&guideline=5.4>`_ and `Letsencrypt <https://letsencrypt.org>`_ non profit CA.

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

