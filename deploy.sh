#!/bin/bash
# run in MASTER_DIR
set -x
set -e

MESSAGE=$1

MASTER_DIR="$(pwd)"
GHPAGE_DIR="${MASTER_DIR}/gh-pages"
# CODING_DIR="${GITBOOK_DIR}/${PROGRAM}-coding-pages"

# build
gitbook build

# clean GHPAGE_DIR
rm -fr ${GHPAGE_DIR}/*
# rm -fr ${CODING_DIR}/*

# copy _book to GHPAGE_DIR
cp -fr ${MASTER_DIR}/_book/* ${GHPAGE_DIR}
cp -fr ${MASTER_DIR}/README.md ${GHPAGE_DIR}
# cp -fr ${MASTER_DIR}/_book/* ${CODING_DIR}
# cp -fr ${MASTER_DIR}/README.md ${CODING_DIR}

# git commit
cd ${GHPAGE_DIR}
git add --all
git commit -m "${MESSAGE}"
git push origin gh-pages

# cd ${CODING_DIR}
# git add --all
# git commit -m "${MESSAGE}"
# git push origin coding-pages
