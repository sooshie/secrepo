#!/bin/bash

sed -n 's/.*href="\([^"]*\).*/\1/p' index.html > urls.txt
while read url; do
    curl -Ifs -o /dev/null "$url"
    retval=`echo $?`
    if [ "$retval" -gt "0" ]; then
        echo "$url - $retval"
    fi         
done < urls.txt
