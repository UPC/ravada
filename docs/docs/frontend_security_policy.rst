Frontend Security Policy
========================

If you want to add custom third party HTML inside Ravada you may want
to change the security policy headers. That may be necessary when you
are using custom widgets, footers or login pages.

Default Security Policy
-----------------------

Default Security Policy only allows content from the Ravada frontend server
or its CDN libraries, such as bootstrap, fonts and others we are using.

Custom Security Policy
----------------------

Single Entry
~~~~~~~~~~~~

The easiest way to allow third party content attached to the frontend is
adding this single configuration in /etc/rvd_front.conf

::

      ,security_policy => 'foo.bar.com'

This will allow any kind of content from this domain inside the Ravada web
pages.

Multiple source policies
~~~~~~~~~~~~~~~~~~~~~~~~

If you want to be more specific about what content you are allowed, or you
want to have different sources, you can do it this way:

::

      ,security_policy => {
        default_src => 'foodefault.bar.com'
        ,frame_src => 'fooframe.bar.com'
        ,script_src => 'fooscript.bar.com'
      }

These three entries were enough to allow extra content in our tests, but
there are many sources policies you can change.

This is a list of all of the security policies you can enable in this config:

* connect_src
* default_src
* frame_src
* font_src
* media_src
* object_src
* style_src
* script_src

