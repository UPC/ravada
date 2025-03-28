
Nginx as reverse proxy
======================

Remark
------
This instruction was tested on **nginx 1.26.3** *(stable version)* and **Debian12**,
but must work on any other major Linux distributions.
    
Install nginx (fast way)
------------------------
The main problem of this option is that some distributions by default install ancient versions of **nginx**

* For **Debian**/**Ubuntu**

::

 sudo apt install nginx

* For **RedHat**/**Fedora**

::

 sudo dnf install nginx

Install nginx (recommended way)
-------------------------------

Install **nginx** according to `Nginx documentations <https://nginx.org/en/linux_packages.html>`_
    

Configure Hypnotoad proxy
-------------------------
    
**Hypnotoad** is an engine that runs the web Ravada frontend.
First of all you need to tell **hypnotoad** we are behind a proxy.
This allows Mojolicious to automatically pick up the **X-Forwarded-For**
and **X-Forwarded-Proto** headers.

Edit the file **/etc/rvd_front.conf** and make sure there is a line with *proxy => 1*
inside hypnotoad. 
Change the line starting with *listen* to *listen => ['http://127.0.0.1:8081']*. We restrict **hypnotoad** to listen on **localhost** only.
    
::

   hypnotoad => {
       pid_file => '/var/run/ravada/rvd_front.pid'
      ,listen => ['http://127.0.0.1:8081']
      ,proxy => 1
   }

Restart the front server to reload its configuration:

::

    sudo systemctl restart rvd_front

Create Diffie-Hellman key
-------------------------

Generation of 4096 bit key may take a long time on slow machines or VMs, so take a break and get a cup of coffee.
::

 sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096



Configure nginx
---------------

**/etc/nginx/nginx.conf**

What's changed:

* added tweaks for websockets support 
* better logging

::

  user  nginx;
  worker_processes  auto;

  error_log  /var/log/nginx/error.log;
  pid        /var/run/nginx.pid;


  events {
      worker_connections  1024;
  }


  http {
      include       /etc/nginx/mime.types;
      default_type  application/octet-stream;

      log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';

      # For websockets
      map $http_upgrade $connection_upgrade {
          default upgrade;
          '' close;
    }

      # Don't log access from local Zabbix agent
      map $request_uri $loggable {
          / 0;
          default 1;
    }

    # combined format is recommended for log analyzers
    access_log /var/log/nginx/access.log combined if=$loggable;

    #access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    include /etc/nginx/conf.d/*.conf;
  }

----

**/etc/nginx/conf.d/default.conf**

What's changed:

* added HTTP->HTTPS redirect, 
* better logging
* added support for .well-known *(useful for some SSL-agents, e.g. acme.sh)*
* enabled statistics support for local Zabbix-agent

::

  server {
      listen       80;
      server_name  _;

      access_log  /var/log/nginx/access.log combined if=$loggable;
      error_log /var/log/nginx/error.log;

      ###########################
      # Basic security measures #
      ###########################

      # Block server info
      server_tokens off;

      ##################
      # Other settings #
      ##################
      index index.html index.htm;

      #####################
      # Paths to catalogs #
      #####################

      # Path to root catalog by default
      root /usr/share/nginx/html;

      # Enable statistics for Zabbix agent
      location = /basic_status {
          stub_status;
          allow 127.0.0.1;
          allow ::1;
          deny all;
          access_log    off;
          log_not_found off;
      }

      # For acme.sh SSL-bot
      location /.well-known {
          root /var/www;
      }

      # HTTP -> HTTPS redirect for all sites
      location / {
          return 301 https://$host$request_uri;
      }

      #error_page  404              /404.html;

      # redirect server error pages to the static page /50x.html
      #
      error_page   500 502 503 504  /50x.html;
      location = /50x.html {
          root   /usr/share/nginx/html;
      }
  }

----

**/etc/nginx/conf.d/ravada.example.com.conf**

Do not forget:

* Change **ravada.example.com** to your hostname
* Check path to SSL-certs and keys
* Check if logging catalog exists and is correct

::

    server {
        listen       443 ssl;
        http2 on;
        server_name  ravada.example.com;

        # Path to log files
        access_log  /var/log/nginx/ravada.example.com/access.log combined if=$loggable;
        error_log   /var/log/nginx/ravada.example.com/error.log;

        ##########################
        # SSL settings for HTTPS #
        ##########################

        resolver 8.8.8.8 8.8.4.4;

        # Path to RSA cert and key
        ssl_certificate /opt/certagent/ssl-certs/ravada.example.com/fullchain.cer;
        ssl_certificate_key /opt/certagent/ssl-certs/ravada.example.com/ravada.example.com.key;

        # Path to ECC cert and key
        ssl_certificate /opt/certagent/ssl-certs/ravada.example.com_ecc/fullchain.cer;
        ssl_certificate_key /opt/certagent/ssl-certs/ravada.example.com_ecc/ravada.example.com.key;

        ssl_session_timeout 1d;
        ssl_session_cache shared:MozSSL:10m;  # about 40000 sessions
        ssl_session_tickets off;

        # Path to Diffie-Hellman key
        ssl_dhparam /etc/ssl/certs/dhparam.pem;

        # Ciphers settings (good but not paranoid)
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

        ###########################
        # Basic security measures #
        ###########################

        # Block server info
        server_tokens off;

        ##################
        # Other settings #
        ##################
        index index.html index.htm;

        #####################
        # Paths to catalogs #
        #####################

        # Path to root catalog by default
        root /usr/share/nginx/html;

        # Redirect to Ravada
        location / {

            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto "https";

            proxy_set_header Host $host;

            proxy_pass http://127.0.0.1:8081$request_uri;
            #root /var/www;
        }

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/share/nginx/html;
        }

    }

----

Create log dir for your site:

::

  sudo mkdir -p /var/log/nginx/ravada.example.com

Create dir for **.well-known**

* For **Debian**/**Ubuntu**

::

 sudo mkdir -p /var/www
 sudo chown -R www-data:www-data /var/www

* For **RedHat**/**Fedora**

::

 sudo mkdir -p /var/www
 sudo chown -R nginx:nginx /var/www

Final check
-----------

::

  sudo nginx -t

Correct any errors if they appear.

Start nginx
-----------

::

  sudo systemctl enable nginx
  sudo systemctl restart nginx

Superfinal check
----------------

This command
::

  sudo netstat -tulpn

must show something similar to:

::

  Active Internet connections (only servers)
  Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
  tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      2819/nginx: master  
  tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      723/sshd: /usr/sbin 
  tcp        0      0 0.0.0.0:443             0.0.0.0:*               LISTEN      2819/nginx: master  
  tcp        0      0 127.0.0.1:8081          0.0.0.0:*               LISTEN      2835/rvd_front      
  tcp        0      0 127.0.0.1:8461          0.0.0.0:*               LISTEN      591/python3         
  tcp6       0      0 :::22                   :::*                    LISTEN      723/sshd: /usr/sbin 
  ...          

Last advice
-----------
* Remember to add your **hostname** in **Admin Tools -> Settings -> Frontend -> Content Security Policy**
* And make sure that **80/tcp** and **443/tcp** ports are open for access from the internet.
