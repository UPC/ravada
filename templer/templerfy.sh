#!/bin/bash
#TODO
# pod2html.pl
PATH1="/src/ravada"

echo "change repo directory..."
eval cd ~$PATH1
git checkout master && echo "Checkout master..."|| echo "Checkout master failed!";exit
eval mkdir -p ~$PATH1/documentation/docs ~$PATH1/documentation/devel-docs
mkdir -p /tmp/mds/docs /tmp/mds/devel-docs
cp docs/* /tmp/mds/docs
cp devel-docs/* /tmp/mds/devel-docs
git checkout gh-pages && echo "Checkout gh-pages..."|| echo "Checkout gh-pages failed!";exit
mkdir -p templer/input/docs templer/input/devel-docs
#rm documentation/docs/* documentation/devel-docs/*
for i in `ls /tmp/mds/docs/*.md`;do
    NAME=`basename $i .md`
    echo -e "title: ${NAME//_/ }\n----\n$(cat $i)" > $i
    eval cp $i ~$PATH1/templer/input/docs/
done

for i in `ls /tmp/mds/devel-docs/*.md`;do
    NAME=`basename $i .md`
    echo -e "title: ${NAME//_/ }\n----\n$(cat $i)" > $i
    eval cp $i ~$PATH1/templer/input/devel-docs/
done

#Run templer and generate the output in 
eval cd ~$PATH1/templer
echo "Generation static pages..."
templer
echo "Deleting input directory..."
echo "***********************************************"
echo "***********************************************"
echo "*                                             *"
echo "*  Remember to upload to git, with git push   *"
echo "*                                             *"
echo "***********************************************"
echo "***********************************************"
rm -rf input/docs/* input/devel-docs/* 

#Delete al temp files
rm -rf /tmp/mds
