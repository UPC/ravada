#!/bin/bash
#script to start ravada server

display_usage()
{
	echo "./start_ravada"
	echo "./start_ravada 1 (messages not shown to terminal)"
}

if [ "$1" == "-h" ]
then
	display_usage
	exit 1
else
	SHOW_MESSAGES=$1
    export PERL5LIB="./lib"
    export MOJO_REVERSE_PROXY=1
	if [ "$SHOW_MESSAGES" == "1" ]
	then
	   morbo -m development -v ./script/rvd_front > /dev/null 2>&1 &
	   sudo PERL5LIB=./lib ./script/rvd_back --debug > /dev/null 2>&1 &
	else
	   morbo -m development -v ./script/rvd_front &
       sudo PERL5LIB=./lib ./script/rvd_back --debug &
	fi
	echo "Server initialized succesfully."
fi

