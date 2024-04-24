Service Status
==============

Health and monitoring data can be accessed from /status.json

Configuration
-------------

Add this entry to /etc/rvd_front.conf

::

    ,status => {
      allowed => [
        '127.0.0.1'
        ,'ip1.domain'
        ,'ip2.domain'
      ]

