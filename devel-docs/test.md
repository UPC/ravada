
#Testing environment

Previously [install](https://github.com/frankiejol/Test-SQL-Data/blob/master/INSTALL.md) TEST::SQL::DATA module.

In project root run:

    $ perl Makefile.PL
    $ sudo make test 
    
At the end, in "Test Summary Report" you can check the result.

If something goes wrong you see: 
    Result: FAIL    

##Run a single test

    $ make && sudo prove -b t/lxc/*t
