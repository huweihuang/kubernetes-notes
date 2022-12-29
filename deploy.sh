#!/bin/bash
set -x
set -e

MESSAGE=$1

# update blog in blog-source repo
NOTE_NAME="kubernetes-notes"
BLOG_SOURCE_DIR="../blog-source/${NOTE_NAME}"
MASTER_DIR="$(pwd)"
GHPAGE_DIR="${MASTER_DIR}/gh-pages"

clean and copy blog
rm -fr $(ls | grep -v -E 'node_modules|book.json|README.md|SUMMARY.md|.gitignore|LICENSE|gh-pages|deploy.sh|code-analysis')
cp -fr ${BLOG_SOURCE_DIR}/* ./

# clone gh-pages
rm -fr gh-pages
git clone -b gh-pages https://github.com/huweihuang/${NOTE_NAME}.git gh-pages

# build
gitbook build

# clean GHPAGE_DIR
rm -fr ${GHPAGE_DIR}/*

# copy _book to GHPAGE_DIR
cp -fr ${MASTER_DIR}/_book/* ${GHPAGE_DIR}
cp -fr ${MASTER_DIR}/README.md ${GHPAGE_DIR}

# git commit
cd ${GHPAGE_DIR}
git add --all
git commit -m "${MESSAGE}"
git push origin gh-pages