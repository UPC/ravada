
#First run

When the server is running connect it at http://servername:3000/

Start creating a domain base for the users. As long as there are no, it will show this:

    No base domains available

#Domain Bases

Domain bases are used to create virtual hosts. Build systems in the Hypervisor, then
prepare them with rvd_back.

One way to build base images is using virt-manager. Install it and create a new virtual machine there. Once it is done, prepare it to use it as a base for the ravada:

    $ sudo ./bin/rvd_back.pl --prepare

