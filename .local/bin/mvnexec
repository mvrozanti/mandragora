#!/bin/bash
filet="$1"
mainClass_path="`realpath $filet | sed 's/.*\/java\/\(.*\)\.java/\1/g' | tr / . `"
curdir="`pwd`"
while [[ ! "`ls | grep pom.xml`" ]]; do
    cd ..
done
mvn exec:java -Dexec.mainClass="$mainClass_path"
