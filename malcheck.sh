#!/bin/bash

# MalCheck - マルウェアチェックスクリプト（最適化版・バージョンチェック対応・自動更新機能付き）
# 使用方法: ./malcheck.sh <検索パス> [パッケージリストファイル]
# パッケージリストファイルを省略した場合、自動的にオンラインから最新版をダウンロードします

set -e

# カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 設定
MALWARE_DB_URL="https://raw.githubusercontent.com/wiz-sec-public/wiz-research-iocs/refs/heads/main/reports/shai-hulud-2-packages.csv"
CACHE_DIR="$HOME/.malcheck_cache"
CACHE_FILE="$CACHE_DIR/shai-hulud-2-packages.csv"
FALLBACK_FILE="AffectedPackages.txt"

# キャッシュディレクトリの作成
mkdir -p "$CACHE_DIR"

# マルウェアDBファイルのダウンロード・キャッシュ管理
download_malware_db() {
    local needs_download=true
    
    # キャッシュファイルが存在し、24時間以内に更新されているかチェック
    if [ -f "$CACHE_FILE" ]; then
        local file_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
        if [ $file_age -lt 86400 ]; then # 86400秒 = 24時間
            echo -e "${GREEN}✓ キャッシュされたマルウェアDBを使用します（${file_age}秒前に更新）${NC}"
            needs_download=false
        else
            echo -e "${YELLOW}キャッシュが古いため、最新版をダウンロードします...${NC}"
        fi
    else
        echo -e "${YELLOW}最新のマルウェアDBをダウンロードしています...${NC}"
    fi
    
    if [ "$needs_download" = true ]; then
        if command -v curl >/dev/null 2>&1; then
            if curl -s -L -o "$CACHE_FILE.tmp" "$MALWARE_DB_URL"; then
                mv "$CACHE_FILE.tmp" "$CACHE_FILE"
                echo -e "${GREEN}✓ 最新のマルウェアDBをダウンロードしました${NC}"
            else
                echo -e "${RED}警告: ダウンロードに失敗しました${NC}"
                rm -f "$CACHE_FILE.tmp"
                return 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q -O "$CACHE_FILE.tmp" "$MALWARE_DB_URL"; then
                mv "$CACHE_FILE.tmp" "$CACHE_FILE"
                echo -e "${GREEN}✓ 最新のマルウェアDBをダウンロードしました${NC}"
            else
                echo -e "${RED}警告: ダウンロードに失敗しました${NC}"
                rm -f "$CACHE_FILE.tmp"
                return 1
            fi
        else
            echo -e "${RED}警告: curlもwgetも見つかりません${NC}"
            return 1
        fi
    fi
    
    return 0
}

# パラメータチェック
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo -e "${RED}エラー: パラメータが正しくありません${NC}"
    echo "使用方法: $0 <検索パス> [npmパッケージリストファイル]"
    echo "例:"
    echo "  $0 /path/to/search                    # オンラインから最新DBを取得"
    echo "  $0 /path/to/search suspicious_packages.txt  # ローカルファイルを使用"
    exit 1
fi

SEARCH_PATH="$1"
PACKAGE_LIST_FILE="${2:-}"

# 検索パスの確認
if [ ! -d "$SEARCH_PATH" ]; then
    echo -e "${RED}エラー: 指定されたパス '$SEARCH_PATH' が存在しません${NC}"
    exit 1
fi

# パッケージリストファイルの決定
if [ -z "$PACKAGE_LIST_FILE" ]; then
    # 第2パラメータが指定されていない場合、オンラインから取得
    if download_malware_db; then
        PACKAGE_LIST_FILE="$CACHE_FILE"
        echo -e "${BLUE}オンライン最新版を使用: ${PACKAGE_LIST_FILE}${NC}"
    else
        # ダウンロードに失敗した場合のフォールバック
        if [ -f "$CACHE_FILE" ]; then
            PACKAGE_LIST_FILE="$CACHE_FILE"
            echo -e "${YELLOW}ダウンロードに失敗しましたが、古いキャッシュを使用します${NC}"
        elif [ -f "$FALLBACK_FILE" ]; then
            PACKAGE_LIST_FILE="$FALLBACK_FILE"
            echo -e "${YELLOW}オンライン取得に失敗したため、ローカルファイル '${FALLBACK_FILE}' を使用します${NC}"
        else
            echo -e "${RED}エラー: マルウェアDBファイルが取得できませんでした${NC}"
            echo "  - オンラインからのダウンロードに失敗"
            echo "  - ローカルキャッシュが存在しない"
            echo "  - フォールバックファイル '${FALLBACK_FILE}' が存在しない"
            exit 1
        fi
    fi
