Run Hypnotoad service and Apache as a proxy for it

Apache Proxy

<IfModule mod_ssl.c>
    <VirtualHost _default_:443>

    ProxyRequests Off
    ProxyPreserveHost On
    ProxyPass / http://localhost:8080/ keepalive=On
    ProxyPassReverse / http://localhost:8080/

