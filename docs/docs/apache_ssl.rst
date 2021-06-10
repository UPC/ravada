Apache SSL
==========

You need to buy an SSL certificate, then add it to /etc/apache2/sites-enabled/default-ssl.conf

This is an example redacted from a real server:

::

    <IfModule mod_ssl.c>
    <VirtualHost _default_:443>
        SSLEngine on
        SSLCertificateFile /etc/apache2/ssl/rvd_server_cert.cer
        SSLCertificateKeyFile /etc/apache2/ssl/rvd_server.key
        SSLCertificateChainFile /etc/apache2/ssl/rvd_server_interm.cer
