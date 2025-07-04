#!/bin/bash
set -x
set -e

MESSAGE=$1
DEPLOY_MODE=$2

# update blog in blog-source repo
NOTE_NAME="kubernetes-notes"
BLOG_SOURCE_DIR="../blog-source/${NOTE_NAME}"
MASTER_DIR="$(pwd)"
GHPAGE_DIR="${MASTER_DIR}/gh-pages"

# clean and copy blog
rm -fr $(ls | grep -v -E 'node_modules|book.json|README.md|SUMMARY.md|.gitignore|LICENSE|gh-pages|deploy.sh|code-analysis')
cp -fr ${BLOG_SOURCE_DIR}/* ./

# clean GHPAGE_DIR
if [ ! -d $GHPAGE_DIR  ];then
    git clone -b gh-pages https://github.com/huweihuang/${NOTE_NAME}.git gh-pages
fi
rm -fr ${GHPAGE_DIR}/*

# build
gitbook build

# copy _book to GHPAGE_DIR
cp -fr ${MASTER_DIR}/_book/* ${GHPAGE_DIR}
cp -fr ${MASTER_DIR}/README.md ${GHPAGE_DIR}
cp -fr ${MASTER_DIR}/SUMMARY.md ${GHPAGE_DIR}

if [ $2 = "dry-run" ];then
    echo "gitbook server dry run"
    gitbook serve
else
    # git commit
    cd ${GHPAGE_DIR}
    git add --all
    git config user.name huweihuang
    git config user.email huweihuang@foxmail.com
    git commit -m "${MESSAGE}"
    git push origin gh-pages
fi
