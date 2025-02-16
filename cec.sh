#!/bin/sh

for i in 1 2 3 4 5
m^X Exit      ^R Read File  ^\ Replace    ^U Paste      ^J Justify
   echo $1 '0.0.0.0' | cec-client -s -d 1
done
