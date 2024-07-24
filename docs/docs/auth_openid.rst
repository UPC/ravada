Auth OpenID
===========

OpenID authentication is used with Apache OpenID modules.

Apache Module
-------------

Install modules
~~~~~~~~~~~~~~~

::

 sudo apt install libapache2-mod-auth-openidc
 sudo a2enmod auth_openidc

Configure module
~~~~~~~~~~~~~~~

/etc/apache2/mods-available/auth_openidc.conf

At least you will need these provided by your organization openid server:

* Secret passphrase
* ProviderMetadataURL
* Client ID

::

  OIDCRedirectURI https://rvd_server.mydomain/login_openid/redirect_uri
  OIDCCryptoPassphrase SECRET
  OIDCProviderMetadataURL https://your.openid.server/.well-known/openid-configuration
  OIDCScope "openid email profile"
  OIDCResponseType "code"
  OIDCResponseMode query
  OIDCClientID YOUR_CLIENT_ID
  OIDCClientSecret SECRET
  OIDCPKCEMethod S256
  OIDCUserInfoSignedResponseAlg RS256
  OIDCCacheShmEntrySizeMax 32000
  <Location /login_openid>
     AuthType openid-connect
     Require valid-user
  </Location>

Restart Apache
~~~~~~~~~~~~~~

::

  sudo systemctl restart apache2

Other Options
~~~~~~~~~~~~~

Check official Apache OpenID documentation

https://github.com/OpenIDC/mod_auth_openidc/wiki

Login page
----------

Configure the login page for your Ravada server so users use this URL to authenticate

::

  /login_openid

