START_DIR=$(pwd)
PATCH_DIR="$(readlink -f "$(dirname "$(readlink -f "$0")")/../kernel-tree-scripts/")"
PATCH_PATH="$PATCH_DIR/wg.patch"

if [ ! -f "$PATCH_PATH" ]; then
    echo "Error: Patch '$PATCH_PATH' not found."
    exit 1
fi

TARGET_VER="5.6"

if [ -n "$1" ]; then
    TARGET_VER="$1"
fi

echo "TARGET:$TARGET_VER"

trap "cd $START_DIR" EXIT SIGINT SIGTERM

TMP_DIR="$PATCH_DIR/_tmp"
rm -rf "$TMP_DIR"

git clone --branch "v$TARGET_VER" --single-branch --depth 1 --no-checkout https://github.com/torvalds/linux "$TMP_DIR"
cd "$TMP_DIR"
git sparse-checkout set drivers/net/wireguard
git checkout

CODE_DIR="$TMP_DIR/drivers/net/wireguard"

if [ ! -d "$CODE_DIR" ]; then
    echo "Error: Directory '$CODE_DIR' does not exist."
    exit 1
fi

cd "$CODE_DIR"

echo "$CODE_DIR"

if patch -Np1 -f --dry-run < "$PATCH_PATH" > /dev/null 2>&1; then
    echo "Applying patch..."
    patch -Np1 -f < "$PATCH_PATH"
    echo "Patch applied."
    git status -s
else
    echo "Error: Conflict detected! Patch not applied."
    patch -Np1 -f --dry-run < "$PATCH_PATH"
    exit 1
fi