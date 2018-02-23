use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Copy;
use Test::More;
use Test::SQL::Data;

use v5.22; use feature qw(signatures);
no warnings "experimental::signatures";

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($test->connector, $FILE_CONFIG);

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my @VMS = vm_names();
my $USER = create_user("foo","bar");
#######################################################################33

sub test_create_domain {
    my $vm_name = shift;
    my $create_swap = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my @arg_create = (arg_create_dom($vm_name)
        ,id_owner => $USER->id
        ,name => $name
    );
    push @arg_create, (swap => 128*1024*1024)   if $create_swap;

    my $domain;
    eval { $domain = $vm->create_domain(@arg_create) };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}

sub test_add_volume {
    my $vm = shift;
    my $domain = shift;
    my $volume_name = shift or confess "Missing volume name";
    my $swap = shift;

    $domain->shutdown_now($USER) if $domain->is_active;

    my @volumes = $domain->list_volumes();

#    diag("[".$domain->vm."] adding volume $volume_name to domain ".$domain->name);

    $domain->add_volume(name => $domain->name.".$volume_name", size => 512*1024 , vm => $vm
        ,swap => $swap);

    my ($vm_name) = $vm->name =~ /^(.*)_/;
    my $vmb = rvd_back->search_vm($vm_name);
    ok($vmb,"I can't find a VM ".$vm_name) or return;
    my $domainb = $vmb->search_domain($domain->name);
    my @volumesb2 = $domainb->list_volumes();

    my $domain_xml = '';
    $domain_xml = $domain->domain->get_xml_description()    if $vm->type =~ /kvm|qemu/i;
    ok(scalar @volumesb2 == scalar @volumes + 1,
        "[".$domain->vm."] Domain ".$domain->name." expecting "
            .(scalar @volumes+1)." volumes, got ".scalar(@volumesb2)
            .Dumper(\@volumes)."\n".Dumper(\@volumesb2)."\n"
            .$domain_xml)
        or exit;


    my @volumes2 = $domain->list_volumes();

    ok(scalar @volumes2 == scalar @volumes + 1,
        "[".$domain->vm."] Domain ".$domain->name." expecting "
            .(scalar @volumes+1)." volumes, got ".scalar(@volumes2))
        or exit;
}

sub test_prepare_base {
    my $vm_name = shift;
    my $domain = shift;

    my @volumes = $domain->list_volumes();
#    diag("[$vm_name] preparing base for domain ".$domain->name);
    my @img;
    eval {@img = $domain->prepare_base( $USER) };
    is($@,'');
#    diag("[$vm_name] ".Dumper(\@img));


    my @files_base= $domain->list_files_base();
    return(scalar @files_base == scalar @volumes
        , "[$vm_name] Domain ".$domain->name
            ." expecting ".scalar @volumes." files base, got "
            .scalar(@files_base));

}

sub test_clone {
    my $vm_name = shift;
    my $domain = shift;

    my @volumes = $domain->list_volumes();

    my $name_clone = new_domain_name();
#    diag("[$vm_name] going to clone from ".$domain->name);
    $domain->is_public(1);
    my $domain_clone = $RVD_BACK->create_domain(
        name => $name_clone
        ,id_owner => $USER->id
        ,id_base => $domain->id
        ,vm => $vm_name
    );
    ok($domain_clone);
    ok(! $domain_clone->is_base,"Clone domain should not be base");

    my @volumes_clone = $domain_clone->list_volumes();

    ok(scalar @volumes == scalar @volumes_clone
        ,"[$vm_name] ".$domain->name." clone to $name_clone , expecting "
            .scalar @volumes." volumes, got ".scalar(@volumes_clone)
       ) or do {
            diag(Dumper(\@volumes,\@volumes_clone));
            exit;
    };

    my %volumes_clone = map { $_ => 1 } @volumes_clone ;

    ok(scalar keys %volumes_clone == scalar @volumes_clone
        ,"check duplicate files cloned ".join(",",sort keys %volumes_clone)." <-> "
        .join(",",sort @volumes_clone));

    return $domain_clone;
}

