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

# clean GHPAGE_DIR
if [ ! -d $GHPAGE_DIR  ];then
    git clone https://github.com/huweihuang/blog.huweihuang.com.git gh-pages
fi
rm -fr ${GHPAGE_DIR}/*

# build
gitbook build

# copy _book to GHPAGE_DIR
cp -fr ${MASTER_DIR}/_book/* ${GHPAGE_DIR}
cp -fr ${MASTER_DIR}/README.md ${GHPAGE_DIR}

# git commit
cd ${GHPAGE_DIR}
git add --all
git commit -m "${MESSAGE}"
git push origin gh-pages