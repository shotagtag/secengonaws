# 🚀 KMS の暗号化(クライアント側)を体験してみましょう

## サーバー側暗号化 vs クライアント側暗号化

**サーバー側暗号化**は、データがAWSサービスに到着した後、サーバー側で暗号化を行う方式です。AWS KMSを使用する場合、AWSサービスとKMSが自動的に連携し、エンベロープ暗号化の一連の処理（データキー生成、暗号化、データキー自体の暗号化、平文データキーの破棄）を裏側で実行します。アプリケーション側では暗号化の実装が不要、またはオプション指定のみで済むため、開発負担が少ない方法です。

**クライアント側暗号化**は、データをAWSサービスに送信する前に、クライアント側で暗号化を行う方式です。KMSを用いたエンベロープ暗号化を実装する場合、アプリケーション側で暗号化処理を実装する必要があります。専用のSDKを使用することで実装負担を軽減できますが、今回は学習のために手動でエンベロープ暗号化の仕組みを体験してみましょう。

## LocalStackについて

LocalStackは、AWSサービスをローカル環境でシミュレートできるツールです。シュミレート環境上でS3やDynamoDBなどのサービスを試すことができます。今回はLocalStack上でS3環境を構築し、KMSで暗号化したデータを保存する練習を行います。

> **注意**: LocalStackはあくまでシミュレート環境です。本番のAWSとは動作が異なる場合があります。

## 環境準備

1. EC2インスタンス Command Host にログインします。