sub test_files_base {
    my ($vm_name, $domain, $volumes) = @_;
    my @files_base= $domain->list_files_base();
    ok(scalar @files_base == scalar @$volumes, "[$vm_name] Domain ".$domain->name
            ." expecting ".scalar @$volumes." files base, got ".scalar(@files_base)) or exit;

    my %files_base = map { $_ => 1 } @files_base;

    ok(scalar keys %files_base == scalar @files_base
        ,"check duplicate files base ".join(",",sort keys %files_base)." <-> "
        .join(",",sort @files_base));

    if ($vm_name eq 'KVM'){
        for my $volume ($domain->list_volumes) {
            my $info = `qemu-img info $volume`;
            my ($backing) = $info =~ m{(backing.*)}gm;
            like($backing,qr{^backing file\s*:\s*.+},$info) or exit;
        }
    }

    $domain->stop if $domain->is_active;
    eval { $domain->start($USER) };
    ok($@,"Expecting error, got : '".($@ or '')."'");
    ok(!$domain->is_active,"Expecting domain not active");
    $domain->shutdown_now($USER)    if $domain->is_active;
}

sub test_domain_2_volumes {

    my $vm_name = shift;
    my $vm = $RVD_BACK->search_vm($vm_name);

    my $domain2 = test_create_domain($vm_name);
    test_add_volume($vm, $domain2, 'vdb');

    my @volumes = $domain2->list_volumes;
    ok(scalar @volumes == 2
        ,"[$vm_name] Expecting 2 volumes, got ".scalar(@volumes));

    ok(test_prepare_base($vm_name, $domain2));
    ok($domain2->is_base,"[$vm_name] Domain ".$domain2->name
        ." sould be base");
    test_files_base($vm_name, $domain2, \@volumes);

    my $domain2_clone = test_clone($vm_name, $domain2);
    
    test_add_volume($vm, $domain2, 'vdc');

    @volumes = $domain2->list_volumes;
    ok(scalar @volumes == 3
        ,"[$vm_name] Expecting 3 volumes, got ".scalar(@volumes));

}

sub test_domain_n_volumes {

    my $vm_name = shift;
    my $n = shift;

    my $vm = $RVD_BACK->search_vm($vm_name);

    my $domain = test_create_domain($vm_name);
    diag("Creating domain ".$domain->name." with $n volumes");

    test_add_volume($vm, $domain, 'vdb',"swap");
    for ( reverse 3 .. $n) {
        my $vol_name = 'vd'.chr(ord('a')-1+$_);
        test_add_volume($vm, $domain, $vol_name);
    }

    my @volumes = $domain->list_volumes;
    ok(scalar @volumes == $n
        ,"[$vm_name] Expecting $n volumes, got ".scalar(@volumes));

    ok(test_prepare_base($vm_name, $domain));
    ok($domain->is_base,"[$vm_name] Domain ".$domain->name
        ." sould be base");
    test_files_base($vm_name, $domain, \@volumes);

    my $domain_clone = test_clone($vm_name, $domain);

    my @volumes_clone = $domain_clone->list_volumes_target;
    ok(scalar @volumes_clone ==$n
        ,"[$vm_name] Expecting $n volumes, got ".scalar(@volumes_clone));

    return if $vm_name =~ /void/i;
    for my $vol ( @volumes_clone ) {
        my ($file, $target) = @$vol;
        like($file,qr/-$target-/);
    }
}

sub test_add_volume_path {
    my $vm_name = shift;

    my $vm = $RVD_BACK->search_vm($vm_name);

    my $domain = test_create_domain($vm_name);
    my @volumes = $domain->list_volumes();

    my $file_path = $vm->dir_img."/mock.img";

    open my $out,'>',$file_path or die "$! $file_path";
    print $out "hi\n";
    close $out;

    $domain->add_volume(path => $file_path);

    my $domain2 = $vm->search_domain($domain->name);
    my @volumes2 = $domain2->list_volumes();
    is(scalar @volumes2,scalar @volumes + 1);# or exit;

    $domain->remove(user_admin);
    unlink $file_path or die "$! $file_path"
        if -e $file_path;
}

sub test_domain_1_volume {
    my $vm_name = shift;
    my $vm = $RVD_BACK->search_vm($vm_name);

    my $domain = test_create_domain($vm_name);
    ok($domain->disk_size
            ,"Expecting domain disk size something, got :".($domain->disk_size or '<UNDEF>'));
    test_prepare_base($vm_name, $domain);
    ok($domain->is_base,"[$vm_name] Domain ".$domain->name." sould be base");
    my $domain_clone = test_clone($vm_name, $domain);
    $domain = undef;
    $domain_clone = undef;

}

sub test_domain_create_with_swap {
    test_domain_swap(@_,1);
}

