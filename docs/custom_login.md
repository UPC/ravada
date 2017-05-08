Create a custom login template
------------------------------

If you need custom login template create one and save it in templates/main/custom, e.g. custom_login.html.ep


Configuration
-------------

Add your template in /etc/rvd_front.conf

  ,login_custom => 'main/custom/custom_login'


Path for CSS, js and images
---------------------------

If CSS, js or images are needed save in: public/css/custom, public/js/custom or public/img/custom respectively.

Make sure your CSS, JS or images in custom template refers to those paths.

Restart frontend
----------------

Finally restart rvd_front: 
    
    $ sudo systemctl restart rvd_front