- チェックボックスを押後、接続をクリックします
    - ![image](https://github.com/user-attachments/assets/b95dddb7-9741-4b57-bfaa-58d74a3d42c3)
- セッションマネージャーで接続します
    - ![image](https://github.com/user-attachments/assets/3cd4696f-018d-49ce-b602-490cb612542b)

2. rootユーザーに切り替えます。
```bash
sudo su -
```

3. Dockerをインストールして起動し、LocalStackを起動します。
```bash
yum install -y docker
systemctl start docker
docker run -d --name localstack -p 4566:4566 -e SERVICES=s3 localstack/localstack
```

4. LocalStackにリクエストを送るためのコマンドを `awslocal` というalias(別名)として定義します。
```bash
alias awslocal="aws --endpoint-url=http://localhost:4566"
```

5. LocalStack 上に S3 バケットを作成します。
```bash
awslocal s3 mb s3://mybucket
```

6. バケットが作成されたことを確認します。
```bash
awslocal s3 ls
```

🎉これでLocalStack上でS3を使用する準備が整いました。以降はLocalStackのS3を仮のS3と見立てて進めます。

## AWS KMS で KMSキー(ルートキー)を作成

1. AWSマネジメントコンソールでKMSサービスへ移動します。
2. 左メニューから「カスタマー管理型のキー」をクリックします。
3. 「キーの作成」をクリックします。
4. 「キーを設定」ページで次のオプションを選択し、次のオプションが選択されているか確認します。
   - キーのタイプ : 対称
   - キーの使用方法 : 暗号化および復号化
5. 「次へ」をクリックします。
6. エイリアスに `myapp-kms-key` を入力し、下部の「確認にスキップ」をクリックします。
7. 確認画面をスクロールし、作成を完了します。

🎉これでKMSキー(ルートキー)が作成できました。

## クライアント側の暗号化をやってみましょう

ローカルでファイルをエンベロープ暗号化してLocalStack S3に送信します。

1. EC2インスタンスに再度ログインします。
   > まだセッションが残っていればそのまま使っても大丈夫です。

2. rootユーザーに切り替え、エイリアスを再設定します（新しいセッションの場合）。
```bash
sudo su -
alias awslocal="aws --endpoint-url=http://localhost:4566"
```

### データキーの生成

1. KMS API でデータキーを作成します。生成して、応答をJSONファイルに出力します。
```bash
aws kms generate-data-key --key-id alias/myapp-kms-key --key-spec AES_256 > datakey.json
```

2. KMSからの応答内容を確認してみましょう。ポイントとして平文データキーだけではなく、KMSキーで暗号化済みのデータキーも一緒に返してくれます。これによりKMS APIとのやりとりを減らすことができます。
```bash
cat datakey.json | jq .
```

応答の構造：
- `CiphertextBlob` には **base64エンコードされた暗号化データキー** が含まれます。
- `Plaintext` には **base64エンコードされた平文データキー** が含まれます。
- `KeyId` には **どのKMSキーでデータキーを暗号化したのか** がARNで書かれています。

### データキーの抽出

3. JSONから平文データキーを抽出します。AWS CLIはバイナリデータをbase64エンコードして返すため、デコードが必要です。
```bash
cat datakey.json | jq -r '.Plaintext' | base64 -d > plaintext_key.bin
```

4. JSONから暗号化データキーも抽出します。
```bash
cat datakey.json | jq -r '.CiphertextBlob' | base64 -d > encrypted_key.bin
```

### ファイルの暗号化

5. 暗号化するファイルを作成します。
```bash
echo 'Hello AWS KMS!' > original.txt
cat original.txt
```

6. 平文データキーを使ってファイルを暗号化します。OpenSSLのAES-256-CBCを使用します。
```bash
openssl enc -aes-256-cbc -in original.txt -out original.encrypted -pass file:./plaintext_key.bin
```

**コマンドの意味:**
- `openssl enc`: OpenSSLの暗号化コマンド
- `-aes-256-cbc`: AES 256ビット暗号化をCBCモードで使用
- `-in original.txt`: 暗号化する入力ファイル
- `-out original.encrypted`: 暗号化後の出力ファイル
- `-pass file:./plaintext_key.bin`: パスワード（データキー）をファイルから読み込む

7. 暗号化されたファイルを確認します（バイナリなので読めません）。
```bash
cat original.encrypted
```

### 暗号化ファイルと暗号化データキーをS3にアップロード

8. 暗号化されたデータファイルをLocalStack S3にアップロードします。
```bash
awslocal s3 cp original.encrypted s3://mybucket/
```

9. 暗号化されたデータキーもLocalStack S3にアップロードします。
```bash
awslocal s3 cp encrypted_key.bin s3://mybucket/
```

10. アップロードされたオブジェクトを確認します。
```bash
awslocal s3 ls s3://mybucket/
```

### セキュリティのためのクリーンアップ

11. 平文データキーと元ファイル、JSONファイルをローカルから削除します（セキュリティのため）。
```bash
rm plaintext_key.bin original.txt datakey.json
```

🎉 これで暗号化されたファイル(`original.encrypted`)と暗号化されたデータキー(`encrypted_key.bin`)がLocalStack S3に安全に保存されました！

## 🍵まとめ

このミニハンズオンで、エンベロープ暗号化を用いたクライアント側暗号化の基本の流れを体験しました：

1. **データキーの生成**: AWS KMSで平文データキーと暗号化データキーを生成
2. **データの暗号化**: 平文データキーを使ってファイルを暗号化
3. **暗号化したデータ、暗号化したデータキーを送信**: 暗号化されたファイルと暗号化されたデータキーをS3に保存
4. **平文データキーの破棄**: セキュリティのため平文データキーを削除

### ⚠️実際のアプリケーション開発では

今回は学習のために手動でエンベロープ暗号化を行いましたが、実際のアプリケーション開発では、AWSが提供する専用のSDKを使用することで、一連の処理を抽象化し実装の負担を減らせます：

- **Amazon S3の場合**: [S3 Client Encryption SDK](https://docs.aws.amazon.com/encryption-sdk/latest/developer-guide/s3-encryption-client.html)
- **DynamoDBの場合**: [DynamoDB Encryption Client](https://docs.aws.amazon.com/dynamodb-encryption-client/latest/devguide/what-is-ddb-encrypt.html)
- **汎用的な用途**: [AWS Encryption SDK](https://docs.aws.amazon.com/encryption-sdk/latest/developer-guide/introduction.html)

これらのSDKは、データキーの生成、暗号化、復号化、キーの管理といった複雑な処理を自動的に行ってくれるため、開発者はセキュアなアプリケーションを簡単に構築できます。

### クリーンアップ（オプション）

練習が終わったら、LocalStackコンテナを停止・削除できます。

```bash
docker stop localstack
docker rm localstack
```