sub test_domain_swap {
    my $vm_name = shift;
    my $create_swap = (shift or 0);

    my $vm = $RVD_BACK->search_vm($vm_name);

    my $domain = test_create_domain($vm_name, $create_swap);
    if ( !$create_swap ) {
        $domain->add_volume_swap( size => 128*1024*1024, target => 'vdb' );
    }

    ok(grep(/SWAP/,$domain->list_volumes),"Expecting a swap file, got :"
            .join(" , ",$domain->list_volumes));
    for my $file ($domain->list_volumes) {
        ok(-e $file,"[$vm_name] Expecting file $file");
    }
    $domain->start($USER);
    for my $file ($domain->list_volumes) {
        ok(-e $file,"[$vm_name] Expecting file $file");
    }
    $domain->shutdown_now($USER);
    for my $file ($domain->list_volumes) {
        ok(-e $file,"[$vm_name] Expecting file $file");
    }

    test_prepare_base($vm_name, $domain);
    ok($domain->is_base,"[$vm_name] Domain ".$domain->name." sould be base");

    my @files_base = $domain->list_files_base();
    ok(scalar(@files_base) == 2,"Expecting 2 files base "
        .Dumper(\@files_base)) or exit;

    #test files base must be there
    for my $file_base ( $domain->list_files_base ) {
        ok(-e $file_base,
                "Expecting file base created for $file_base");
    }
    $domain->is_public(1);
    my $domain_clone = $domain->clone(name => new_domain_name(), user => $USER);

    # after clone, the qcow file should be there, swap shouldn't
    for my $file_base ( $domain_clone->list_files_base ) {
        if ( $file_base !~ /SWAP/) {
            ok(-e $file_base,
                "Expecting file base created for $file_base")
            or exit;
        } else {
            ok(!-e $file_base
                ,"Expecting no file base created for $file_base")
            or exit;
        }
;
    }
    eval { $domain_clone->start($USER) };
    ok(!$@,"[$vm_name] expecting no error at start, got :$@");
    ok($domain_clone->is_active,"Domain ".$domain_clone->name
                                ." should be active");

    my $min_size = 197120 if $vm_name eq 'KVM';
    $min_size = 529 if $vm_name eq 'Void';
    # after start, all the files should be there
     my $found_swap = 0;
    for my $file ( $domain_clone->list_volumes) {
         ok(-e $file ,
            "Expecting file exists $file");
        if ( $file =~ /SWAP/) {
            $found_swap++;
            my $size = -s $file;
            copy($file, "$file.tmp");
            `/bin/cat $file.tmp >> $file`;
            ok(-s $file > $size);
            ok(-s $file > $min_size
                , "Expecting swap file bigger than $min_size, got :"
                    .-s $file);
        }
    }
    $domain_clone->shutdown_now($USER);
    if ( $create_swap ) {
        ok($found_swap, "Expecting swap files , got :$found_swap") or exit;
    }

    # after shutdown, the qcow file should be there, swap be empty
    for my $file( $domain_clone->list_volumes) {
        ok(-e $file,
                "Expecting file exists $file")
            or exit;
        next if ( $file!~ /SWAP/);

        ok(-s $file <= $min_size
            ,"[$vm_name] Expecting swap $file size <= $min_size , got :".-s $file)

    }

}

sub test_search($vm_name) {
    my $vm = rvd_back->search_vm($vm_name);
    $vm->set_default_storage_pool_name('default') if $vm eq 'KVM';

    my $file_old = $vm->search_volume_path("file.iso");
    unlink $file_old if -e $file_old;

    $vm->default_storage_pool_name('default');

    my $file_out = $vm->dir_img."/file.iso";

    open my $out,">",$file_out or do {
        warn "$! $file_out";
        return;
    };
    print $out "foo.bar\n";
    close $out;

    $vm->refresh_storage();

    my $file = $vm->search_volume_path("file.iso");
    is($file_out, $file);

    my $file_re = $vm->search_volume_path_re(qr(file.*so));
    is($file_re, $file);

    my @isos = $vm->search_volume_path_re(qr(.*\.iso$));
    ok(scalar @isos,"Expecting isos, got : ".Dumper(\@isos));
}

#######################################################################33

remove_old_domains();
remove_old_disks();

for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM");

    my $vm;
    eval { $vm = $RVD_BACK->search_vm($vm_name) } if $RVD_BACK;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok("Ravada::VM::$vm_name");

        test_domain_swap($vm_name);
        test_domain_create_with_swap($vm_name);
        test_domain_1_volume($vm_name);
        test_domain_2_volumes($vm_name);
        for ( 3..6) {
            test_domain_n_volumes($vm_name,$_);
        }
        test_search($vm_name);

        test_add_volume_path($vm_name);
    }
}

remove_old_domains();
remove_old_disks();

done_testing();