else
    # 第2パラメータが指定されている場合、そのファイルを使用
    if [ ! -f "$PACKAGE_LIST_FILE" ]; then
        echo -e "${RED}エラー: 指定されたパッケージリストファイル '$PACKAGE_LIST_FILE' が存在しません${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    MalCheck - マルウェアチェック開始${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "検索パス: ${YELLOW}$SEARCH_PATH${NC}"
echo -e "パッケージリスト: ${YELLOW}$PACKAGE_LIST_FILE${NC}"
echo ""

# 検出カウンター（変数を使用 - ファイルI/O削減）
MALWARE_COUNT=0

# 空白削除用のヘルパー関数（xargsの代わり）
trim_whitespace() {
    local var="$1"
    # 先頭の空白を削除
    var="${var#"${var%%[![:space:]]*}"}"
    # 末尾の空白を削除
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# バージョンチェック共通関数
check_suspicious_version() {
    local package_name="$1"
    local version_in_file="$2"
    local version_spec="$3"
    
    if [ -z "$version_spec" ]; then
        # バージョン指定がない場合は、パッケージ名のみで判定
        return 0  # true (suspicious)
    else
        # バージョン仕様を解析（|| で区切られた複数バージョンに対応）
        IFS='||' read -ra VERSION_PARTS <<< "$version_spec"
        for VERSION_PART in "${VERSION_PARTS[@]}"; do
            # 前後の空白と "= " を削除
            VERSION_PART=$(trim_whitespace "$VERSION_PART")
            VERSION_PART="${VERSION_PART#=}"
            VERSION_PART=$(trim_whitespace "$VERSION_PART")
            
            # バージョンが一致するかチェック（^や~などの範囲指定も考慮）
            if [ -n "$version_in_file" ]; then
                # 最適化：1回の正規化で処理
                CLEAN_VERSION="${version_in_file#[~^]}"
                CLEAN_PART="${VERSION_PART#[~^]}"
                
                if [[ "$version_in_file" == "$VERSION_PART" ]] || [[ "$CLEAN_VERSION" == "$CLEAN_PART" ]]; then
                    return 0  # true (suspicious)
                fi
            fi
        done
    fi
    
    return 1  # false (not suspicious)
}

# =====================================================
# チェック1: package.json・package-lock.jsonファイル内の疑わしいnpmパッケージ
# =====================================================
echo -e "${BLUE}[チェック1] package.json・package-lock.jsonファイルの検査（バージョンチェック対応）${NC}"
echo "---------------------------------------------------"

# 疑わしいパッケージリストを配列に読み込む（Bash 3.x互換）
SUSPICIOUS_PACKAGES_NAMES=()
SUSPICIOUS_PACKAGES_VERSIONS=()

line_num=0
while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    
    # ヘッダー行、空行、コメント行をスキップ
    if [ $line_num -eq 1 ] || [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # CSV形式をパース（パッケージ名,バージョン）
    IFS=',' read -r package_name version_spec <<< "$line"
    
    # 前後の空白を削除（最適化：xargsの代わりにBashネイティブ機能を使用）
    package_name=$(trim_whitespace "$package_name")
    version_spec=$(trim_whitespace "$version_spec")
    
    if [ -n "$package_name" ]; then
        SUSPICIOUS_PACKAGES_NAMES+=("$package_name")
        SUSPICIOUS_PACKAGES_VERSIONS+=("$version_spec")
    fi
done < "$PACKAGE_LIST_FILE"

echo -e "読み込まれた疑わしいパッケージ数: ${YELLOW}${#SUSPICIOUS_PACKAGES_NAMES[@]}${NC}"
echo ""

# package.jsonとpackage-lock.jsonファイルを検索（Bash 3.x互換）
PACKAGE_JSON_ARRAY=()
PACKAGE_LOCK_ARRAY=()
OLD_IFS="$IFS"
IFS=$'\n'
PACKAGE_JSON_ARRAY=($(find "$SEARCH_PATH" -type f -name "package.json" 2>/dev/null))
PACKAGE_LOCK_ARRAY=($(find "$SEARCH_PATH" -type f -name "package-lock.json" 2>/dev/null))
IFS="$OLD_IFS"

TOTAL_FILES=$((${#PACKAGE_JSON_ARRAY[@]} + ${#PACKAGE_LOCK_ARRAY[@]}))

if [ $TOTAL_FILES -eq 0 ]; then
    echo -e "${GREEN}✓ package.json・package-lock.jsonファイルが見つかりませんでした${NC}"
else
    echo -e "見つかったファイル数: package.json=${YELLOW}${#PACKAGE_JSON_ARRAY[@]}${NC}個, package-lock.json=${YELLOW}${#PACKAGE_LOCK_ARRAY[@]}${NC}個"
    echo ""
    
    # package.jsonファイルのチェック
    if [ ${#PACKAGE_JSON_ARRAY[@]} -gt 0 ]; then
        echo -e "${BLUE}package.jsonファイルをチェック中...${NC}"
        for PKG_FILE in "${PACKAGE_JSON_ARRAY[@]}"; do
            # ファイル内容を一度だけ読み込む
            if [ -f "$PKG_FILE" ]; then
                PKG_CONTENT=$(cat "$PKG_FILE" 2>/dev/null || echo "")
                
                # 全ての疑わしいパッケージをチェック
                for i in "${!SUSPICIOUS_PACKAGES_NAMES[@]}"; do
                    PACKAGE_NAME="${SUSPICIOUS_PACKAGES_NAMES[$i]}"
                    VERSION_SPEC="${SUSPICIOUS_PACKAGES_VERSIONS[$i]}"
                    
                    # 最適化：正規表現マッチングを使用（grep/sed/pipeの代わり）
                    if [[ "$PKG_CONTENT" =~ \"$PACKAGE_NAME\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                        VERSION_IN_FILE="${BASH_REMATCH[1]}"
                        
                        # バージョンチェック（共通関数に移行）
                        if check_suspicious_version "$PACKAGE_NAME" "$VERSION_IN_FILE" "$VERSION_SPEC"; then
                            echo -e "${RED}[警告] 疑わしいパッケージが検出されました！${NC}"
                            echo -e "  ファイル: ${YELLOW}$PKG_FILE${NC}"
                            echo -e "  パッケージ: ${RED}$PACKAGE_NAME${NC}"
                            if [ -n "$VERSION_IN_FILE" ]; then
                                echo -e "  検出バージョン: ${RED}$VERSION_IN_FILE${NC}"
                            fi
                            if [ -n "$VERSION_SPEC" ]; then
                                echo -e "  疑わしいバージョン: ${RED}$VERSION_SPEC${NC}"
                            fi
                            echo ""
                            ((MALWARE_COUNT++))
                        fi
                    fi
                done
            fi
        done
    fi
    
    # package-lock.jsonファイルのチェック
    if [ ${#PACKAGE_LOCK_ARRAY[@]} -gt 0 ]; then
        echo -e "${BLUE}package-lock.jsonファイルをチェック中...${NC}"
        for LOCK_FILE in "${PACKAGE_LOCK_ARRAY[@]}"; do
            # ファイル内容を一度だけ読み込む
            if [ -f "$LOCK_FILE" ]; then
                LOCK_CONTENT=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
                
                # 全ての疑わしいパッケージをチェック
                for i in "${!SUSPICIOUS_PACKAGES_NAMES[@]}"; do
                    PACKAGE_NAME="${SUSPICIOUS_PACKAGES_NAMES[$i]}"
                    VERSION_SPEC="${SUSPICIOUS_PACKAGES_VERSIONS[$i]}"
                    
                    # package-lock.jsonでは "packages" セクション内と "dependencies" セクション内をチェック
                    # パターン1: "packages" セクション ("node_modules/パッケージ名": { "version": "x.y.z" })
                    if [[ "$LOCK_CONTENT" =~ \"node_modules/$PACKAGE_NAME\"[[:space:]]*:[[:space:]]*\{[^}]*\"version\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                        VERSION_IN_FILE="${BASH_REMATCH[1]}"
                        
                        if check_suspicious_version "$PACKAGE_NAME" "$VERSION_IN_FILE" "$VERSION_SPEC"; then
                            echo -e "${RED}[警告] 疑わしいパッケージが検出されました！${NC}"
                            echo -e "  ファイル: ${YELLOW}$LOCK_FILE${NC} (packagesセクション)"
                            echo -e "  パッケージ: ${RED}$PACKAGE_NAME${NC}"
                            echo -e "  検出バージョン: ${RED}$VERSION_IN_FILE${NC}"
                            if [ -n "$VERSION_SPEC" ]; then
                                echo -e "  疑わしいバージョン: ${RED}$VERSION_SPEC${NC}"
                            fi
                            echo ""
                            ((MALWARE_COUNT++))
                        fi
                    # パターン2: "dependencies" セクション ("パッケージ名": { "version": "x.y.z" })
                    elif [[ "$LOCK_CONTENT" =~ \"$PACKAGE_NAME\"[[:space:]]*:[[:space:]]*\{[^}]*\"version\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                        VERSION_IN_FILE="${BASH_REMATCH[1]}"
                        
                        if check_suspicious_version "$PACKAGE_NAME" "$VERSION_IN_FILE" "$VERSION_SPEC"; then
                            echo -e "${RED}[警告] 疑わしいパッケージが検出されました！${NC}"
                            echo -e "  ファイル: ${YELLOW}$LOCK_FILE${NC} (dependenciesセクション)"
                            echo -e "  パッケージ: ${RED}$PACKAGE_NAME${NC}"
                            echo -e "  検出バージョン: ${RED}$VERSION_IN_FILE${NC}"
                            if [ -n "$VERSION_SPEC" ]; then
                                echo -e "  疑わしいバージョン: ${RED}$VERSION_SPEC${NC}"
                            fi
                            echo ""
                            ((MALWARE_COUNT++))
                        fi
                    fi
                done
            fi
        done
    fi
fi

echo ""

# =====================================================
# チェック2: 疑わしいファイル・フォルダの存在確認
# =====================================================
echo -e "${BLUE}[チェック2] 疑わしいファイル・フォルダの検査${NC}"
echo "---------------------------------------------------"

# 検査対象のファイル・フォルダリスト
SUSPICIOUS_ITEMS=(
    "setup_bun.js"
    "bun_environment.js"
    ".dev-env"
)

# 最適化：1回のfindで全アイテムを検索
FIND_EXPR=()
for i in "${!SUSPICIOUS_ITEMS[@]}"; do
    if [ $i -eq 0 ]; then
        FIND_EXPR+=("-name" "${SUSPICIOUS_ITEMS[$i]}")
    else
        FIND_EXPR+=("-o" "-name" "${SUSPICIOUS_ITEMS[$i]}")
    fi
done

# 全ての疑わしいアイテムを一度に検索（Bash 3.x互換）
if [ ${#FIND_EXPR[@]} -gt 0 ]; then
    FOUND_ITEMS_ARRAY=()
    OLD_IFS="$IFS"
    IFS=$'\n'
    FOUND_ITEMS_ARRAY=($(find "$SEARCH_PATH" \( "${FIND_EXPR[@]}" \) 2>/dev/null))
    IFS="$OLD_IFS"
    
    # 各疑わしいアイテムに対して結果を整理して表示
    for ITEM in "${SUSPICIOUS_ITEMS[@]}"; do
        ITEM_FOUND=false
        for FOUND_PATH in "${FOUND_ITEMS_ARRAY[@]}"; do
            BASENAME=$(basename "$FOUND_PATH")
            if [ "$BASENAME" = "$ITEM" ]; then
                if [ "$ITEM_FOUND" = false ]; then
                    echo -e "${RED}[警告] 疑わしいアイテムが検出されました！${NC}"
                    echo -e "  名前: ${RED}$ITEM${NC}"
                    ITEM_FOUND=true
                fi
                
                if [ -d "$FOUND_PATH" ]; then
                    echo -e "  場所: ${YELLOW}$FOUND_PATH${NC} ${RED}(ディレクトリ)${NC}"
                else
                    echo -e "  場所: ${YELLOW}$FOUND_PATH${NC} ${RED}(ファイル)${NC}"
                fi
                
                # カウントを増やす（最適化：変数を使用）
                ((MALWARE_COUNT++))
            fi
        done
        
        if [ "$ITEM_FOUND" = true ]; then
            echo ""
        else
            echo -e "${GREEN}✓ '$ITEM' は見つかりませんでした${NC}"
        fi
    done
else
    for ITEM in "${SUSPICIOUS_ITEMS[@]}"; do
        echo -e "${GREEN}✓ '$ITEM' は見つかりませんでした${NC}"
    done
fi

echo ""

# =====================================================
# 結果サマリー
# =====================================================
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    検査結果${NC}"
echo -e "${BLUE}================================================${NC}"

# 最終カウントを取得（最適化：変数を直接使用）
if [ $MALWARE_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ マルウェアや疑わしいファイルは検出されませんでした${NC}"
    echo -e "${GREEN}✓ システムは安全です${NC}"
    exit 0
else
    echo -e "${RED}⚠ 警告: $MALWARE_COUNT 件の疑わしいアイテムが検出されました！${NC}"
    echo -e "${RED}⚠ 詳細を確認し、必要に応じて対処してください${NC}"
    exit 1
fi