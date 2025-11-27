#!/bin/bash

# MalCheck - マルウェアチェックスクリプト（高速版）
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
TEMP_RESULT_FILE=$(mktemp)
echo "0" > "$TEMP_COUNT_FILE"

# クリーンアップ用のトラップ
trap "rm -f $TEMP_COUNT_FILE $TEMP_RESULT_FILE" EXIT

# =====================================================
# チェック1: package.jsonファイル内の疑わしいnpmパッケージ
# =====================================================
echo -e "${BLUE}[チェック1] package.jsonファイルの検査${NC}"
echo "---------------------------------------------------"

# 疑わしいパッケージリストを配列に読み込む（空行とコメントを除外）
SUSPICIOUS_PACKAGES=()
while IFS= read -r line || [ -n "$line" ]; do
    # 空行とコメント行をスキップ
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    # 前後の空白を削除して配列に追加
    line=$(echo "$line" | xargs)
    if [ -n "$line" ]; then
        SUSPICIOUS_PACKAGES+=("$line")
    fi
done < "$PACKAGE_LIST_FILE"

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
            for SUSPICIOUS_PACKAGE in "${SUSPICIOUS_PACKAGES[@]}"; do
                # パッケージ名を検索（エスケープして安全に）
                if echo "$PKG_CONTENT" | grep -q "\"$SUSPICIOUS_PACKAGE\"" 2>/dev/null; then
                    echo -e "${RED}[警告] 疑わしいパッケージが検出されました！${NC}"
                    echo -e "  ファイル: ${YELLOW}$PKG_FILE${NC}"
                    echo -e "  パッケージ: ${RED}$SUSPICIOUS_PACKAGE${NC}"
                    echo ""
                    # カウントを増やす
                    CURRENT_COUNT=$(cat "$TEMP_COUNT_FILE")
                    echo $((CURRENT_COUNT + 1)) > "$TEMP_COUNT_FILE"
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
                
                # カウントを増やす
                CURRENT_COUNT=$(cat "$TEMP_COUNT_FILE")
                echo $((CURRENT_COUNT + 1)) > "$TEMP_COUNT_FILE"
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

# 最終カウントを取得
MALWARE_COUNT=$(cat "$TEMP_COUNT_FILE")

if [ $MALWARE_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ マルウェアや疑わしいファイルは検出されませんでした${NC}"
    echo -e "${GREEN}✓ システムは安全です${NC}"
    exit 0
else
    echo -e "${RED}⚠ 警告: $MALWARE_COUNT 件の疑わしいアイテムが検出されました！${NC}"
    echo -e "${RED}⚠ 詳細を確認し、必要に応じて対処してください${NC}"
    exit 1
fi

