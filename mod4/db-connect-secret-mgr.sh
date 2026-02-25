#!/bin/bash

# Secrets Manager から接続情報を取得（JSON形式）
SECRET=$(aws secretsmanager get-secret-value --secret-id "mydatabase/credentials" --query "SecretString" --output json)


# JSONから各値を抽出
DB_HOST=$(echo $SECRET | jq -r '.host')
DB_USER=$(echo $SECRET | jq -r '.username')
DB_PASS=$(echo $SECRET | jq -r '.password')
DB_NAME=$(echo $SECRET | jq -r '.database')

# MySQLデータベースに接続
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME
