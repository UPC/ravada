How to create tests
===================

We take great care on crafting a stable product. One of the main keys is
creating `automated tests <http://ravada.readthedocs.io/en/latest/devel-docs/test.html>`__
to check everytying works as expected.

As soon as a problem is found, the very first thing is to be able to reproduce
it and then create a test case. Make this test fail, so when the code is fixed
it should succeed.

Test Requirements
-----------------

Tests run on an blank *sqlite* database that is an exact replica of the real *mysql* database
used in production. The fields and data is the same but the data is empty. So you can run
the tests in the same host when a real *Ravada* service is running.

To ease the process of creating this *mock* database it is required to install the
module `Test-SQL-Data <https://github.com/frankiejol/test-sql-data>`__ .


Test Directory
--------------

Create a file in the directory *t* with the *.t* extension. There are subdirs there,
try to put the file in one of them.

Test File Template
------------------

This is an empty tests that does nothing. It just loads a test environment with
a blank *sqlite* database. Notice there is a cleaning of the test environment
at the begin and end of the tests. This removes possible old leftovers from
failed tests.

Let's create a simple test that checks if a virtual machine is removed.
So we edit a new file called *30_remove.t* in the directory *ravada/t*.

::

    #!perl
    
    use Test::More;
    use Test::SQL::Data;
    
    use lib 't/lib';
    use Test::Ravada;
    
    # create the mock database
    my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
    
    # init ravada for testing
    init($test->connector);
    
    ##############################################################################
    
    clean();
    
    use_ok('Ravada');
    
    clean();
    
    done_testing();


Run
---

The prove command runs a test file, before you have to prepare the
libraries and environment. Tests create remove and manage virtual machines. That
requires root access to the system, so sudo should be used to run the tests.


The best thing is to run it this way:

::

    $ cd ravada
    $ perl Makefile.PL && make && sudo prove -b t/30_remove.t
    t/user/30_grant_remove.t .. ok
    All tests successful.
    Files=1, Tests=1,  2 wallclock secs ( 0.02 usr  0.00 sys +  0.57 cusr  0.10 csys =  0.69 CPU)
    Result: PASS

Trying the Virtual Managers
---------------------------

It is advisable to run the tests on all the virtual managers known to Ravada.
To do so we add a loop that tries to load each of them.

Now the test file is like this:

::

    #!perl
    
    use Test::More;
    use Test::SQL::Data;
    
    use lib 't/lib';
    use Test::Ravada;
    
    my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
    
    init($test->connector);
    
    ##############################################################################
    
    clean();
    
    use_ok('Ravada');
    
    for my $vm_name ( vm_names() ) {
    
        my $vm;
        eval { $vm = rvd_back->search_vm($vm_name) };
    
        SKIP: {
            my $msg = "SKIPPED test: No $vm_name VM found ";
            if ($vm && $vm_name =~ /kvm/i && $>) {
                $msg = "SKIPPED: Test must run as root";
                $vm = undef;
            }
    
            diag($msg)      if !$vm;
            skip $msg       if !$vm;
    
            diag("Testing remove on $vm_name");
        }
    }
    
    clean();
    
    done_testing();

We also have a *mock* virtual
manager that does nothing but it is used to test generic virtual machines. It is
called the *Void* VM and it only should be used for testing. So the output of running
the test should be like this:


::

    $ perl Makefile.PL && make && sudo prove -b t/30_remove.t
    t/user/30_grant_remove.t .. 1/?
    # Testing remove on KVM
    # Testing remove on Void
    t/user/30_grant_remove.t .. ok
    All tests successful.

Test Example: check machine removal
-----------------------------------

Now the test is there, let's make it check something, like if a virtual machine
has been removed.

::

    #!perl
    
    use Test::More;
    use Test::SQL::Data;
    
    use lib 't/lib';
    use Test::Ravada;
    
    my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
    
    init($test->connector);
    
    ##############################################################################
    
    sub test_remove {
        my $vm = shift;
    
        my $domain = create_domain($vm->type);
    #    $domain->remove( user_admin );
    
        my $domain2 = $vm->search_domain( $domain->name );
        ok(!$domain2,"[".$domain->type."] expecting domain already removed");
    
    }
    ##############################################################################
    
    clean();
    
    use_ok('Ravada');
    
    for my $vm_name ( vm_names() ) {
    
        my $vm;
        eval { $vm = rvd_back->search_vm($vm_name) };
    
        SKIP: {
            my $msg = "SKIPPED test: No $vm_name VM found ";
            if ($vm && $vm_name =~ /kvm/i && $>) {
                $msg = "SKIPPED: Test must run as root";
                $vm = undef;
            }
    
            diag($msg)      if !$vm;
            skip $msg       if !$vm;
    
            diag("Testing remove on $vm_name");
    
            test_remove($vm);
        }
    }
    
    clean();
    
    done_testing();

Now let's run the test:

::

    $ perl Makefile.PL && make && sudo prove -b t/30_remove.t
    t/user/30_grant_remove.t .. 1/?
    # Texting remove on KVM
    t/user/30_grant_remove.t .. 3/?
    #   Failed test '[KVM] expecting domain already removed'
    #   at t/user/30_grant_remove.t line 22.
    # Texting remove on Void
    
    #   Failed test '[Void] expecting domain already removed'
    #   at t/user/30_grant_remove.t line 22.
    # Looks like you failed 2 tests of 7.
    t/user/30_grant_remove.t .. Dubious, test returned 2 (wstat 512, 0x200)
    Failed 2/7 subtests
    
    Test Summary Report
    -------------------
    t/user/30_grant_remove.t (Wstat: 512 Tests: 7 Failed: 2)
      Failed tests:  4, 7


Whoah there ! It looks like the test failed, of course, someone commented
the line 19 that actually removes the machine. Uncomment it and run the tests
again. It should return OK.


