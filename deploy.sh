#!/bin/sh

echo "=========git pull======="
git pull
 

echo "=========deploy======="
git add . && git commit -m "deploy" && git push

echo "=========git build======="
git build 

echo "=========git serve======="
git serve



