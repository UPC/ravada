#!/bin/bash

read -r -p "Remove images (front - back - mysql) - Are you sure? [Y/n]" response
response=${response,,} # tolower
if [[ $response =~ ^(yes|y| ) ]] || [[ -z $response ]]; then
	docker image rm mariadb:11.4 -f
	docker image rm dockerfy-ravada-back:latest -f
	docker image rm dockerfy-ravada-front:latest -f
fi

read -r -p "Remove volume dockerfy_sshkeys - Are you sure? [Y/n]" response
response=${response,,} # tolower
if [[ $response =~ ^(yes|y| ) ]] || [[ -z $response ]]; then
	docker volume rm dockerfy_sshkeys
fi

read -r -p "Remove persistent data (/opt/ravada/) - Are you sure? [Y/n]" response
response=${response,,} # tolower
if [[ $response =~ ^(yes|y| ) ]] || [[ -z $response ]]; then
	rm -rfv /opt/ravada/*
fi
