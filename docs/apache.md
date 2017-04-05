Run Hypnotoad service and Apache as a proxy for it.

## Enable apache modules

    # a2enmod ssl proxy proxy_http proxy_connect

## Apache Proxy Configuration

Link the https configuration and add the proxy lines.

    # a2ensite default-ssl


Edit /etc/apache2/sites-enabled/default-ssl.conf

    <IfModule mod_ssl.c>
        <VirtualHost _default_:443>
            ProxyRequests Off
            ProxyPreserveHost On
            ProxyPass / http://localhost:8081/ keepalive=On
            ProxyPassReverse / http://localhost:8081/

## Apache redirect to https

Redirect all the connections to https.

Edit /etc/apache2/sites-enabled/000-default.conf

    <VirtualHost *:80>
        ServerName hostname.domainname
        Redirect / https://hostname.domainname/
    </virtualhost>

