#!/bin/bash
#TODO
# pod2html.pl
PATH1="/src/ravada"

echo "change repo directory..."
eval cd ~$PATH1
git checkout master && echo "Checkout master..."|| echo "Checkout master failed!"
eval mkdir -p ~$PATH1/documentation/docs ~$PATH1/documentation/devel_docs
mkdir -p /tmp/mds/docs /tmp/mds/devel_docs
cp docs/* /tmp/mds/docs
cp devel_docs/* /tmp/mds/devel_docs
git checkout gh-pages && echo "Checkout gh-pages..."|| echo "Checkout gh-pages failed!"
mkdir -p templer/input/docs templer/input/devel_docs
rm documentation/docs/* documentation/devel_docs/*
for i in `ls /tmp/mds/docs/*.md`;do
    NAME=`basename $i .md`
    echo -e "title: ${NAME//_/ }\n----\n$(cat $i)" > $i
    eval cp $i ~$PATH1/templer/input/docs/
done

for i in `ls /tmp/mds/devel_docs/*.md`;do
    NAME=`basename $i .md`
    echo -e "title: ${NAME//_/ }\n----\n$(cat $i)" > $i
    eval cp $i ~$PATH1/templer/input/devel_docs/
done

#Run templer and generate the output in 
eval cd ~$PATH1/templer
echo "Generation static pages..."
templer
echo "Deleting input directory..."
echo "Remember upload to git, with git push"
rm -rf input/docs/* input/devel_docs/* 

#Delete al temp files
rm -rf /tmp/mds
