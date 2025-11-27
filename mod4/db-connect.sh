#!/bin/bash

# 接続情報を直接指定
DB_HOST="example.com"
DB_USER="myuser"
DB_PASS="mypassword"
DB_NAME="mydatabase"

# MySQL データベース に接続
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME
