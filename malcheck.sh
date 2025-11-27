#!/bin/bash

# MalCheck - マルウェアチェックスクリプト
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

# 検出カウンター（一時ファイルを使用してサブシェル問題を回避）
TEMP_COUNT_FILE=$(mktemp)
echo "0" > "$TEMP_COUNT_FILE"

# =====================================================
# チェック1: package.jsonファイル内の疑わしいnpmパッケージ
# =====================================================
echo -e "${BLUE}[チェック1] package.jsonファイルの検査${NC}"
echo "---------------------------------------------------"

# package.jsonファイルを検索
PACKAGE_JSON_FILES=$(find "$SEARCH_PATH" -type f -name "package.json" 2>/dev/null)

if [ -z "$PACKAGE_JSON_FILES" ]; then
    echo -e "${GREEN}✓ package.jsonファイルが見つかりませんでした${NC}"
else
    PACKAGE_JSON_COUNT=$(echo "$PACKAGE_JSON_FILES" | wc -l)
    echo -e "見つかったpackage.jsonファイル数: ${YELLOW}$PACKAGE_JSON_COUNT${NC}"
    echo ""
    
    # 疑わしいパッケージリストを読み込む
    while IFS= read -r SUSPICIOUS_PACKAGE || [ -n "$SUSPICIOUS_PACKAGE" ]; do
        # 空行とコメント行をスキップ
        if [ -z "$SUSPICIOUS_PACKAGE" ] || [[ "$SUSPICIOUS_PACKAGE" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # 前後の空白を削除
        SUSPICIOUS_PACKAGE=$(echo "$SUSPICIOUS_PACKAGE" | xargs)
        
        # 各package.jsonファイルをチェック
        while IFS= read -r PKG_FILE; do
            # package.json内でパッケージを検索
            if grep -q "\"$SUSPICIOUS_PACKAGE\"" "$PKG_FILE" 2>/dev/null; then
                echo -e "${RED}[警告] 疑わしいパッケージが検出されました！${NC}"
                echo -e "  ファイル: ${YELLOW}$PKG_FILE${NC}"
                echo -e "  パッケージ: ${RED}$SUSPICIOUS_PACKAGE${NC}"
                echo ""
                # カウントを増やす
                CURRENT_COUNT=$(cat "$TEMP_COUNT_FILE")
                echo $((CURRENT_COUNT + 1)) > "$TEMP_COUNT_FILE"
            fi
        done <<< "$PACKAGE_JSON_FILES"
    done < "$PACKAGE_LIST_FILE"
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

for ITEM in "${SUSPICIOUS_ITEMS[@]}"; do
    # ファイルまたはディレクトリを検索
    FOUND_ITEMS=$(find "$SEARCH_PATH" -name "$ITEM" 2>/dev/null)
    
    if [ -n "$FOUND_ITEMS" ]; then
        echo -e "${RED}[警告] 疑わしいアイテムが検出されました！${NC}"
        echo -e "  名前: ${RED}$ITEM${NC}"
        while IFS= read -r FOUND_PATH; do
            if [ -d "$FOUND_PATH" ]; then
                echo -e "  場所: ${YELLOW}$FOUND_PATH${NC} ${RED}(ディレクトリ)${NC}"
            else
                echo -e "  場所: ${YELLOW}$FOUND_PATH${NC} ${RED}(ファイル)${NC}"
            fi
            # カウントを増やす
            CURRENT_COUNT=$(cat "$TEMP_COUNT_FILE")
            echo $((CURRENT_COUNT + 1)) > "$TEMP_COUNT_FILE"
        done <<< "$FOUND_ITEMS"
        echo ""
    else
        echo -e "${GREEN}✓ '$ITEM' は見つかりませんでした${NC}"
    fi
done

echo ""

# =====================================================
# 結果サマリー
# =====================================================
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    検査結果${NC}"
echo -e "${BLUE}================================================${NC}"

# 最終カウントを取得
MALWARE_COUNT=$(cat "$TEMP_COUNT_FILE")
rm -f "$TEMP_COUNT_FILE"

if [ $MALWARE_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ マルウェアや疑わしいファイルは検出されませんでした${NC}"
    echo -e "${GREEN}✓ システムは安全です${NC}"
    exit 0
else
    echo -e "${RED}⚠ 警告: $MALWARE_COUNT 件の疑わしいアイテムが検出されました！${NC}"
    echo -e "${RED}⚠ 詳細を確認し、必要に応じて対処してください${NC}"
    exit 1
fi

