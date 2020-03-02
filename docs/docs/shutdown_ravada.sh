#!/bin/bash
#script to shutdown the ravada server

pid_front=$(pidof './script/rvd_front')
if [ -n "$pid_front" ];then
    echo "Shutting down rvd_front"
    sudo kill -15 $pid_front
else
    echo rvd_front already down
fi

pid_back=$(pidof -x './script/rvd_back')
if [ -n "$pid_back" ];then
    echo "Shutting down rvd_back"
    sudo kill -15 $pid_back
else
    echo rvd_back already down
fi
