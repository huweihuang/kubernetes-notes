#!/bin/bash
# run in MASTER_DIR
set -x
set -e

MESSAGE=$1

PROGRAM="kubernetes"
GITBOOK_DIR="/Users/meitu/hexo/gitbook"
MASTER_DIR="${GITBOOK_DIR}/${PROGRAM}-notes"
GHPAGE_DIR="${GITBOOK_DIR}/${PROGRAM}-gh-pages"
CODING_DIR="${GITBOOK_DIR}/${PROGRAM}-coding-pages"

# build
gitbook build

# clean GHPAGE_DIR
rm -fr ${GHPAGE_DIR}/*
rm -fr ${CODING_DIR}/*

# copy _book to GHPAGE_DIR
cp -fr ${MASTER_DIR}/_book/* ${GHPAGE_DIR}
cp -fr ${MASTER_DIR}/README.md ${GHPAGE_DIR}
cp -fr ${MASTER_DIR}/_book/* ${CODING_DIR}
cp -fr ${MASTER_DIR}/README.md ${CODING_DIR}

# git commit
cd ${GHPAGE_DIR}
git add --all
git commit -m "${MESSAGE}"
git push origin gh-pages

cd ${CODING_DIR}
git add --all
git commit -m "${MESSAGE}"
git push origin coding-pages
