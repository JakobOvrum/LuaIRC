#!/bin/bash

if [ "$TRAVIS_REPO_SLUG" == "JakobOvrum/LuaIRC" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "master" ]; then

  echo -e "Generating luadoc...\n"

  git config --global user.email "travis@travis-ci.org"
  git config --global user.name "travis-ci"
  git clone --quiet --branch=gh-pages https://${GH_TOKEN}@github.com/${TRAVIS_REPO_SLUG} gh-pages > /dev/null

  cd gh-pages
  git rm -rf ./doc
  sh ./generate.sh
  git add -f ./doc
  git commit -m "Lastest documentation on successful travis build $TRAVIS_BUILD_NUMBER auto-pushed to gh-pages"
  git push -fq origin gh-pages > /dev/null

  echo -e "Published luadoc to gh-pages.\n"
fi
