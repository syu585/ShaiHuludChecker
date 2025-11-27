#!/bin/bash

# MalCheck - マルウェアチェックスクリプト（最適化版・バージョンチェック対応）
# 使用方法: ./malcheck.sh <検索パス> <npmパッケージリストファイル>

set -e

# カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# パラメータチェック
if [ $# -ne 2 ]; then
    echo -e "${RED}エラー: パラメータが不足しています${NC}"
    echo "使用方法: $0 <検索パス> <npmパッケージリストファイル>"
    echo "例: $0 /path/to/search suspicious_packages.txt"
    exit 1
fi

SEARCH_PATH="$1"
PACKAGE_LIST_FILE="$2"

# 検索パスの確認
if [ ! -d "$SEARCH_PATH" ]; then
    echo -e "${RED}エラー: 指定されたパス '$SEARCH_PATH' が存在しません${NC}"
    exit 1
fi

# npmパッケージリストファイルの確認
if [ ! -f "$PACKAGE_LIST_FILE" ]; then
    echo -e "${RED}エラー: npmパッケージリストファイル '$PACKAGE_LIST_FILE' が存在しません${NC}"
    exit 1
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

# =====================================================
# チェック1: package.jsonファイル内の疑わしいnpmパッケージ
# =====================================================
echo -e "${BLUE}[チェック1] package.jsonファイルの検査（バージョンチェック対応）${NC}"
echo "---------------------------------------------------"

# 疑わしいパッケージリストを連想配列に読み込む（パッケージ名 -> バージョン）
declare -A SUSPICIOUS_PACKAGES_MAP
SUSPICIOUS_PACKAGES_NAMES=()

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
        SUSPICIOUS_PACKAGES_MAP["$package_name"]="$version_spec"
        SUSPICIOUS_PACKAGES_NAMES+=("$package_name")
    fi
done < "$PACKAGE_LIST_FILE"

echo -e "読み込まれた疑わしいパッケージ数: ${YELLOW}${#SUSPICIOUS_PACKAGES_NAMES[@]}${NC}"
echo ""

# package.jsonファイルを検索
mapfile -t PACKAGE_JSON_ARRAY < <(find "$SEARCH_PATH" -type f -name "package.json" 2>/dev/null)

if [ ${#PACKAGE_JSON_ARRAY[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ package.jsonファイルが見つかりませんでした${NC}"
else
    PACKAGE_JSON_COUNT=${#PACKAGE_JSON_ARRAY[@]}
    echo -e "見つかったpackage.jsonファイル数: ${YELLOW}$PACKAGE_JSON_COUNT${NC}"
    echo ""
    
    # 最適化：各ファイルを1回だけ読んで全パッケージをチェック
    for PKG_FILE in "${PACKAGE_JSON_ARRAY[@]}"; do
        # ファイル内容を一度だけ読み込む
        if [ -f "$PKG_FILE" ]; then
            PKG_CONTENT=$(cat "$PKG_FILE" 2>/dev/null || echo "")
            
            # 全ての疑わしいパッケージをチェック
            for PACKAGE_NAME in "${SUSPICIOUS_PACKAGES_NAMES[@]}"; do
                # 最適化：正規表現マッチングを使用（grep/sed/pipeの代わり）
                if [[ "$PKG_CONTENT" =~ \"$PACKAGE_NAME\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                    VERSION_IN_FILE="${BASH_REMATCH[1]}"
                    
                    # 疑わしいバージョン仕様を取得
                    VERSION_SPEC="${SUSPICIOUS_PACKAGES_MAP[$PACKAGE_NAME]}"
                    
                    # バージョンチェック
                    IS_SUSPICIOUS=false
                    
                    if [ -z "$VERSION_SPEC" ]; then
                        # バージョン指定がない場合は、パッケージ名のみで判定
                        IS_SUSPICIOUS=true
                    else
                        # バージョン仕様を解析（|| で区切られた複数バージョンに対応）
                        IFS='||' read -ra VERSION_PARTS <<< "$VERSION_SPEC"
                        for VERSION_PART in "${VERSION_PARTS[@]}"; do
                            # 前後の空白と "= " を削除（最適化版）
                            VERSION_PART=$(trim_whitespace "$VERSION_PART")
                            VERSION_PART="${VERSION_PART#=}"
                            VERSION_PART=$(trim_whitespace "$VERSION_PART")
                            
                            # バージョンが一致するかチェック（^や~などの範囲指定も考慮）
                            if [ -n "$VERSION_IN_FILE" ]; then
                                # 最適化：1回の正規化で処理
                                CLEAN_VERSION="${VERSION_IN_FILE#[~^]}"
                                CLEAN_PART="${VERSION_PART#[~^]}"
                                
                                if [[ "$VERSION_IN_FILE" == "$VERSION_PART" ]] || [[ "$CLEAN_VERSION" == "$CLEAN_PART" ]]; then
                                    IS_SUSPICIOUS=true
                                    break
                                fi
                            fi
                        done
                    fi
                    
                    if [ "$IS_SUSPICIOUS" = true ]; then
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
                        # カウントを増やす（最適化：ファイルI/Oの代わりに変数を使用）
                        ((MALWARE_COUNT++))
                    fi
                fi
            done
        fi
    done
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

# 全ての疑わしいアイテムを一度に検索
if [ ${#FIND_EXPR[@]} -gt 0 ]; then
    mapfile -t FOUND_ITEMS_ARRAY < <(find "$SEARCH_PATH" \( "${FIND_EXPR[@]}" \) 2>/dev/null)
    
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