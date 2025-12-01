# MalCheck - マルウェアチェックツール

指定されたパスの中にマルウェアがあるかどうかを確認するシェルスクリプトです。

注意：
- LLMで生成されていたスクリプトであり，このチェックを通しても絶対に安全とは言えません
- 感染されたnpm packageのリストの実効性も保証ありません
- 対象packageのバージョンは確認していないので検出されても，感染された前のバージョンである可能性が高い。現時点では個別に確認する必要がある。

## 感染されたnpm packageのリスト

- https://www.aikido.dev/blog/shai-hulud-strikes-again-hitting-zapier-ensdomains 
- https://github.com/wiz-sec-public/wiz-research-iocs/blob/main/reports/shai-hulud-2-packages.csv

## 機能

このスクリプトは以下の2つのチェックを実行します：

1. **package.json・package-lock.jsonファイルのチェック**
   - 指定されたパス内の全ての`package.json`および`package-lock.json`ファイルを検索
   - 疑わしいnpmパッケージがインストールされているかを確認
   - package-lock.jsonでは`packages`セクションと`dependencies`セクションの両方をチェック

2. **疑わしいファイル・フォルダの検出**
   - `setup_bun.js`
   - `bun_environment.js`
   - `.dev-env`
   
   これらのファイル・フォルダの存在を確認します。

## 使用方法

### 基本的な使い方

```bash
./malcheck.sh <検索パス> [npmパッケージリストファイル]
```

### パラメータ

- **第1パラメータ**: 検索したいパス（必須）
- **第2パラメータ**: 疑わしいnpmパッケージのリストファイル（省略可能）
  - 省略した場合、自動的にオンラインから最新のマルウェアDBをダウンロード
  - 指定した場合、そのローカルファイルを使用
  - オフライン時は`AffectedPackages.txt`をフォールバックとして使用

### 例

```bash
# カレントディレクトリをチェック（最新DBを自動取得）
./malcheck.sh .

# 特定のプロジェクトディレクトリをチェック（最新DBを自動取得）
./malcheck.sh /path/to/project

# ホームディレクトリ全体をチェック（最新DBを自動取得）
./malcheck.sh ~

# ローカルファイルを明示的に指定してチェック
./malcheck.sh . AffectedPackages.txt
```

### 自動更新機能

- マルウェアDBは24時間ごとに自動更新されます
- キャッシュは`$HOME/.malcheck_cache/`に保存されます
- オンライン取得に失敗した場合、以下の順でフォールバックします：
  1. 古いキャッシュファイル（存在する場合）
  2. ローカルの`AffectedPackages.txt`ファイル

## パッケージリストファイルの形式

`AffectedPackages.txt`ファイルには、1行に1つの疑わしいnpmパッケージ名を記載します：

```
@asyncapi/diff
@asyncapi/nodejs-ws-template
posthog-node
# コメント行も使用可能
kill-port
```

オンライン版では最新の脅威情報が含まれています。ローカルの`AffectedPackages.txt`には現在797個の既知のマルウェアパッケージがリストされています。

## 出力結果

スクリプトは以下の情報を表示します：

- **緑色（✓）**: 問題なし
- **赤色（⚠）**: マルウェアまたは疑わしいファイルが検出されました
- **黄色**: 情報表示

### 終了コード

- `0`: マルウェアが検出されませんでした（安全）
- `1`: マルウェアまたは疑わしいアイテムが検出されました

## セットアップ

1. スクリプトをダウンロード：
```bash
git clone <repository-url>
cd MalCheck
```

2. 実行権限を付与：
```bash
chmod +x malcheck.sh
```

3. 疑わしいパッケージリストを編集（必要に応じて）：
```bash
nano AffectedPackages.txt
```

4. スクリプトを実行：
```bash
# 最新DBを自動取得してチェック（推奨）
./malcheck.sh /path/to/check

# またはローカルファイルを指定
./malcheck.sh /path/to/check AffectedPackages.txt
```

## 要件

- Bash 4.0以上
- `find`コマンド
- `grep`コマンド
- `curl`または`wget`（オンライン更新機能を使用する場合）

## 注意事項

- このスクリプトは読み取り専用で、ファイルを変更・削除することはありません
- 大規模なディレクトリをスキャンする場合、時間がかかることがあります
- オンライン更新機能を使用する場合、マルウェアDBは24時間ごとに自動更新されます
- オフライン環境では定期的に`AffectedPackages.txt`を手動更新することを推奨します

## ライセンス

MIT License

